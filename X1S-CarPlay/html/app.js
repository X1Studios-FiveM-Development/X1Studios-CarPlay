// ==============================
// Global State
// ==============================
window.playing = false;
window.queue = [];
window.queueActive = false;
window.currentSong = null;
window.savedSongs = [];

let maxVolume = 1.0;
let volumeStep = 0.05;
let currentVolume = 0.5;
let submitting = false;

const app = document.getElementById("app");
const mainUI = document.getElementById("mainUI");
const linkInput = document.getElementById("link");
const linkError = document.getElementById("linkError");
const title = document.getElementById("title");
const artist = document.getElementById("artist");
const album = document.getElementById("album");
const artPlaceholder = document.getElementById("artPlaceholder");
const bar = document.getElementById("bar");
const timeCur = document.getElementById("timeCur");
const timeDur = document.getElementById("timeDur");
const playPauseBtn = document.getElementById("playpause");
// SVG icons (same box size) so the button never resizes when toggling.
const PLAY_ICON = '<svg viewBox="0 0 24 24" width="22" height="22"><path d="M7 4.5v15l12-7.5-12-7.5z" fill="currentColor"/></svg>';
const PAUSE_ICON = '<svg viewBox="0 0 24 24" width="22" height="22"><rect x="6" y="4.5" width="4" height="15" rx="1" fill="currentColor"/><rect x="14" y="4.5" width="4" height="15" rx="1" fill="currentColor"/></svg>';
const playBtn = document.getElementById("playbtn");
const queueBtn = document.getElementById("queuebtn");
const startQueueBtn = document.getElementById("startQueueBtn");
const startQueueBtn2 = document.getElementById("startQueueBtn2");
const queuePanel = document.getElementById("queuePanel");
const queueList = document.getElementById("queueList");
const savedPanel = document.getElementById("savedPanel");
const savedList = document.getElementById("savedList");
const saveCurrentBtn = document.getElementById("saveCurrentBtn");
const saveCurrentBtn2 = document.getElementById("saveCurrentBtn2");
const volPct = document.getElementById("volPct");
const volUpBtn = document.getElementById("volUp");
const volDownBtn = document.getElementById("volDown");
const progressTrack = document.getElementById("progressTrack");

const skipbtn = document.getElementById("skipbtn");
const restartbtn = document.getElementById("restartbtn");

const toastContainer = document.getElementById("toastContainer");

// How long the open/close animations take (ms) - kept in sync with the
// CSS transition durations on .carplay / .vol-rail / .queuePanel /
// .savedPanel, so display:none is only applied once they've actually
// finished animating out.
const UI_ANIM_MS = 260;

const linkModalOverlay = document.getElementById("linkModalOverlay");
const linkModalTitle = document.getElementById("linkModalTitle");
const linkModalInput = document.getElementById("linkModalInput");
const linkModalError = document.getElementById("linkModalError");
const linkModalSubmit = document.getElementById("linkModalSubmit");
let linkModalMode = null; // "song" or "playlist" - which action the shared modal is currently wired to

const toggleSavedBtn = document.getElementById("toggleSavedBtn");
const toggleQueueBtn = document.getElementById("toggleQueueBtn");
const savedCountEl = document.getElementById("savedCount");
const queueCountEl = document.getElementById("queueCount");

// Mini Player (persistent now-playing widget, see app.js "Mini Player" section below)
const toggleMiniBtn = document.getElementById("toggleMiniBtn");
const miniPlayer = document.getElementById("miniPlayer");
const miniAlbum = document.getElementById("miniAlbum");
const miniArtPlaceholder = document.getElementById("miniArtPlaceholder");
const miniTitle = document.getElementById("miniTitle");
const miniArtist = document.getElementById("miniArtist");
const miniBar = document.getElementById("miniBar");
const miniTimeCur = document.getElementById("miniTimeCur");
const miniTimeDur = document.getElementById("miniTimeDur");
const miniVolume = document.getElementById("miniVolume");

let currentDuration = 0;
let seeking = false;

// Side panels start closed every time the menu is opened - they're
// revealed with the Saved/Queue toggle buttons on the main head unit.
let queuePanelOpen = false;
let savedPanelOpen = false;

// Whether the Mini Player widget is turned on FOR THE VEHICLE THE PLAYER IS
// IN. The choice is saved per vehicle by client.lua (KVP, keyed by plate)
// and pushed here with the "miniPlayerState" message whenever a vehicle is
// entered, so one car can have it on while another has it off.
let miniPlayerEnabled = false;

// Whether the player is currently inside a vehicle - the Mini Player
// should never show while on foot, even if it's turned on. Kept in sync
// via the "vehicleState" NUI message from client.lua.
let inVehicle = false;

