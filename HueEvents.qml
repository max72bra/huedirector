import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "."
import "WallpaperSync.js" as WallpaperSync

// Daemon (one instance, unlike the bar widgets, one per bar). It owns the bridge state, the event stream,
// the polling and every command, shared with the widgets and the settings through
// PluginService.pluginDaemonInstances["hueDirector"]; it also runs the "System events" rules and the IPC.
// Rule per event: pluginData.event_<e>_target ("" | "grouped_light:<id>" | "light:<id>") and
// pluginData.event_<e>_action ("on" | "off" | "warm", "dim" on idle; default in defaultActions)
PluginComponent {
    id: root

    // --- Bridge state, in the shape built by HueBridge.normalize()
    readonly property var bridge: hueBridge
    readonly property var pairing: pairingItem
    property var rooms: []
    property var zones: []
    // Entertainment areas, used only for wallpaper sync
    property var areas: []
    property var lights: []
    // grouped_light of the whole home, for "all off"
    property string homeGroupedId: ""
    property string error: ""
    property bool loaded: false
    // False when there is no pairing or the bridge rejects the key
    property bool paired: true
    // The bridge answered with a different public key than at pairing (replaced bridge or another device)
    property bool certChanged: false
    readonly property bool needsPairing: !paired || certChanged
    // Unreachable lights keep their last reported state on the bridge: they never count as on
    readonly property int lightsOn: lights.filter(l => l.Reachable && l.HueData?.on?.on).length
    // Last error written to the log, so a bridge that stays offline doesn't log on every poll
    property string loggedError: ""

    // Shared by fetch and put. Returns true when err was handled as an error
    function handleError(err) {
        if (!err)
            return false;
        if (err !== loggedError)
            console.warn("Hue Director:", err);
        loggedError = err;
        if (err === "unpaired") {
            paired = false;
            error = "";
        } else if (err === "unreachable") {
            error = I18n.trFor("hueDirector", "Hue Bridge not reachable");
        } else if (err === "certchanged") {
            certChanged = true;
            error = I18n.trFor("hueDirector", "The bridge identity changed: pair again");
        } else {
            error = err;
        }
        return true;
    }

    function refresh() {
        if (!hueBridge.configured) {
            // Forgotten or never paired: drop the old bridge's rooms and lights (settings targets, IPC)
            paired = false;
            rooms = [];
            zones = [];
            areas = [];
            lights = [];
            homeGroupedId = "";
            loaded = false;
            return;
        }
        hueBridge.fetchAll((result, err) => {
            if (handleError(err))
                return;
            publish(result);
            error = "";
            loggedError = "";
            loaded = true;
            paired = true;
            certChanged = false;
            startEvents();
            syncAfterRefresh();
        });
    }

    // A HueBridge.normalize() result into the state the widgets and settings read
    function publish(result) {
        // Bridge order is not stable (scenes move after activation): sort everything by name
        const byName = (a, b) => (a.Name ?? "").localeCompare(b.Name ?? "");
        result.rooms.concat(result.zones).forEach(r => {
            r.Scenes.sort(byName);
            r.SmartScenes.sort(byName);
        });
        rooms = result.rooms.sort(byName);
        zones = result.zones.sort(byName);
        areas = result.areas.sort(byName);
        lights = result.lights.sort(byName);
        homeGroupedId = result.homeGroupedId;
    }

    // kind: "light" | "grouped_light" | "scene" | "smart_scene", body: Hue API v2 PUT body.
    // With the event stream up, the bridge's own event refreshes the state; otherwise refresh here
    function setResource(kind, id, body) {
        hueBridge.put(kind, id, body, err => {
            if (!handleError(err) && !eventsActive)
                refresh();
        });
    }

    // Rooms and zones are controlled through their grouped_light service
    function setRoom(room, body) {
        const groupedId = room?.GroupedLight?.HueData?.id;
        if (groupedId)
            setResource("grouped_light", groupedId, body);
    }

    function setColor(lightId, c) {
        setResource("light", lightId, { on: { on: true }, color: { xy: hueBridge.rgbToXy(c) } });
    }

    // Gradient lights: points (2..points_capable) spread along the light; mode optional (keeps the current one).
    // A point is the bridge's xy {x, y}, sent as is, or a color
    function setGradient(lightId, colors, mode) {
        const toXy = c => c.x !== undefined ? { x: c.x, y: c.y } : hueBridge.rgbToXy(c);
        const points = colors.map(c => ({ color: { xy: toXy(c) } }));
        if (points.length < 2)
            return;
        const gradient = { points: points };
        if (mode)
            gradient.mode = mode;
        setResource("light", lightId, { on: { on: true }, gradient: gradient });
    }

    // --- Wallpaper sync: the lights of one entertainment area take the wallpaper color at their position
    // (WallpaperSync.js), over plain REST: the area is never started. Only the hue comes from the image,
    // brightness is syncBrightness for every light. Saved in the plugin state: syncArea, syncBrightness;
    // Settings → syncRestore starts it again with the shell, syncMonitor picks the wallpaper
    property string syncAreaId: ""
    // Read once in Component.onCompleted: as a binding, saving it would re-evaluate it (binding loop)
    property int syncBrightness: 70
    // "" or why the wallpaper could not be read (video wallpaper, missing file, ...)
    property string syncError: ""
    property bool syncRestoreChecked: false
    // Bar widgets (HueDirector.qml) lend their Canvas to read the wallpaper: the daemon has no window
    // to paint one in. No widget on any bar, no sync
    property var syncSamplers: []
    readonly property bool syncAvailable: syncSamplers.length > 0

    function addSyncSampler(sampler) {
        if (!syncSamplers.includes(sampler))
            syncSamplers = syncSamplers.concat([sampler]);
        if (loaded)
            syncAfterRefresh();
    }

    function removeSyncSampler(sampler) {
        syncSamplers = syncSamplers.filter(s => s !== sampler);
    }

    // Bars are rebuilt on monitor and settings changes: the sync stops only if no widget comes back
    onSyncAvailableChanged: if (syncAvailable) syncUnavailableTimer.stop(); else if (syncAreaId) syncUnavailableTimer.restart()

    Timer {
        id: syncUnavailableTimer
        interval: 3000
        onTriggered: if (!root.syncAvailable) root.setSync("")
    }
    readonly property var syncArea: areas.find(a => a.Id === syncAreaId) ?? null

    // areaId "" stops the sync. Stopping, or moving to another area, puts the lights back as they were
    // before the sync (syncSnapshot); when that is unknown, Settings → syncEnd_<areaId> says what to do
    function setSync(areaId) {
        if (areaId && !syncAvailable)
            return;
        const previous = syncArea;
        // Lights shared with the area being left still show its wallpaper colors: their saved state comes from here
        let kept = null;
        if (syncAreaId && syncAreaId !== areaId) {
            kept = PluginService.loadPluginState("hueDirector", "syncSnapshot", null);
            syncEnd(previous);
        }
        syncAreaId = areaId;
        syncError = "";
        PluginService.savePluginState("hueDirector", "syncArea", areaId);
        if (!areaId)
            return;
        // Kept across restarts: a sync restored at startup must not save its own colors as the previous state
        if (!PluginService.loadPluginState("hueDirector", "syncSnapshot", null)) {
            const snap = syncSnapshot(syncArea);
            for (const id in kept ?? {})
                if (id in snap)
                    snap[id] = kept[id];
            PluginService.savePluginState("hueDirector", "syncSnapshot", snap);
        }
        syncNow(true);
    }

    // {lightId: PUT body} rebuilding each reachable light of the area: on, brightness, then gradient,
    // color temperature or color, whichever the light is using (a plain color clears the gradient points)
    function syncSnapshot(area) {
        const snap = {};
        for (const l of lights.filter(l => l.Reachable && (area?.LightIds ?? []).includes(l.Id))) {
            const hd = l.HueData;
            const body = { on: { on: !!hd.on?.on } };
            if (hd.dimming)
                body.dimming = { brightness: hd.dimming.brightness };
            if ((hd.gradient?.points ?? []).length >= 2)
                body.gradient = { points: hd.gradient.points.map(p => ({ color: { xy: p.color.xy } })), mode: hd.gradient.mode };
            else if (hd.color_temperature?.mirek_valid && hd.color_temperature.mirek)
                body.color_temperature = { mirek: hd.color_temperature.mirek };
            else if (hd.color?.xy)
                body.color = { xy: hd.color.xy };
            snap[l.Id] = body;
        }
        return snap;
    }

    // Saved snapshot back on the lights, or Settings → syncEnd_<areaId>: "off" (default), "none",
    // "warm" (2700 K at the sync brightness) or "scene:<id>"
    function syncEnd(area) {
        const snap = PluginService.loadPluginState("hueDirector", "syncSnapshot", null);
        PluginService.savePluginState("hueDirector", "syncSnapshot", null);
        if (snap) {
            for (const id in snap)
                setResource("light", id, snap[id]);
            return;
        }
        const end = pluginData?.["syncEnd_" + area?.Id] ?? "off";
        if (end === "off") {
            for (const id of area?.LightIds ?? [])
                setResource("light", id, { on: { on: false } });
        } else if (end === "warm") {
            for (const id of area?.LightIds ?? [])
                setResource("light", id, { on: { on: true }, dimming: { brightness: syncBrightness }, color_temperature: { mirek: 370 } });
        } else if (end.startsWith("scene:")) {
            setResource("scene", end.slice(6), { recall: { action: "active" } });
        }
    }

    function setSyncBrightness(value) {
        syncBrightness = value;
        PluginService.savePluginState("hueDirector", "syncBrightness", value);
        for (const id of syncArea?.LightIds ?? [])
            setResource("light", id, { on: { on: true }, dimming: { brightness: value } });
    }

    // First fetch with a bar widget around: restore the saved sync (Settings → syncRestore).
    // Later fetches: stop if the area is gone
    function syncAfterRefresh() {
        if (!syncRestoreChecked) {
            if (!syncAvailable)
                return;
            syncRestoreChecked = true;
            const saved = PluginService.loadPluginState("hueDirector", "syncArea", "");
            if (pluginData?.syncRestore && areas.some(a => a.Id === saved)) {
                setSync(saved);
            } else {
                // Not restored: lights are left alone at startup (a login rule may have just set them)
                PluginService.savePluginState("hueDirector", "syncArea", "");
                PluginService.savePluginState("hueDirector", "syncSnapshot", null);
            }
        } else if (syncAreaId && !syncArea) {
            setSync("");
        }
    }

    function syncWallpaper() {
        const screen = pluginData?.syncMonitor || (Quickshell.screens[0]?.name ?? "");
        return SessionData.getMonitorWallpaper(screen) ?? "";
    }

    // turnOn: starting the sync switches the area on; a wallpaper change only recolors the lights that are on
    function syncNow(turnOn) {
        const area = syncArea;
        if (!area || area.Active || !syncAvailable)
            return;
        const path = syncWallpaperPath;
        if (!path)
            return;
        // Solid color wallpaper: the same color everywhere
        if (path.startsWith("#")) {
            const c = Qt.color(path);
            const img = { w: 1, h: 1, px: [c.r, c.g, c.b] };
            syncApply(area, WallpaperSync.lightColors(area, img), turnOn);
            return;
        }
        // shortcut: the whole image is sampled, the wallpaper fill mode (crop) is ignored; crop it if lights look off
        syncSamplers[0].sample(path, img => {
            if (!img) {
                syncError = I18n.trFor("hueDirector", "Can't read the wallpaper");
                console.warn("Hue Director: wallpaper sync:", syncError, path);
                return;
            }
            syncError = "";
            // By id: every refresh rebuilds the area objects
            if (syncAreaId === area.Id)
                syncApply(area, WallpaperSync.lightColors(area, img), turnOn);
        });
    }

    // colorsByLight: {lightId: [[r, g, b], ...]} in strip order. Gradient lights get up to
    // points_capable colors, the others the middle one
    function syncApply(area, colorsByLight, turnOn) {
        const toXy = rgb => hueBridge.rgbToXy({ r: rgb[0], g: rgb[1], b: rgb[2] });
        for (const id in colorsByLight) {
            const light = lights.find(l => l.Id === id);
            const hd = light?.HueData;
            if (!hd || !light.Reachable || light.Streaming || (!turnOn && !hd.on?.on))
                continue;
            const colors = colorsByLight[id];
            const cap = hd.gradient?.points_capable ?? 0;
            const body = { dimming: { brightness: syncBrightness } };
            if (turnOn)
                body.on = { on: true };
            if (cap >= 2 && colors.length >= 2)
                body.gradient = { points: WallpaperSync.spread(colors, cap).map(c => ({ color: { xy: toXy(c) } })) };
            else if (hd.color)
                body.color = { xy: toXy(colors[Math.floor(colors.length / 2)]) };
            setResource("light", id, body);
        }
    }

    // Wallpaper changes come in bursts (light/dark switch, per-monitor updates): one sample after they settle
    Timer {
        id: syncTimer
        interval: 1000
        onTriggered: root.syncNow(false)
    }

    // Follows SessionData and Settings → syncMonitor (the binding tracks what syncWallpaper() reads)
    readonly property string syncWallpaperPath: syncWallpaper()
    onSyncWallpaperPathChanged: if (syncAreaId) syncTimer.restart()

    // A light another app is streaming to: commands to it are skipped until the stream ends
    function lightStreaming(id) {
        return lights.some(l => l.Id === id && l.Streaming);
    }

    // Favorite light, room, zone or whole home (Settings → Favorite light): bar right click and IPC toggle
    function toggleFavorite() {
        const t = hueBridge.parseTarget(pluginData?.favoriteLight);
        if (!t)
            return "no favorite light set";
        if (t.kind === "light" && lightStreaming(t.id))
            return "in use by another app";
        setResource(t.kind, t.id, { on: { on: !hueBridge.targetIsOn(t, root) } });
        return "ok";
    }

    // Why a brightness command can't go to a target, "" when it can. Plugs have no dimming and the bridge
    // would answer with an error; the home group isn't in rooms or zones and counts as dimmable
    function brightnessBlocked(t) {
        if (t.kind === "light" && lightStreaming(t.id))
            return "in use by another app";
        const hd = t.kind === "light" ? lights.find(l => l.Id === t.id)?.HueData : rooms.concat(zones).find(r => r.GroupedLight?.HueData?.id === t.id)?.GroupedLight.HueData;
        return hd && !hd.dimming ? "not dimmable" : "";
    }

    function setBrightness(t, value) {
        const blocked = brightnessBlocked(t);
        if (blocked)
            return blocked;
        setResource(t.kind, t.id, { on: { on: true }, dimming: { brightness: value } });
        return "ok";
    }

    // delta in points, signed. put() keeps only the last body of a burst, so a step adds to what is still
    // waiting: 5 fast wheel notches are one +50 request
    function stepBrightness(t, delta) {
        const blocked = brightnessBlocked(t);
        if (blocked)
            return blocked;
        const pending = hueBridge.pendingBodies[t.id];
        if (pending?.dimming)
            return setBrightness(t, Math.max(1, Math.min(100, pending.dimming.brightness + delta)));
        if (!(pending?.on?.on ?? hueBridge.targetIsOn(t, root)))
            return delta > 0 ? setBrightness(t, Math.min(100, delta)) : "ok";
        const waiting = pending?.dimming_delta;
        const sum = delta + (waiting ? (waiting.action === "up" ? 1 : -1) * waiting.brightness_delta : 0);
        setResource(t.kind, t.id, { dimming_delta: { action: sum < 0 ? "down" : "up", brightness_delta: Math.min(100, Math.abs(sum)) } });
        return "ok";
    }

    // Bar wheel on the favorite light, room, zone or whole home
    function wheelFavorite(delta) {
        const t = hueBridge.parseTarget(pluginData?.favoriteLight);
        if (t && !ipcReady())
            stepBrightness(t, delta);
    }

    // Timed effects (sunrise/sunset) need a duration: 30 minutes, like the Hue app default.
    // "no_effect" clears both kinds, since only one of them can be running
    function setEffect(light, value) {
        const timed = light?.HueData?.timed_effects?.effect_values ?? [];
        let body;
        if (value === "no_effect")
            body = { effects: { effect: "no_effect" } };
        else if (timed.includes(value))
            body = { on: { on: true }, timed_effects: { effect: value, duration: 1800000 } };
        else
            body = { on: { on: true }, effects: { effect: value } };
        if (value === "no_effect" && (light?.HueData?.timed_effects?.status ?? "no_effect") !== "no_effect")
            body.timed_effects = { effect: "no_effect" };
        setResource("light", light.Id, body);
    }

    // Effect on each light of a group that supports it (the bridge ignores effects on grouped_light), skipping
    // the ones another app streams to. group: {Name, LightIds}. Answers like the IPC calls
    function setGroupEffect(group, value) {
        const capable = lights.filter(l => (group?.LightIds ?? []).includes(l.Id) && (l.HueData?.effects?.effect_values ?? []).concat(l.HueData?.timed_effects?.effect_values ?? []).includes(value));
        const free = capable.filter(l => !l.Streaming);
        for (const l of free)
            setEffect(l, value);
        return !capable.length ? "effect not supported by " + group?.Name : free.length ? "ok" : "in use by another app";
    }

    // Soft blink: two brightness pulses in 2.5 s (4 steps of 625 ms, each a 600 ms fade), then back to the
    // light's previous state. Hue "breathe" can't be stopped and runs far longer on some lights.
    // Steps go straight to the bridge: the event stream updates the UI, no refresh per step
    readonly property int identifyStepMs: 625
    // light id -> remaining PUT bodies
    property var identifyQueue: ({})

    function identify(light) {
        const hd = light?.HueData;
        if (!hd || identifyQueue[light.Id])
            return;
        const fade = { duration: identifyStepMs - 25 };
        // Reported also while off: restored so the next switch-on keeps the user's brightness
        const bri = hd.dimming?.brightness ?? 100;
        let steps;
        if (hd.on?.on) {
            // Dim a bright light, brighten a dim one: the pulse must be visible either way
            const pulse = bri > 40 ? Math.max(1, Math.round(bri * 0.15)) : 100;
            steps = [pulse, bri, pulse, bri].map(b => ({ dimming: { brightness: b }, dynamics: fade }));
        } else {
            steps = [{ on: { on: true }, dimming: { brightness: 100 }, dynamics: fade }, { dimming: { brightness: 5 }, dynamics: fade }, { dimming: { brightness: bri }, dynamics: fade }, { on: { on: false }, dynamics: fade }];
        }
        identifyQueue = Object.assign({}, identifyQueue, { [light.Id]: steps });
        identifyStep();
        identifyTimer.start();
    }

    function identifyStep() {
        const next = {};
        for (const id in identifyQueue) {
            const steps = identifyQueue[id];
            hueBridge.put("light", id, steps[0], err => handleError(err));
            if (steps.length > 1)
                next[id] = steps.slice(1);
        }
        identifyQueue = next;
        if (Object.keys(next).length === 0)
            identifyTimer.stop();
    }

    Timer {
        id: identifyTimer
        interval: root.identifyStepMs
        repeat: true
        onTriggered: root.identifyStep()
    }

    // --- Live updates from the bridge event stream (SSE); polling is the safety net
    // Consecutive event stream failures; reset whenever a line arrives
    property int eventsRestarts: 0
    readonly property int maxEventsRestarts: 5
    readonly property bool eventsActive: eventsProcess.running && eventsRestarts <= maxEventsRestarts
    // Set while the stream is stopped on purpose (new pairing), so the exit isn't counted as a failure
    property bool eventsStopping: false

    // Called after every successful fetch: the bridge is reachable, so a stream that gave up
    // (eventsRestarts > max, e.g. laptop away from home) gets a fresh start
    function startEvents() {
        if (eventsProcess.running || eventsRestartTimer.running)
            return;
        if (eventsRestarts > maxEventsRestarts)
            eventsRestarts = 0;
        eventsProcess.running = true;
    }

    // Resource types shown by the UI; other events (sensors, ...) don't refresh
    readonly property var watchedTypes: ["light", "grouped_light", "scene", "smart_scene", "room", "zone", "zigbee_connectivity", "entertainment_configuration"]

    Process {
        id: eventsProcess
        command: ["curl", "-K", hueBridge.confPath, "-N", "-H", "Accept: text/event-stream", "--expand-url", "https://{{ip}}/eventstream/clip/v2"]
        onExited: (exitCode, exitStatus) => {
            // Stopped on purpose, or unpaired: refresh()/a new pairing starts it again
            if (root.eventsStopping || !root.paired) {
                root.eventsStopping = false;
                return;
            }
            if (++root.eventsRestarts > root.maxEventsRestarts) {
                console.warn("Hue Director: event stream keeps failing - falling back to polling");
                return;
            }
            eventsRestartTimer.restart();
        }
        stdout: SplitParser {
            // SSE frames: "id: ...", "data: [...]", and ": hi" keepalives.
            // Any line proves the stream works, keepalives included (quiet homes send no data for long).
            // Updates are merged into the last fetch with no request; anything else fetches again
            // (the debounce in HueBridge.fetchAll() collapses bursts into one request)
            onRead: line => {
                if (!line.trim())
                    return;
                root.eventsRestarts = 0;
                if (!line.startsWith("data:"))
                    return;
                let events = null;
                try {
                    events = JSON.parse(line.slice(5)).filter(ev => (ev.data ?? []).some(r => root.watchedTypes.includes(r.type)));
                } catch (e) {}
                if (events && !events.length)
                    return;
                if (events && root.loaded && hueBridge.applyEvents(events))
                    root.publishLater();
                else
                    root.refresh();
            }
        }
    }

    // Events come in bursts (a scene changes every light): one rebuild per burst
    function publishLater() {
        publishTimer.start();
    }

    Timer {
        id: publishTimer
        interval: 50
        onTriggered: root.publish(hueBridge.normalize(hueBridge.raw))
    }

    Timer {
        id: eventsRestartTimer
        interval: 5000
        onTriggered: eventsProcess.running = true
    }

    Timer {
        interval: root.eventsActive ? 300000 : 30000
        running: hueBridge.configured
        repeat: true
        onTriggered: root.refresh()
    }

    readonly property var defaultActions: ({
            login: "on", lock: "off", unlock: "on", monitorOff: "off", monitorOn: "on", logout: "off", sleep: "off", resume: "on", shutdown: "off", reboot: "off", nightOn: "warm", nightOff: "on", idle: "dim"
        })

    // shutdown marker: power off/reboot also end the graphical session, the logout hook must then stay quiet
    readonly property string shutdownMarker: "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hue-director-shutdown"

    function rule(e) {
        const t = hueBridge.parseTarget(pluginData?.["event_" + e + "_target"]);
        if (!t)
            return null;
        return { kind: t.kind, id: t.id, action: pluginData?.["event_" + e + "_action"] ?? defaultActions[e] };
    }

    // 2700 K, as the sync end "warm"
    function actionBody(action) {
        if (action === "warm")
            return { on: { on: true }, color_temperature: { mirek: 370 } };
        return { on: { on: action === "on" } };
    }

    // done() is always called, also when there is no rule, so sleep/shutdown can release the inhibitor.
    // Those pass done and run without the debounce: logind waits only a few seconds.
    // retries: attempts left when the bridge is unreachable, 2 s apart (resume: the network comes back later)
    function run(e, done, retries) {
        const r = hueBridge.configured ? rule(e) : null;
        if (!r) {
            done?.();
            return;
        }
        if (r.kind === "light" && lightStreaming(r.id)) {
            console.info("Hue Director: event", e, "skipped, light in use by another app");
            done?.();
            return;
        }
        console.info("Hue Director: event", e, "->", r.kind, r.id, r.action);
        if (r.action === "dim") {
            dimTarget(r);
            done?.();
            return;
        }
        hueBridge.put(r.kind, r.id, actionBody(r.action), err => {
            if (err === "unreachable" && retries > 0) {
                retryLater(() => run(e, done, retries - 1));
                return;
            }
            if (err)
                console.warn("Hue Director: event", e, "failed:", err);
            else
                console.info("Hue Director: event", e, "done");
            done?.();
        }, !!done);
    }

    // --- Idle: dim each light to a share of its own brightness, so lights already low don't get brighter.
    // shortcut: dimmed lives in memory, a shell restart during idle leaves the lights dimmed; persist it if that matters
    // light id -> { from, to }
    property var dimmed: ({})
    property int dimRetries: 0

    function dimTarget(t) {
        const ids = t.kind === "light" ? [t.id] : t.id === homeGroupedId ? lights.map(l => l.Id) : (rooms.concat(zones).find(r => r.GroupedLight?.HueData?.id === t.id)?.LightIds ?? []);
        const pct = pluginData?.dimPercent ?? 30;
        for (const l of lights.filter(l => ids.includes(l.Id) && l.Reachable && !l.Streaming && l.HueData?.on?.on && l.HueData?.dimming && !dimmed[l.Id])) {
            const from = l.HueData.dimming.brightness;
            const to = Math.max(1, Math.round(from * pct / 100));
            dimmed[l.Id] = { from: from, to: to };
            setResource("light", l.Id, { dimming: { brightness: to } });
        }
    }

    // Only lights still at the dimmed value (±2, the bridge's rounding): any other was changed meanwhile.
    // retries: after an idle that ended in a suspend the network comes back later
    function restoreDim(retries) {
        const saved = dimmed;
        dimmed = ({});
        for (const id in saved) {
            const l = lights.find(x => x.Id === id);
            if (!l || l.Streaming || Math.abs((l.HueData?.dimming?.brightness ?? -100) - saved[id].to) > 2)
                continue;
            hueBridge.put("light", id, { dimming: { brightness: saved[id].from } }, err => {
                if (err === "unreachable" && retries > 0) {
                    dimmed[id] = saved[id];
                    dimRetries = retries - 1;
                    dimRetryTimer.restart();
                } else {
                    handleError(err);
                }
            });
        }
    }

    Timer {
        id: dimRetryTimer
        interval: 2000
        onTriggered: root.restoreDim(root.dimRetries)
    }

    // Gated on the shell's inhibit state too: the compositor's goes inactive with a hidden bar (see IdleService)
    IdleMonitor {
        enabled: hueBridge.configured && !!root.rule("idle") && !SessionService.idleInhibited
        timeout: (root.pluginData?.idleMinutes ?? 5) * 60
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle)
                root.run("idle");
            else
                root.restoreDim(15);
        }
        onEnabledChanged: {
            if (!enabled)
                root.restoreDim(15);
        }
    }

    // --- Night mode. With the schedule on, nightModeEnabled stays true all day and gammaIsDay tells the period.
    // Pauses are ignored on purpose: fullscreen and excluded apps must not change the lights
    readonly property bool nightActive: NightModeService.nightModeEnabled && (!SessionData.nightModeAutoEnabled || !NightModeService.gammaIsDay)
    // Both values load after startup: those first changes aren't events
    property bool nightArmed: false

    onNightActiveChanged: {
        if (nightArmed)
            run(nightActive ? "nightOn" : "nightOff", null, 15);
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: root.nightArmed = true
    }

    // One pending retry at a time is enough: events of the same kind replace each other
    property var retryFn: null

    function retryLater(fn) {
        retryFn = fn;
        retryTimer.restart();
    }

    Timer {
        id: retryTimer
        interval: 2000
        onTriggered: {
            const fn = root.retryFn;
            root.retryFn = null;
            fn?.();
        }
    }

    Pairing {
        id: pairingItem
        bridge: hueBridge
    }

    HueBridge {
        id: hueBridge
        transitionMs: parseInt(root.pluginData?.transitionMs ?? "-1")
        // Startup or new pairing: reconnect the event stream with the new key/bridge (refresh() restarts it)
        onConfigChanged: {
            root.eventsRestarts = 0;
            if (eventsProcess.running) {
                root.eventsStopping = true;
                eventsProcess.running = false;
            }
            root.refresh();
            root.syncLogoutHook();
        }
    }

    // --- Command line / keybindings: dms ipc call hueDirector <function> [arg]. Uses the live state,
    // so calls answer with the outcome ("ok" or what is wrong)

    // "all", a room, zone or light name (case-insensitive); with the same name rooms win, then zones
    function findTarget(name) {
        const n = (name ?? "").trim().toLowerCase();
        if (n === "all")
            return homeGroupedId ? { kind: "grouped_light", id: homeGroupedId } : null;
        const group = rooms.concat(zones).find(r => r.Name.toLowerCase() === n && r.GroupedLight);
        if (group)
            return { kind: "grouped_light", id: group.GroupedLight.HueData.id };
        const light = lights.find(l => l.Name.toLowerCase() === n);
        return light ? { kind: "light", id: light.Id } : null;
    }

    function ipcReady() {
        return !hueBridge.configured ? "not paired" : !loaded ? "not connected to the bridge yet" : "";
    }

    function setTarget(name, on) {
        const t = findTarget(name);
        if (!t)
            return "no room, zone or light named " + name;
        if (t.kind === "light" && lightStreaming(t.id))
            return "in use by another app";
        setResource(t.kind, t.id, { on: { on: on } });
        return "ok";
    }

    // value: "50" absolute, "+10" or "-10" relative
    function setTargetBrightness(name, value) {
        const t = findTarget(name);
        if (!t)
            return "no room, zone or light named " + name;
        const m = /^([+-]?)(\d+)$/.exec((value ?? "").trim());
        const n = m ? parseInt(m[2]) : -1;
        if (n < 0 || n > 100)
            return "brightness must be 0-100, +n or -n";
        return m[1] ? stepBrightness(t, m[1] === "+" ? n : -n) : setBrightness(t, n);
    }

    // effect: bridge value (candle, fire, sunrise, ...) or "off"
    function setTargetEffect(name, effect) {
        const t = findTarget(name);
        if (!t)
            return "no room, zone or light named " + name;
        const n = (effect ?? "").trim().toLowerCase();
        // shortcut: "all" covers the lights in a room, not those only in a zone or in neither
        const group = t.kind === "light" ? { Name: name, LightIds: [t.id] } : t.id === homeGroupedId ? { Name: name, LightIds: [].concat(...rooms.map(r => r.LightIds)) } : rooms.concat(zones).find(r => r.GroupedLight?.HueData?.id === t.id);
        return setGroupEffect(group, n === "off" ? "no_effect" : n);
    }

    IpcHandler {
        target: "hueDirector"

        // Toggles the favorite light, room, zone or all lights (Settings → Favorite light)
        function toggle(): string {
            return root.ipcReady() || root.toggleFavorite();
        }

        function on(target: string): string {
            return root.ipcReady() || root.setTarget(target, true);
        }

        function off(target: string): string {
            return root.ipcReady() || root.setTarget(target, false);
        }

        // value: "50", "+10" or "-10"
        function brightness(target: string, value: string): string {
            return root.ipcReady() || root.setTargetBrightness(target, value);
        }

        // effect: bridge value (candle, fire, sunrise, ...) or "off"
        function effect(target: string, name: string): string {
            return root.ipcReady() || root.setTargetEffect(target, name);
        }

        // Wallpaper sync on an entertainment area (name, case-insensitive), or off
        function sync(area: string): string {
            const notReady = root.ipcReady();
            if (notReady)
                return notReady;
            const a = root.areas.find(r => r.Name.toLowerCase() === area.trim().toLowerCase());
            if (!a)
                return "no entertainment area named " + area;
            if (a.Active)
                return "in use by another app";
            if (!root.syncAvailable)
                return "wallpaper sync needs the Hue Director widget on a bar";
            root.setSync(a.Id);
            return "ok";
        }

        function syncOff(): string {
            root.setSync("");
            return "ok";
        }

        // "Scene" or "Room/Scene" (also "Zone/Scene") when the name exists in several groups (case-insensitive)
        function scene(name: string): string {
            const notReady = root.ipcReady();
            if (notReady)
                return notReady;
            const parts = name.split("/");
            const sceneName = parts.pop().trim().toLowerCase();
            const roomName = parts.join("/").trim().toLowerCase();
            const groups = root.rooms.concat(root.zones);
            const room = roomName ? groups.find(r => r.Name.toLowerCase() === roomName) : null;
            if (roomName && !room)
                return "no room or zone named " + roomName;
            // no Array.flatMap in the shell's JS engine
            const scenes = [].concat(...(room ? [room] : groups).map(r => r.Scenes));
            const sc = scenes.find(s => s.Name.toLowerCase() === sceneName);
            if (!sc)
                return "no scene named " + name;
            root.setResource("scene", sc.Id, { recall: { action: "active" } });
            return "ok";
        }
    }

    Component.onCompleted: {
        syncBrightness = PluginService.loadPluginState("hueDirector", "syncBrightness", 70);
        checkLogin();
    }

    // --- Login: the daemon also starts on shell restarts, so only a session younger than 2 minutes counts.
    // Wall clock on both sides (session Timestamp in µs from logind): a monotonic start against
    // /proc/uptime would count the time spent suspended before the login
    function checkLogin() {
        Proc.runCommand("hueDirector.events.login", ["sh", "-c", "p=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager GetSession s \"$XDG_SESSION_ID\" | cut -d'\"' -f2) && t=$(busctl get-property org.freedesktop.login1 \"$p\" org.freedesktop.login1.Session Timestamp | cut -d' ' -f2) && [ $(( $(date +%s) - t / 1000000 )) -lt 120 ]"], (stdout, exitCode) => {
            if (exitCode === 0)
                loginTimer.start();
        }, 0);
    }

    // The bridge config loads asynchronously right after startup
    Timer {
        id: loginTimer
        interval: 3000
        onTriggered: root.run("login")
    }

    // --- Monitors off / on: DPMS driven by the shell idle settings (IdleService.requestMonitorOff/On)
    Connections {
        target: IdleService
        function onMonitorsOffChanged() {
            root.run(IdleService.monitorsOff ? "monitorOff" : "monitorOn");
        }
    }

    // --- Lock / unlock
    Connections {
        target: SessionService
        function onSessionLocked() {
            root.run("lock");
        }
        function onSessionUnlocked() {
            root.run("unlock");
        }
        function onSleepRequestedChanged() {
            if (!SessionService.sleepRequested || root.earlySleep)
                return;
            root.earlySleep = true;
            earlySleepTimeout.restart();
            // done only skips the debounce: PrepareForSleep releases the inhibitor, not the answer
            root.run("sleep", () => {});
        }
    }

    // --- Suspend / resume. NetworkManager takes the network down as soon as logind announces the sleep
    // (PrepareForSleep), so the rule runs earlier when the shell starts the suspend (power menu, idle):
    // SessionService.sleepRequested turns true before logind is called. PrepareForSleep then releases
    // the inhibitor at once: the network is going down, waiting for the answer gains nothing.
    // Suspends the shell doesn't start (lid, terminal) still run on PrepareForSleep, racing the network
    property bool earlySleep: false

    function onPrepareForSleep(sleeping) {
        if (sleeping) {
            if (earlySleep) {
                inhibitor.released = true;
            } else {
                root.run("sleep", () => inhibitor.released = true);
            }
        } else {
            earlySleep = false;
            earlySleepTimeout.stop();
            inhibitor.released = false;
            // 15 attempts, 2 s apart: the network may need a while to come back after resume
            root.run("resume", null, 15);
        }
    }

    // A sleep request that never reaches logind (refused, cancelled) must not swallow the next one
    Timer {
        id: earlySleepTimeout
        interval: 30000
        onTriggered: root.earlySleep = false
    }

    // --- logind signals, watched with gdbus: the DMS server doesn't always forward PrepareForSleep and
    // PrepareForShutdown to the shell (lost by some server instances, not others).
    // PrepareForShutdownWithMetadata(true, {type}) tells power off and reboot apart (systemd >= 256), the
    // plain PrepareForShutdown(bool) is then ignored: logind sends both. (false) means cancelled or resumed
    property bool shutdownHasMetadata: false

    // "reboot" for reboot, kexec and soft-reboot; "shutdown" for poweroff, halt and when the type is unknown
    function shutdownEvent(type) {
        return ["reboot", "kexec", "soft-reboot"].includes(type) ? "reboot" : "shutdown";
    }

    // line: "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdownWithMetadata (true, {'type': <'poweroff'>})"
    function onLogindLine(line) {
        if (line === "metadata") {
            shutdownHasMetadata = true;
            return;
        }
        const m = /\.Manager\.(PrepareForSleep|PrepareForShutdown|PrepareForShutdownWithMetadata) \((true|false)/.exec(line);
        if (!m)
            return;
        const active = m[2] === "true";
        if (m[1] === "PrepareForSleep") {
            onPrepareForSleep(active);
            return;
        }
        if ((m[1] === "PrepareForShutdownWithMetadata") !== shutdownHasMetadata)
            return;
        console.info("Hue Director: logind", m[1], m[2]);
        if (active) {
            // Marker first: releasing the inhibitor lets the session end, and the logout hook must find it
            const event = shutdownEvent(/'type': <'([^']*)'>/.exec(line)?.[1] ?? "");
            Proc.runCommand("hueDirector.events.marker", ["sh", "-c", ": > \"" + root.shutdownMarker + "\""], () => run(event, () => inhibitor.released = true), 0);
        } else {
            Proc.runCommand("hueDirector.events.marker", ["sh", "-c", "rm -f \"" + root.shutdownMarker + "\""], () => {}, 0);
            inhibitor.released = false;
        }
    }

    Process {
        id: logindMonitor
        property bool warned: false

        running: !logindRestart.running
        command: ["sh", "-c", "gdbus introspect --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 | grep -q PrepareForShutdownWithMetadata && echo metadata\n"
            + "exec gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: line => root.onLogindLine(line)
        }
        onExited: exitCode => {
            if (!warned)
                console.warn("Hue Director: gdbus monitor exited (" + exitCode + "), sleep and power off rules wait for it to restart");
            warned = true;
            logindRestart.restart();
        }
    }

    Timer {
        id: logindRestart
        interval: 5000
    }

    // Also runs on shell exit and logout, when the logout hook must stay. Only a disabled or uninstalled
    // plugin (enabled turned false before the unload, or plugin.json gone) removes it; bridge.conf is kept
    Component.onDestruction: {
        inhibitor.running = false;
        Proc.runCommand("hueDirector.events.unload", ["sh", "-c", "[ \"$3\" = true ] && [ -f \"$2\" ] && exit 0\n"
            + "rm -f \"$1/logout.action\"\nsystemctl --user stop hue-director-session 2>/dev/null\nexit 0\n",
            "sh", Paths.strip(Paths.state) + "/plugins/hueDirector", Paths.strip(Qt.resolvedUrl("plugin.json")), String(SettingsData.getPluginSetting("hueDirector", "enabled", false))], () => {}, 0);
    }

    // --- Delay inhibitor: logind waits for it (up to InhibitDelayMaxSec, 5 s by default) before sleep or
    // power off, so the PUT can reach the bridge. Released as soon as the rule has run
    Process {
        id: inhibitor

        property bool released: false
        // A logout rule alone also holds "shutdown": the shutdown marker must be written before the session ends
        readonly property string what: [root.rule("sleep") ? "sleep" : "", root.rule("shutdown") || root.rule("reboot") || root.rule("logout") ? "shutdown" : ""].filter(w => w).join(":")
        readonly property bool wanted: what !== "" && hueBridge.configured && !released

        // Paused while inhibitorRestart runs, then started again by this binding
        running: wanted && !inhibitorRestart.running
        command: ["systemd-inhibit", "--what=" + what, "--mode=delay", "--who=Hue Director", "--why=Set the lights before sleep or power off", "sleep", "infinity"]
        // Logout scripts that kill the user's processes before calling systemctl poweroff/reboot take
        // "sleep" down too, which drops the lock. Started again at once: a new process usually escapes
        // such scripts, which collect the processes to kill up front
        onExited: if (wanted) inhibitorRestart.restart()
        // A running process keeps its old --what: restart it with the new rules
        onCommandChanged: if (running) inhibitorRestart.restart()
    }

    Timer {
        id: inhibitorRestart
        interval: 1000
    }

    // --- Logout: the shell dies with the session, so a transient user unit bound to graphical-session.target
    // sends the PUT from its ExecStop. The hook reads logout.action, so rule changes never restart the unit.
    // shortcut: the hook can't tell a light another app is streaming to, its PUT is sent anyway (the bridge ignores it)
    readonly property string hookScript: "#!/bin/sh\n"
        + "# Hue Director logout action, run by hue-director-session.service (ExecStop) when the graphical session ends\n"
        + "d=$(dirname \"$0\")\n"
        + "[ -e \"" + shutdownMarker + "\" ] && exit 0\n"
        + "[ -f \"$d/logout.action\" ] || exit 0\n"
        + "{ read -r p; read -r b; } < \"$d/logout.action\"\n"
        + "exec curl -K \"$d/bridge.conf\" -m 4 -X PUT -H 'Content-Type: application/json' --expand-url \"https://{{ip}}/clip/v2/$p\" --data \"$b\"\n"

    // $1 state dir, $2 hook script, $3 action path ("" removes the action), $4 action body
    readonly property string syncScript: "umask 077; mkdir -p \"$1\" || exit 1\n"
        + "if [ -z \"$3\" ]; then rm -f \"$1/logout.action\"; exit 0; fi\n"
        + "printf '%s' \"$2\" > \"$1/logout-hook.sh\" && printf '%s\\n%s\\n' \"$3\" \"$4\" > \"$1/logout.action\" || exit 1\n"
        + "systemctl --user is-active --quiet graphical-session.target || exit 3\n"
        + "systemctl --user is-active --quiet hue-director-session && exit 0\n"
        + "exec systemd-run --user --quiet --unit=hue-director-session --description='Hue Director logout action' -p PartOf=graphical-session.target -p After=graphical-session.target -p Type=oneshot -p RemainAfterExit=yes -p \"ExecStop=/bin/sh '$1/logout-hook.sh'\" /bin/true\n"

    // Path and body of the logout PUT, "" without a rule: the hook is set up again only when this changes
    readonly property var logoutAction: {
        const r = hueBridge.configured ? rule("logout") : null;
        return r ? ["resource/" + r.kind + "/" + r.id, JSON.stringify(actionBody(r.action))] : ["", ""];
    }
    readonly property string logoutKey: logoutAction.join("\n")
    onLogoutKeyChanged: syncLogoutHook()

    function syncLogoutHook() {
        Proc.runCommand("hueDirector.events.logout", ["sh", "-c", syncScript, "sh", hueBridge.stateDir, hookScript, logoutAction[0], logoutAction[1]], (stdout, exitCode) => {
            if (exitCode === 3)
                console.warn("Hue Director: no systemd graphical session, the logout rule can't run");
            else if (exitCode !== 0)
                console.warn("Hue Director: logout hook setup failed (exit", exitCode + ")");
        }, 500);
    }

}