// ==============================
// Helpers
// ==============================
function formatTime(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${s.toString().padStart(2, "0")}`;
}

function clamp(v, min, max) {
    return Math.min(max, Math.max(min, v));
}

// ==============================
// Toast Notifications
// ==============================
// Confirmation ("success") or error feedback for actions like saving a
// song, importing a playlist, starting the queue, etc. Called either
// directly (for checks that never leave the client) or from the
// "notify" NUI message the server relays a real result through.
function showToast(message, type, duration) {
    if (!toastContainer || !message) return;

    const toast = document.createElement("div");
    toast.className = `toast toast-${type === "error" ? "error" : "success"}`;

    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.setAttribute("class", "toast-icon");
    icon.setAttribute("viewBox", "0 0 24 24");
    icon.innerHTML = type === "error"
        ? '<path d="M12 9v4M12 16.5h.01M10.3 3.9 2.6 17.5A2 2 0 0 0 4.3 20.5h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'
        : '<path d="M4 12.5 9.5 18 20 6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>';

    const text = document.createElement("span");
    text.textContent = message;

    toast.appendChild(icon);
    toast.appendChild(text);
    toastContainer.appendChild(toast);

    toast.offsetHeight; // force reflow so the enter transition actually runs
    toast.classList.add("toast-visible");

    setTimeout(() => {
        toast.classList.remove("toast-visible");
        setTimeout(() => toast.remove(), 240);
    }, duration || 3200);
}

// ==============================
// NUI Listener
// ==============================
window.addEventListener("message", (e) => {
    const data = e.data;

    switch (data.action) {

        case "show":
            app.style.display = "flex";
            mainUI.style.display = "block";

            // Main head unit is always visible; the side panels start
            // closed and only open when their toggle button is pressed.
            closePanel("queue");
            closePanel("saved");
            syncPanelHeights();

            // Force a reflow before adding the visibility class, so the
            // browser actually has a "before" state to transition from
            // instead of snapping straight to the open state.
            app.offsetHeight;
            app.classList.add("ui-visible");

            if (typeof data.maxVolume === "number") maxVolume = data.maxVolume;
            if (typeof data.volumeStep === "number") volumeStep = data.volumeStep;
            updateMiniPlayerVisibility(); // main UI just opened - hide the Mini Player while it's up
            break;

        case "hide":
            closeSettings();
            app.classList.remove("ui-visible");
            closePanel("queue");
            closePanel("saved");
            closeLinkModal();
            updateMiniPlayerVisibility(); // main UI just closed - Mini Player can reappear now

            // Give the fade/scale-out transition time to finish before
            // actually pulling the UI out of the layout.
            setTimeout(() => {
                if (app.classList.contains("ui-visible")) return; // reopened mid-animation
                app.style.display = "none";
                mainUI.style.display = "none";
            }, UI_ANIM_MS);
            break;

        case "notify":
            showToast(data.message, data.type);
            break;

        case "streamerMode":
            applyStreamerMode(data.enabled);
            break;

        case "progress":
            if (!data.duration || data.duration <= 0) return;
            currentDuration = data.duration;
            if (!seeking) {
                bar.style.width = clamp((data.current / data.duration) * 100, 0, 100) + "%";
                timeCur.textContent = formatTime(data.current);
            }
            timeDur.textContent = formatTime(data.duration);

            if (miniBar) miniBar.style.width = clamp((data.current / data.duration) * 100, 0, 100) + "%";
            if (miniTimeCur) miniTimeCur.textContent = formatTime(data.current);
            if (miniTimeDur) miniTimeDur.textContent = formatTime(data.duration);
            break;

        case "nowPlaying":
            window.currentSong = data.song || {};
            window.playing = !data.paused;

            title.innerText = window.currentSong.title || "Unknown Title";
            artist.innerText = window.currentSong.artist || "Unknown Artist";
            setAlbumArt(window.currentSong.thumbnail);

            if (miniTitle) miniTitle.innerText = window.currentSong.title || "Unknown Title";
            if (miniArtist) miniArtist.innerText = window.currentSong.artist || "Unknown Artist";
            setMiniAlbumArt(window.currentSong.thumbnail);

            playPauseBtn.innerHTML = window.playing ? PAUSE_ICON : PLAY_ICON;
            currentDuration = 0;
            seeking = false;
            bar.style.width = "0%";
            timeCur.textContent = "0:00";
            timeDur.textContent = "0:00";

            if (miniBar) miniBar.style.width = "0%";
            if (miniTimeCur) miniTimeCur.textContent = "0:00";
            if (miniTimeDur) miniTimeDur.textContent = "0:00";

            if (typeof data.volume === "number") setVolumeDisplay(data.volume);
            updateMiniPlayerVisibility();
            break;

        case "paused":
            window.playing = false;
            playPauseBtn.innerHTML = PLAY_ICON;
            break;

        case "resumed":
            window.playing = true;
            playPauseBtn.innerHTML = PAUSE_ICON;
            break;

        case "volumeSync":
            if (typeof data.volume === "number") setVolumeDisplay(data.volume);
            break;

        case "miniPlayerState":
            miniPlayerEnabled = !!data.enabled;
            if (toggleMiniBtn) {
                toggleMiniBtn.classList.toggle("active", miniPlayerEnabled);
                toggleMiniBtn.setAttribute("aria-pressed", miniPlayerEnabled ? "true" : "false");
            }
            updateMiniPlayerVisibility();
            break;

        case "vehicleState":
            inVehicle = !!data.inVehicle;
            updateMiniPlayerVisibility();
            break;

        case "stop":
            window.currentSong = null;
            window.playing = false;
            playPauseBtn.innerHTML = PLAY_ICON;
            currentDuration = 0;
            seeking = false;
            bar.style.width = "0%";
            timeCur.textContent = "0:00";
            timeDur.textContent = "0:00";
            title.innerText = "Nothing Playing";
            artist.innerText = "Paste a link below to get started";
            setAlbumArt(null);

            if (miniTitle) miniTitle.innerText = "Nothing Playing";
            if (miniArtist) miniArtist.innerText = "—";
            if (miniBar) miniBar.style.width = "0%";
            if (miniTimeCur) miniTimeCur.textContent = "0:00";
            if (miniTimeDur) miniTimeDur.textContent = "0:00";
            setMiniAlbumArt(null);
            updateMiniPlayerVisibility(); // nothing playing - Mini Player hides itself
            break;

        case "updateQueue":
            window.queue = data.queue || [];
            window.queueActive = !!data.queueActive;
            updateQueueUI();
            break;

        case "savedSongsSync":
            window.savedSongs = data.songs || [];
            updateSavedUI();
            break;

        case "playlistImportResult":
            handlePlaylistImportResult(data);
            break;
    }
});

function setAlbumArt(url) {
    if (url) {
        album.src = url;
        album.style.display = "block";
        artPlaceholder.style.display = "none";
    } else {
        album.removeAttribute("src");
        album.style.display = "none";
        artPlaceholder.style.display = "flex";
    }
}

function setVolumeDisplay(vol) {
    currentVolume = clamp(vol, 0, maxVolume);
    const pct = maxVolume > 0 ? Math.round((currentVolume / maxVolume) * 100) : 0;
    volPct.textContent = `${pct}%`;
    if (miniVolume) miniVolume.textContent = `${pct}%`;
}

// ==============================
// Mini Player
// ==============================
// A small always-available now-playing widget, positioned above the
// minimap. It mirrors the main head unit's song info (thumbnail, artist,
// title, song length, current volume) but is shown/hidden independently
// of #app, since its whole point is to still be visible once the main
// CarPlay menu is closed. Toggled on/off with the "Mini" button on the
// main head unit; the on/off choice is saved per vehicle by client.lua.
function setMiniAlbumArt(url) {
    if (!miniAlbum || !miniArtPlaceholder) return;
    if (url) {
        miniAlbum.src = url;
        miniAlbum.style.display = "block";
        miniArtPlaceholder.style.display = "none";
    } else {
        miniAlbum.removeAttribute("src");
        miniAlbum.style.display = "none";
        miniArtPlaceholder.style.display = "flex";
    }
}

// Tells client.lua whether the Mini Player is on, so it keeps sending
// now-playing/progress/volume updates while the main menu is closed
// (those are otherwise only sent while the main CarPlay UI is open).
function syncMiniPlayerEnabledToClient() {
    fetch(`https://${GetParentResourceName()}/miniPlayerToggle`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled: miniPlayerEnabled })
    }).catch(() => {});
}

// Mini Player shows whenever it's turned on, song playing or not - it
// only hides while the main head unit is open so the two don't overlap,
// then reappears the moment the main UI closes.
function updateMiniPlayerVisibility() {
    if (!miniPlayer) return;
    const mainOpen = app.classList.contains("ui-visible");
    const shouldShow = settingsView === "position" || (miniPlayerEnabled && !mainOpen && inVehicle);
    miniPlayer.classList.toggle("mini-visible", shouldShow);
}

// ==============================
// Settings Menu (Mini Player position)
// ==============================
// Opened from the gear button under the volume rail. While open, the main
// CarPlay UI is hidden (#app.settings-open) and the Mini Player is forced
// visible so it can be nudged around with the +/- buttons. Save stores the
// offset; closing the menu (X / Esc) brings the main UI back, and any
// unsaved nudges are reverted to the last saved position.
const MINI_POS_STORAGE_KEY = "x1s_carplay_miniPlayerPos";
const MINI_POS_STEP = 5; // px per click
const settingsMenu = document.getElementById("settingsMenu");
const posXVal = document.getElementById("posXVal");
const posYVal = document.getElementById("posYVal");
const settingsStatus = document.getElementById("settingsStatus");

let settingsOpen = false;
let settingsView = null; // null (closed) | "hub" | "accent" | "position"
let savedMiniPos = { x: 0, y: 0 };   // last saved offset (x: + right, y: + up)
let miniPos = { x: 0, y: 0 };        // current (possibly unsaved) offset

try {
    const raw = JSON.parse(localStorage.getItem(MINI_POS_STORAGE_KEY) || "null");
    if (raw && Number.isFinite(raw.x) && Number.isFinite(raw.y)) savedMiniPos = { x: raw.x, y: raw.y };
} catch (e) { /* localStorage unavailable - default position */ }
miniPos = { ...savedMiniPos };

function isSettingsOpen() { return settingsOpen; }

function applyMiniPos() {
    if (!miniPlayer) return;
    miniPlayer.style.setProperty("--mini-x", miniPos.x + "px");
    miniPlayer.style.setProperty("--mini-y", miniPos.y + "px");
    if (posXVal) posXVal.value = miniPos.x;
    if (posYVal) posYVal.value = miniPos.y;

    const dirty = miniPos.x !== savedMiniPos.x || miniPos.y !== savedMiniPos.y;
    if (settingsStatus && (dirty || !settingsStatus.classList.contains("saved"))) {
        settingsStatus.textContent = dirty ? "Unsaved changes" : "";
        settingsStatus.className = "settings-status" + (dirty ? " dirty" : "");
    }
}

// Move one step on an axis, but never let the Mini Player leave the screen.
function nudgeMini(axis, dir) {
    const prev = { ...miniPos };
    miniPos[axis] += dir * MINI_POS_STEP;
    applyMiniPos();

    const r = miniPlayer.getBoundingClientRect();
    if (r.left < 0 || r.top < 0 || r.right > window.innerWidth || r.bottom > window.innerHeight) {
        miniPos = prev;
        applyMiniPos();
    }
    if (settingsStatus) settingsStatus.classList.remove("saved");
    applyMiniPos();
}

// ---- Views ----
//   hub, accent -> shown INSIDE the player box (main UI stays up, everything
//                  else greyed out, title reads "CarPlay Settings")
//   position    -> hides the whole main UI so the Mini Player can be seen and
//                  moved, in its own floating menu
const SETTINGS_PANEL_VIEWS = { hub: "settingsHub", accent: "settingsAccent" };
const SETTINGS_SUBTITLES = { hub: "Choose an option", accent: "Accent Color" };

// Everything greyed out while the settings are open also gets `inert`, so
// keyboard focus / Enter can't trigger it either (pointer-events is handled in CSS).
const SETTINGS_DIMMED_SELECTORS = [
    ".topbar", ".panel-toggles", ".progress", ".time-row", ".controls",
    ".link-row", ".link-actions", "#linkError", ".bottom-actions",
    "#volUp", "#volDown", ".vol-meter"
];
function setMainUiInert(on) {
    SETTINGS_DIMMED_SELECTORS.forEach((sel) => {
        document.querySelectorAll(sel).forEach((el) => { el.inert = on; });
    });
}

function renderSettingsView() {
    const boxView = settingsView === "accent" ? "accent" : "hub"; // position view hides the box anyway
    for (const key in SETTINGS_PANEL_VIEWS) {
        const el = document.getElementById(SETTINGS_PANEL_VIEWS[key]);
        if (el) el.classList.toggle("settings-view-active", key === boxView);
    }
    const sub = document.getElementById("settingsInfoSub");
    if (sub) sub.textContent = SETTINGS_SUBTITLES[boxView];
}

function showSettingsView(name) {
    settingsView = name;
    const inPosition = name === "position";
    renderSettingsView();
    app.classList.toggle("settings-open", inPosition);              // hides the whole main UI
    settingsMenu.classList.toggle("settings-visible", inPosition);  // floating position menu
    updateMiniPlayerVisibility();                                   // forces the Mini Player to show in that view
}

// Discards unsaved position nudges and clears the status line.
function resetPositionDraft() {
    miniPos = { ...savedMiniPos };
    if (settingsStatus) { settingsStatus.className = "settings-status"; settingsStatus.textContent = ""; }
    applyMiniPos();
}

// The gear button: opens the settings, press again to close them.
function openSettings() {
    if (settingsOpen) { closeSettings(); return; }
    settingsOpen = true;
    resetPositionDraft();

    closePanel("queue");
    closePanel("saved");
    if (typeof closeLinkModal === "function") closeLinkModal();

    app.classList.add("settings-active");
    setMainUiInert(true);
    showSettingsView("hub");
}

function openSettingsView(name) {
    if (name === "position") resetPositionDraft();
    showSettingsView(name);
}

function backToSettingsHub() {
    resetPositionDraft(); // leaving the position view without saving reverts it
    showSettingsView("hub");
}

// Esc: step back to the hub from a sub-view, close everything from the hub.
function settingsEscape() {
    if (settingsView !== "hub") backToSettingsHub();
    else closeSettings();
}

function savePosition() {
    savedMiniPos = { ...miniPos };
    try {
        localStorage.setItem(MINI_POS_STORAGE_KEY, JSON.stringify(savedMiniPos));
    } catch (e) { /* position just won't persist across restarts */ }
    if (settingsStatus) {
        settingsStatus.textContent = "Saved ✓";
        settingsStatus.className = "settings-status saved";
    }
}

function closeSettings() {
    if (!settingsOpen) return;
    settingsOpen = false;

    // Discard anything that wasn't saved.
    resetPositionDraft();

    settingsView = null;
    app.classList.remove("settings-active", "settings-open"); // main UI is back to normal
    settingsMenu.classList.remove("settings-visible");
    setMainUiInert(false);
    renderSettingsView();
    updateMiniPlayerVisibility();
}

// ==============================
// Streamer Mode
// ==============================
// Mutes every CarPlay sound for THIS player only (hooked into
// SoundPlayer.setVolume in xsound/SoundPlayer.js). Playback itself keeps
// running silently so the queue still advances for everyone else in the car.
// client.lua is the source of truth (saved with KVP, also togglable with the
// /streamermode command); localStorage just mirrors it so the mute is already
// in place the instant the page loads.
const STREAMER_STORAGE_KEY = "x1s_carplay_streamerMode";
let streamerMode = false;
try { streamerMode = localStorage.getItem(STREAMER_STORAGE_KEY) === "1"; } catch (e) {}
window.X1S_StreamerMode = streamerMode;

function applyStreamerMode(enabled) {
    streamerMode = !!enabled;
    window.X1S_StreamerMode = streamerMode;
    try { localStorage.setItem(STREAMER_STORAGE_KEY, streamerMode ? "1" : "0"); } catch (e) {}

    // Re-apply volume on every live sound so it mutes / unmutes immediately.
    try {
        // (soundList lives in xsound/listener.js; it may not exist yet at page load)
        for (const name in soundList) {
            try { const s = soundList[name]; if (s) s.setVolume(s.getVolume()); } catch (e) {}
        }
    } catch (e) {}

    const sw = document.getElementById("streamerSwitch");
    const opt = document.getElementById("streamerOption");
    const txt = document.getElementById("streamerStatusText");
    if (sw) sw.classList.toggle("on", streamerMode);
    if (opt) opt.setAttribute("aria-checked", streamerMode ? "true" : "false");
    if (txt) txt.textContent = streamerMode
        ? "On · music muted for you"
        : "Off · mutes music for you";
}

function toggleStreamerMode() {
    const next = !streamerMode;
    applyStreamerMode(next);
    fetch(`https://${GetParentResourceName()}/streamerMode`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled: next })
    }).catch(() => {});
}

// ==============================
// Accent Color
// ==============================
const ACCENT_STORAGE_KEY = "x1s_carplay_accent";
const ACCENTS = {
    red:    { label: "Red",    main: "#ff3049", dim: "#7a1c26", glow: "rgba(255, 48, 73, 0.35)" },
    blue:   { label: "Blue",   main: "#3a8dff", dim: "#1c3f7a", glow: "rgba(58, 141, 255, 0.35)" },
    yellow: { label: "Yellow", main: "#ffc81e", dim: "#7a6210", glow: "rgba(255, 200, 30, 0.35)" },
    purple: { label: "Purple", main: "#a259ff", dim: "#4a2a7a", glow: "rgba(162, 89, 255, 0.35)" },
    orange: { label: "Orange", main: "#ff8a1f", dim: "#7a4210", glow: "rgba(255, 138, 31, 0.35)" },
    green:  { label: "Green",  main: "#2fd16b", dim: "#146a36", glow: "rgba(47, 209, 107, 0.35)" },
    pink:   { label: "Pink",   main: "#ff5fb0", dim: "#7a2c58", glow: "rgba(255, 95, 176, 0.35)" }
};
let currentAccent = "red";
try {
    const saved = localStorage.getItem(ACCENT_STORAGE_KEY);
    if (saved && ACCENTS[saved]) currentAccent = saved;
} catch (e) {}

// Applies instantly (and is remembered) - no Save needed for this one.
function applyAccent(key, persist) {
    const a = ACCENTS[key];
    if (!a) return;
    currentAccent = key;

    const root = document.documentElement;
    root.style.setProperty("--red", a.main);
    root.style.setProperty("--red-dim", a.dim);
    root.style.setProperty("--red-glow", a.glow);

    document.querySelectorAll(".accent-swatch").forEach((el) => {
        el.classList.toggle("selected", el.dataset.accent === key);
    });
    const nameEl = document.getElementById("accentNameText");
    if (nameEl) nameEl.textContent = a.label;

    if (persist) {
        try { localStorage.setItem(ACCENT_STORAGE_KEY, key); } catch (e) {}
    }
}

function buildAccentGrid() {
    const grid = document.getElementById("accentGrid");
    if (!grid) return;
    const check = '<svg viewBox="0 0 24 24" width="14" height="14"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    for (const key in ACCENTS) {
        const a = ACCENTS[key];
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "accent-swatch";
        btn.dataset.accent = key;
        btn.setAttribute("aria-label", a.label + " accent");
        btn.innerHTML = `<span class="swatch-dot" style="background:${a.main};box-shadow:0 0 10px ${a.glow}">${check}</span><span>${a.label}</span>`;
        btn.addEventListener("click", () => applyAccent(key, true));
        grid.appendChild(btn);
    }
}
buildAccentGrid();
applyAccent(currentAccent, false);

// Click a number to type an exact value. Enter or clicking away applies it;
// values that would push the Mini Player off-screen are clamped to the edge.
function setMiniAxis(axis, value) {
    const r = miniPlayer.getBoundingClientRect();
    let min, max;
    if (axis === "x") {
        min = miniPos.x - r.left;
        max = miniPos.x + (window.innerWidth - r.right);
    } else {
        min = miniPos.y - (window.innerHeight - r.bottom);
        max = miniPos.y + r.top;
    }
    miniPos[axis] = Math.round(clamp(value, Math.ceil(min), Math.floor(max)));
    if (settingsStatus) settingsStatus.classList.remove("saved");
    applyMiniPos();
}

[posXVal, posYVal].forEach((input) => {
    if (!input) return;
    const axis = input.dataset.axis;
    input.addEventListener("focus", () => input.select());
    input.addEventListener("keydown", (e) => {
        e.stopPropagation(); // typing must not trigger Esc/close handling mid-edit
        if (e.key === "Enter") input.blur();
        if (e.key === "Escape") { input.value = miniPos[axis]; input.blur(); }
    });
    input.addEventListener("blur", () => {
        const v = parseInt(input.value, 10);
        if (Number.isFinite(v)) setMiniAxis(axis, v);
        else input.value = miniPos[axis];
    });
});

// Press-and-hold on +/- repeats the move.
(function wirePosButtons() {
    let holdTimer = null, repeatTimer = null;
    const stop = () => { clearTimeout(holdTimer); clearInterval(repeatTimer); };
    document.querySelectorAll(".pos-btn").forEach((btn) => {
        const axis = btn.dataset.axis;
        const dir = parseInt(btn.dataset.dir, 10);
        btn.addEventListener("mousedown", () => {
            nudgeMini(axis, dir);
            holdTimer = setTimeout(() => {
                repeatTimer = setInterval(() => nudgeMini(axis, dir), 60);
            }, 350);
        });
        ["mouseup", "mouseleave", "blur"].forEach((ev) => btn.addEventListener(ev, stop));
    });
    window.addEventListener("mouseup", stop);
})();

function toggleMiniPlayer() {
    miniPlayerEnabled = !miniPlayerEnabled;

    if (toggleMiniBtn) {
        toggleMiniBtn.classList.toggle("active", miniPlayerEnabled);
        toggleMiniBtn.setAttribute("aria-pressed", miniPlayerEnabled ? "true" : "false");
    }

    syncMiniPlayerEnabledToClient();
    updateMiniPlayerVisibility();
}

// ==============================
// Side Panel Toggles (Saved / Queue)
// ==============================
// The main head unit is always on screen; the queue and saved-songs
// panels are hidden until their toggle button is pressed, and both are
// sized (in CSS) to line up next to the main UI - only their display
// and the toggle button's active state change here.
function openPanel(which) {
    const panel = which === "queue" ? queuePanel : savedPanel;
    const btn = which === "queue" ? toggleQueueBtn : toggleSavedBtn;

    if (which === "queue") queuePanelOpen = true;
    else savedPanelOpen = true;

    panel.style.display = "flex";
    panel.offsetHeight; // force reflow so the slide/fade-in actually transitions
    panel.classList.add("panel-visible");
    btn.classList.add("active");
    btn.setAttribute("aria-pressed", "true");
}

function closePanel(which) {
    const panel = which === "queue" ? queuePanel : savedPanel;
    const btn = which === "queue" ? toggleQueueBtn : toggleSavedBtn;

    if (which === "queue") queuePanelOpen = false;
    else savedPanelOpen = false;

    panel.classList.remove("panel-visible");
    btn.classList.remove("active");
    btn.setAttribute("aria-pressed", "false");

    setTimeout(() => {
        if (panel.classList.contains("panel-visible")) return; // reopened mid-animation
        panel.style.display = "none";
    }, UI_ANIM_MS);
}

function toggleQueuePanel() {
    if (queuePanelOpen) closePanel("queue");
    else openPanel("queue");
}

function toggleSavedPanel() {
    if (savedPanelOpen) closePanel("saved");
    else openPanel("saved");
}

// ==============================
// Keep the side panels exactly as tall as the main head unit, even as
// its own height changes with content (album art, error text, etc.)
// ==============================
function syncPanelHeights() {
    const h = mainUI.offsetHeight;
    if (h > 0) {
        queuePanel.style.height = h + "px";
        savedPanel.style.height = h + "px";
    }
}

if (typeof ResizeObserver !== "undefined") {
    new ResizeObserver(syncPanelHeights).observe(mainUI);
}

// ==============================
// Play Song / Add To Queue
// ==============================
function playSong(song) {
    fetch(`https://${GetParentResourceName()}/play`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(song)
    })
        .then(r => r.json())
        .then(result => {
            if (result === "fail") {
                showToast("Couldn't play that - are you still in the vehicle?", "error");
            }
        })
        .catch(() => {});
}

function queueSong(song) {
    fetch(`https://${GetParentResourceName()}/queueAdd`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(song)
    })
        .then(r => r.json())
        .then(result => {
            if (result === "fail") {
                showToast("Couldn't add that to the queue - are you still in the vehicle?", "error");
            }
        })
        .catch(() => {});
}

function startQueue() {
    fetch(`https://${GetParentResourceName()}/startQueue`, { method: "POST" });
}

// ==============================
// Queue UI
// ==============================
function updateQueueUI() {
    if (!queueList) return;

    if (startQueueBtn) {
        startQueueBtn.disabled = window.queueActive || window.queue.length === 0;
        startQueueBtn.textContent = window.queueActive ? "Queue Running" : "Start Queue";
    }

    if (startQueueBtn2) {
        startQueueBtn2.disabled = window.queueActive || window.queue.length === 0;
        startQueueBtn2.title = window.queueActive ? "Queue running" : "Start queue";
    }

    if (queueCountEl) queueCountEl.textContent = window.queue.length;

    queueList.innerHTML = "";

    if (window.queue.length === 0) {
        const empty = document.createElement("div");
        empty.className = "queue-empty";
        empty.textContent = "Queue is empty";
        queueList.appendChild(empty);
        return;
    }

    window.queue.forEach((song, index) => {
        const item = document.createElement("div");
        item.className = "queue-item";

        const text = document.createElement("span");
        text.className = "qtext";

        const qindex = document.createElement("span");
        qindex.className = "qindex";
        qindex.textContent = `${index + 1}.`;

        text.appendChild(qindex);
        text.appendChild(document.createTextNode(song.title || "Unknown Title"));

        const removeBtn = document.createElement("button");
        removeBtn.textContent = "✖";
        removeBtn.setAttribute("aria-label", "Remove from queue");
        removeBtn.addEventListener("click", () => removeFromQueue(index));

        item.appendChild(text);
        item.appendChild(removeBtn);
        queueList.appendChild(item);
    });
}

// ==============================
// Remove Song From Queue
// ==============================
function removeFromQueue(index) {
    window.queue.splice(index, 1);
    updateQueueUI();

    fetch(`https://${GetParentResourceName()}/remove`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ index })
    });
}

function clearQueue() {
    if (window.queue.length === 0) return;

    // remove from the end so index shifting doesn't skip anything
    while (window.queue.length > 0) {
        window.queue.pop();
        fetch(`https://${GetParentResourceName()}/remove`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ index: window.queue.length })
        });
    }
    updateQueueUI();
    showToast("Queue cleared.", "success");
}

// ==============================
// Saved Songs (gallery view)
// ==============================
function updateSavedUI() {
    if (!savedList) return;

    if (savedCountEl) savedCountEl.textContent = window.savedSongs.length;

    savedList.innerHTML = "";

    if (window.savedSongs.length === 0) {
        const empty = document.createElement("div");
        empty.className = "queue-empty";
        empty.textContent = "No saved songs yet";
        savedList.appendChild(empty);
        return;
    }

    window.savedSongs.forEach((song, index) => {
        const card = document.createElement("div");
        card.className = "gallery-card";

        const thumb = document.createElement("div");
        thumb.className = "gallery-thumb";
        if (song.thumbnail) {
            thumb.style.backgroundImage = `url("${song.thumbnail}")`;
        } else {
            thumb.textContent = "♪";
        }

        const actions = document.createElement("div");
        actions.className = "gallery-actions";

        const playBtnEl = document.createElement("button");
        playBtnEl.className = "gallery-action gplay";
        playBtnEl.textContent = "▶";
        playBtnEl.setAttribute("aria-label", "Play saved song");
        playBtnEl.addEventListener("click", () => playSavedSong(index));

        const queueBtnEl = document.createElement("button");
        queueBtnEl.className = "gallery-action gqueue";
        queueBtnEl.textContent = "+";
        queueBtnEl.setAttribute("aria-label", "Add saved song to queue");
        queueBtnEl.addEventListener("click", () => queueSavedSong(index));

        const removeBtnEl = document.createElement("button");
        removeBtnEl.className = "gallery-action gremove";
        removeBtnEl.textContent = "✖";
        removeBtnEl.setAttribute("aria-label", "Remove saved song");
        removeBtnEl.addEventListener("click", () => removeSavedSong(index));

        actions.appendChild(playBtnEl);
        actions.appendChild(queueBtnEl);
        actions.appendChild(removeBtnEl);
        thumb.appendChild(actions);

        const label = document.createElement("div");
        label.className = "gallery-title";
        label.textContent = song.title || "Unknown Title";

        card.appendChild(thumb);
        card.appendChild(label);
        savedList.appendChild(card);
    });
}

function saveCurrentSong() {
    if (!window.currentSong) return;

    fetch(`https://${GetParentResourceName()}/saveSong`, { method: "POST" });
}

function playSavedSong(index) {
    fetch(`https://${GetParentResourceName()}/playSaved`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ index })
    });
}

// Adds a saved song to the live queue instead of playing it immediately.
function queueSavedSong(index) {
    fetch(`https://${GetParentResourceName()}/queueSaved`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ index })
    });
}

function removeSavedSong(index) {
    window.savedSongs.splice(index, 1);
    updateSavedUI();
    showToast("Removed from saved.", "success");

    fetch(`https://${GetParentResourceName()}/removeSaved`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ index })
    });
}

// ==============================
// Shared Save Song / Import Playlist modal - one input+button, switched
// between the two actions below depending on which button opened it.
// ==============================
function isLinkModalOpen() {
    return linkModalOverlay.classList.contains("open");
}

function openLinkModal(mode) {
    linkModalMode = mode;
    linkModalInput.value = "";
    linkModalError.textContent = "";

    if (mode === "playlist") {
        linkModalTitle.textContent = "Import Playlist";
        linkModalInput.placeholder = "Paste a YouTube playlist link";
        linkModalSubmit.textContent = "Import";
    } else {
        linkModalTitle.textContent = "Save Song";
        linkModalInput.placeholder = "Paste a YouTube link";
        linkModalSubmit.textContent = "Save";
    }

    linkModalOverlay.classList.add("open");
    linkModalInput.focus();
}

function closeLinkModal() {
    linkModalOverlay.classList.remove("open");
}

function submitLinkModal() {
    if (linkModalMode === "playlist") {
        submitPlaylistLink();
    } else {
        submitSavedLink();
    }
}

linkModalInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") submitLinkModal();
});

// ==============================
// Link-type helpers - a playlist link is anything with a `list=` query
// param but no specific video attached to it (a plain `watch?v=...&list=`
// link is still just that one video, so it's fine either way; only a
// bare `/playlist?list=...` link - or one with no video id at all - is
// treated as playlist-only).
// ==============================
function isPlaylistOnlyLink(link) {
    try {
        const url = new URL(link);
        const list = url.searchParams.get("list");
        if (!list) return false;

        const host = url.hostname.replace(/^www\./i, "").toLowerCase();
        const hasVideoId = host === "youtu.be"
            ? /^\/[\w-]{6,}/.test(url.pathname)
            : !!url.searchParams.get("v");

        return !hasVideoId;
    } catch {
        return false;
    }
}

// ==============================
// Save a song straight from a YouTube link - doesn't touch playback
// or the queue, just drops it into the saved list directly.
// ==============================
let savingByLink = false;

function submitSavedLink() {
    if (savingByLink) return;

    const link = linkModalInput.value.trim();
    linkModalError.textContent = "";

    if (!link) return;

    if (!/^https?:\/\//i.test(link)) {
        linkModalError.textContent = "That doesn't look like a valid link.";
        return;
    }

    if (isPlaylistOnlyLink(link)) {
        linkModalError.textContent = "That's a playlist link - use Import Playlist instead.";
        return;
    }

    savingByLink = true;
    linkModalSubmit.disabled = true;
    linkModalSubmit.textContent = "Saving...";

    fetch(`https://noembed.com/embed?url=${encodeURIComponent(link)}`)
        .then(r => r.json())
        .then(d => {
            if (d.error) throw new Error(d.error);

            const songData = {
                link: link,
                title: d.title || "Unknown Title",
                artist: d.author_name || "Unknown Artist",
                thumbnail: d.thumbnail_url || ""
            };

            fetch(`https://${GetParentResourceName()}/saveSongByLink`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(songData)
            });

            closeLinkModal();
        })
        .catch(() => {
            linkModalError.textContent = "Couldn't load that link. Check it and try again.";
            showToast("Couldn't load that link. Check it and try again.", "error");
        })
        .finally(() => {
            savingByLink = false;
            linkModalSubmit.disabled = false;
            linkModalSubmit.textContent = "Save";
        });
}

// ==============================
// Save an entire YouTube playlist to the saved list - the server
// resolves the playlist's videos and reports back how many made it in.
// ==============================
let savingPlaylist = false;

function submitPlaylistLink() {
    if (savingPlaylist) return;

    const link = linkModalInput.value.trim();
    linkModalError.textContent = "";

    if (!link) return;

    if (!/^https?:\/\//i.test(link) || !/[?&]list=/.test(link)) {
        linkModalError.textContent = "That doesn't look like a playlist link.";
        return;
    }

    savingPlaylist = true;
    linkModalSubmit.disabled = true;
    linkModalSubmit.textContent = "Importing...";

    fetch(`https://${GetParentResourceName()}/savePlaylist`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ link })
    });

    // Button/input get re-enabled once playlistImportResult comes back
    // (or after a timeout, in case the request never returns).
    setTimeout(() => {
        if (savingPlaylist) resetPlaylistButton();
    }, 15000);
}

function resetPlaylistButton() {
    savingPlaylist = false;
    linkModalSubmit.disabled = false;
    linkModalSubmit.textContent = linkModalMode === "playlist" ? "Import" : "Save";
}

function handlePlaylistImportResult(data) {
    resetPlaylistButton();

    if (!data.success) {
        linkModalError.textContent = data.error || "Couldn't import that playlist.";
        showToast(data.error || "Couldn't import that playlist.", "error");
        return;
    }

    if (data.added === 0) {
        linkModalError.textContent = "Those songs are already saved.";
        showToast("Those songs are already saved.", "error");
    } else if (data.added < data.total) {
        const msg = `Added ${data.added} of ${data.total} - saved list is full.`;
        linkModalError.textContent = msg;
        showToast(msg, "error");
    } else {
        showToast(`Imported ${data.added} song${data.added === 1 ? "" : "s"}.`, "success");
        closeLinkModal();
    }
}

// ==============================
// Play / Pause
// ==============================
function toggle() {
    if (!window.currentSong) return;

    window.playing = !window.playing;
    playPauseBtn.innerHTML = window.playing ? PAUSE_ICON : PLAY_ICON;

    fetch(`https://${GetParentResourceName()}/${window.playing ? "resume" : "pause"}`, {
        method: "POST"
    });
}

// ==============================
// Submit Song (shared lookup, then either play immediately or queue)
// ==============================
function submitLink(mode) {
    if (submitting) return;

    const link = linkInput.value.trim();
    linkError.textContent = "";

    if (!link) return;

    if (!/^https?:\/\//i.test(link)) {
        linkError.textContent = "That doesn't look like a valid link.";
        return;
    }

    const btn = mode === "queue" ? queueBtn : playBtn;
    const originalLabel = btn.textContent;

    submitting = true;
    playBtn.disabled = true;
    queueBtn.disabled = true;
    btn.textContent = mode === "queue" ? "Adding..." : "Loading...";

    fetch(`https://noembed.com/embed?url=${encodeURIComponent(link)}`)
        .then(r => r.json())
        .then(d => {
            if (d.error) throw new Error(d.error);

            const songData = {
                link: link,
                title: d.title || "Unknown Title",
                artist: d.author_name || "Unknown Artist",
                thumbnail: d.thumbnail_url || ""
            };

            if (mode === "queue") {
                queueSong(songData);
            } else {
                playSong(songData);
            }
            linkInput.value = "";
        })
        .catch(() => {
            linkError.textContent = "Couldn't load that link. Check it and try again.";
            showToast("Couldn't load that link. Check it and try again.", "error");
        })
        .finally(() => {
            submitting = false;
            playBtn.disabled = false;
            queueBtn.disabled = false;
            btn.textContent = originalLabel;
        });
}

function submitPlay() {
    submitLink("play");
}

function submitQueue() {
    submitLink("queue");
}

linkInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") submitPlay();
});

// ==============================
// Volume (+ / - buttons)
// ==============================
function setVolume(vol) {
    vol = clamp(vol, 0, maxVolume);
    setVolumeDisplay(vol);

    fetch(`https://${GetParentResourceName()}/volume`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ vol })
    });
}

volUpBtn.addEventListener("click", () => setVolume(currentVolume + volumeStep));
volDownBtn.addEventListener("click", () => setVolume(currentVolume - volumeStep));

// ==============================
// Close UI
// ==============================
function closeUI() {
    closeSettings();
    fetch(`https://${GetParentResourceName()}/close`, { method: "POST" });

    app.classList.remove("ui-visible");
    closePanel("queue");
    closePanel("saved");

    setTimeout(() => {
        if (app.classList.contains("ui-visible")) return; // reopened mid-animation
        app.style.display = "none";
        mainUI.style.display = "none";
    }, UI_ANIM_MS);
}

// ==============================
// Skip Song (Manual)
// ==============================
function skip() {
    fetch(`https://${GetParentResourceName()}/skip`, {
        method: "POST"
    });
}

// ==============================
// Restart Song (jump back to 0:00)
// ==============================
function restart() {
    if (!window.currentSong) return;
    previewSeek(0);
    seekTo(0);
}

function updateSkipButton() {
    // Skip only makes sense while the queue is actually running - otherwise
    // there's nothing queued up to skip to.
    skipbtn.disabled = !window.currentSong || !window.queueActive;
    restartbtn.disabled = !window.currentSong;
    if (saveCurrentBtn) saveCurrentBtn.disabled = !window.currentSong;
    if (saveCurrentBtn2) saveCurrentBtn2.disabled = !window.currentSong;
}

setInterval(updateSkipButton, 500);

// ==============================
// Seek (click or drag anywhere on the progress bar)
// ==============================
function ratioFromEvent(e) {
    const rect = progressTrack.getBoundingClientRect();
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    if (rect.width === 0) return 0;
    return clamp((clientX - rect.left) / rect.width, 0, 1);
}

function previewSeek(ratio) {
    bar.style.width = (ratio * 100) + "%";
    timeCur.textContent = formatTime(ratio * currentDuration);
}

function startSeek(e) {
    if (!window.currentSong || !currentDuration) return;
    seeking = true;
    progressTrack.classList.add("seeking");
    previewSeek(ratioFromEvent(e));
    e.preventDefault();
}

function moveSeek(e) {
    if (!seeking) return;
    previewSeek(ratioFromEvent(e));
}

function endSeek(e) {
    if (!seeking) return;
    seeking = false;
    progressTrack.classList.remove("seeking");

    const ratio = ratioFromEvent(e);
    const time = ratio * currentDuration;
    previewSeek(ratio);
    seekTo(time);
}

function seekTo(time) {
    fetch(`https://${GetParentResourceName()}/seek`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ time })
    });
}

progressTrack.addEventListener("mousedown", startSeek);
window.addEventListener("mousemove", moveSeek);
window.addEventListener("mouseup", endSeek);
progressTrack.addEventListener("touchstart", startSeek, { passive: false });
window.addEventListener("touchmove", moveSeek, { passive: false });
window.addEventListener("touchend", endSeek);

// ==============================
updateQueueUI();
updateSavedUI();
setAlbumArt(null);
setMiniAlbumArt(null);

if (toggleMiniBtn) {
    toggleMiniBtn.classList.toggle("active", miniPlayerEnabled);
    toggleMiniBtn.setAttribute("aria-pressed", miniPlayerEnabled ? "true" : "false");
}
applyMiniPos();
updateMiniPlayerVisibility();

// Ask client.lua for the saved Streamer Mode state (its KVP is the source of truth).
applyStreamerMode(streamerMode);
fetch(`https://${GetParentResourceName()}/streamerModeReady`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" })
    .then((r) => r.json())
    .then((d) => { if (d && typeof d.enabled === "boolean") applyStreamerMode(d.enabled); })
    .catch(() => {});
