-------------------------------------------------
-- State
-------------------------------------------------
local vehicleNet = nil
local soundId = nil
local finishSent = false
local skipLock = false
local uiOpen = false
local sawNearEnd = false
local miniPlayerEnabled = false -- Mini Player on/off for the CURRENT vehicle (saved per vehicle plate), see "Mini Player toggle" below
local streamerMode = GetResourceKvpInt("x1s_streamer_mode") == 1 -- saved per player, see "Streamer Mode" below

local activeSounds = {}
local vehicleSongs = {}
local vehicleVolumes = {}
local vehiclePaused = {}
local vehicleAudio = {} -- net -> { fade, muffle, sent } eased volume state, see "Distance Fade" below

local lastTrackedNet = nil
local stuckLoggedNet = nil
local stuckSince = nil

local NEAR_END_THRESHOLD = 3.0
local NEAR_END_RESET_MARGIN = 5.0
local STUCK_GRACE_MS = 1500

local DEBUG = Config.Debug or false

local function DebugPrint(msg)
    if DEBUG then
        print("^3[X1S-CarPlay DEBUG]^0 " .. msg)
    end
end

-------------------------------------------------
-- Helpers
-------------------------------------------------
local function NetToVeh(net)
    return NetworkGetEntityFromNetworkId(net)
end

local function Notify(msg)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end

local function getCurrentVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return 0 end
    return GetVehiclePedIsIn(ped, false)
end

local function canControl(veh)
    if not Config.DriverOnly then return true end
    local ped = PlayerPedId()
    return GetPedInVehicleSeat(veh, -1) == ped
end

-------------------------------------------------
-- Muffling / Vehicle Seal Check
-------------------------------------------------
-- A "sealed" vehicle gets the muffled volume; if a door, the roof, or a
-- window is open, sound leaks out clearly and muffling is skipped.
--
-- NOTE ON WINDOWS: GTA/FiveM has no native to read whether a window is
-- currently rolled down (only IsVehicleWindowIntact, which is about broken
-- glass, not roll position). If this server has a separate window-control
-- script, have it call the export below (or set the state bag directly)
-- whenever it rolls a window up/down so this can react to it:
--
--   exports['X1S-CarPlay']:SetVehicleWindowState(vehicle, true)  -- open
--   exports['X1S-CarPlay']:SetVehicleWindowState(vehicle, false) -- closed
--   (swap 'X1S-CarPlay' for whatever this resource's folder is actually named on your server)
--
-- Without that hook, window state is simply ignored (treated as closed).
local function IsVehicleSealed(veh)
    if veh == 0 or not DoesEntityExist(veh) then return true end

    if Config.MuffleCheckDoors then
        local threshold = Config.DoorOpenRatioThreshold or 0.08
        for i = 0, 5 do
            if GetVehicleDoorAngleRatio(veh, i) > threshold then
                return false
            end
        end
    end

    if Config.MuffleCheckRoof and IsVehicleAConvertible(veh, false) then
        -- 0 = roof fully up/closed; anything else (open, raising, lowering) leaks sound
        if GetConvertibleRoofState(veh) ~= 0 then
            return false
        end
    end

    if Config.MuffleCheckWindows then
        local ok, state = pcall(function() return Entity(veh).state end)
        if ok and state and state.windowsOpen then
            return false
        end
    end

    return true
end

exports('SetVehicleWindowState', function(vehicle, isOpen)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    Entity(vehicle).state:set('windowsOpen', isOpen and true or false, true)
end)

-------------------------------------------------
-- Distance Fade
-------------------------------------------------
-- ONE place decides how loud a vehicle's music is for the local player:
--   volume = base volume * distance fade * muffle
-- and it eases smoothly toward that target ~20x per second. The xsound NUI
-- page is told the sound has a huge range (XSOUND_PASSTHRU_DISTANCE), which
-- makes it skip its own distance math (see updateVolume in
-- html/xsound/SoundPlayer.js) - before, the two systems both set the volume
-- on different timers and fought each other, which is what made the music
-- stutter/flicker when walking away from a car.
local XSOUND_PASSTHRU_DISTANCE = 10000.0
local FADE_TICK_MS = 50

local function SmoothStep(t)
    if t <= 0.0 then return 0.0 end
    if t >= 1.0 then return 1.0 end
    return t * t * (3.0 - 2.0 * t)
end

-- 1.0 inside the vehicle / right next to it, easing down to 0.0 at
-- Config.SoundDistance.
local function GetDistanceFade(veh)
    local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh))
    local fadeEnd = Config.SoundDistance
    local fadeStart = math.min(Config.FadeStartDistance or 3.0, fadeEnd)

    if d >= fadeEnd then return 0.0 end
    if d <= fadeStart then return 1.0 end
    return 1.0 - SmoothStep((d - fadeStart) / (fadeEnd - fadeStart))
end

-- Where the fade and muffle multipliers WANT to be right now.
local function GetFadeTargets(veh, pedVeh, prevMuffle)
    if pedVeh ~= 0 and pedVeh == veh then
        return 1.0, 1.0
    end

    local fade = GetDistanceFade(veh)
    local muffle = prevMuffle or 1.0 -- out of earshot: nothing audible to change
    if fade > 0.0 then
        muffle = (Config.EnableMuffling and IsVehicleSealed(veh)) and Config.MuffledVolumeMultiplier or 1.0
    end
    return fade, muffle
end

-- Volume a brand-new sound should START at, so it never pops in at full
-- volume for a moment when you're standing across the street.
local function SeedVehicleAudio(net, veh)
    local fade, muffle = GetFadeTargets(veh, getCurrentVehicle(), nil)
    local vol = (vehicleVolumes[net] or Config.DefaultVolume) * fade * muffle
    if vol < 0.002 then vol = 0.0 end
    vehicleAudio[net] = { fade = fade, muffle = muffle, sent = vol }
    return vol
end

local function Ease(current, target, ratePerSec, dt)
    local nextValue = current + (target - current) * (1.0 - math.exp(-ratePerSec * dt))
    if math.abs(nextValue - target) < 0.002 then return target end
    return nextValue
end

CreateThread(function()
    local last = GetGameTimer()

    while true do
        Wait(FADE_TICK_MS)

        local now = GetGameTimer()
        local dt = math.max((now - last) / 1000.0, 0.001)
        last = now

        local pedVeh = getCurrentVehicle()
        local fadeRate = Config.FadeSmoothing or 10.0

        for net, id in pairs(activeSounds) do
            if soundExists(id) then
                local st = vehicleAudio[net]
                if not st then
                    st = { sent = nil }
                    vehicleAudio[net] = st
                end

                local veh = NetToVeh(net)
                local vol

                if veh ~= 0 and DoesEntityExist(veh) then
                    local targetFade, targetMuffle = GetFadeTargets(veh, pedVeh, st.muffle)
                    st.fade = st.fade or targetFade
                    st.muffle = st.muffle or targetMuffle

                    -- Distance fade follows the player's movement, so it only
                    -- needs light smoothing. The muffle change (doors/roof
                    -- opening or closing) glides at the slower, configurable
                    -- Config.MuffleSmoothing rate - except when you're getting
                    -- INTO the car, where it clears up quickly.
                    local muffleStep = Config.MuffleSmoothing or 1.0
                    local muffleRate = fadeRate
                    if not (pedVeh ~= 0 and pedVeh == veh) and muffleStep < 1.0 then
                        muffleRate = -math.log(1.0 - muffleStep) / 0.2 -- per-200ms-tick setting -> per second
                    end

                    st.fade = Ease(st.fade, targetFade, fadeRate, dt)
                    st.muffle = Ease(st.muffle, targetMuffle, muffleRate, dt)

                    vol = (vehicleVolumes[net] or Config.DefaultVolume) * st.fade * st.muffle
                else
                    -- Vehicle isn't streamed in on this client (too far away):
                    -- keep the sound running silently so it's still in sync
                    -- when you come back, and make sure it is actually silent.
                    st.fade = 0.0
                    vol = 0.0
                end

                if vol < 0.002 then vol = 0.0 end

                if st.sent == nil or math.abs(vol - st.sent) >= 0.002 or (vol == 0.0 and st.sent ~= 0.0) then
                    setVolume(id, vol)
                    st.sent = vol
                end
            end
        end
    end
end)

local function SafeSeek(id, time)
    if not time or time <= 0 then return end

    CreateThread(function()
        local tries = 0
        while tries < 50 do
            if not soundExists(id) then return end
            if (getMaxDuration(id) or 0) > 0 then
                DebugPrint(("SafeSeek firing on '%s' -> %.2fs"):format(id, time))
                setTimeStamp(id, time)
                return
            end
            tries = tries + 1
            Wait(100)
        end
    end)
end

-------------------------------------------------
-- Open / Close CarPlay
-------------------------------------------------
-- Keeps the NUI's idea of "what's playing" correct for whichever vehicle
-- the player is actually in. Used when getting into a vehicle so the Mini
-- Player (and the main menu, once opened) show THAT vehicle's real state
-- instead of carrying over whatever the previous vehicle was showing.
local function SyncVehicleStateToNUI(net)
    local song = vehicleSongs[net]
    if song then
        SendNUIMessage({
            action = "nowPlaying",
            song = song,
            volume = vehicleVolumes[net] or Config.DefaultVolume,
            paused = vehiclePaused[net] or false
        })
    else
        SendNUIMessage({ action = "stop" })
        SendNUIMessage({
            action = "volumeSync",
            volume = vehicleVolumes[net] or Config.DefaultVolume
        })
    end
end

local function CloseCarPlay()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "hide" })
end

local function OpenCarPlay(net)
    vehicleNet = net
    soundId = "car_" .. net
    uiOpen = true

    SetNuiFocus(true, true)

    SendNUIMessage({
        action = "show",
        net = net,
        maxVolume = Config.MaxVolume,
        volumeStep = Config.VolumeStep
    })

    local song = vehicleSongs[net]
    if song then
        SendNUIMessage({
            action = "nowPlaying",
            song = song,
            volume = vehicleVolumes[net] or Config.DefaultVolume,
            paused = vehiclePaused[net] or false
        })
    else
        SendNUIMessage({
            action = "volumeSync",
            volume = vehicleVolumes[net] or Config.DefaultVolume
        })
    end

    TriggerServerEvent("x1s:requestSync")

    TriggerServerEvent("x1s:requestQueue", net)

    TriggerServerEvent("x1s:requestSavedSongs", net)
end

RegisterCommand(Config.Command, function()
    if uiOpen then
        CloseCarPlay()
        return
    end

    local veh = getCurrentVehicle()
    if veh == 0 then
        Notify("You need to be inside a vehicle to open CarPlay.")
        return
    end

    if not canControl(veh) then
        Notify("Only the driver can control CarPlay in this vehicle.")
        return
    end

    local net = NetworkGetNetworkIdFromEntity(veh)

    if Config.Radio and Config.Radio.RequireInstall then
        TriggerServerEvent("x1s:requestOpen", net)
    else
        OpenCarPlay(net)
    end
end, false)

RegisterNetEvent("x1s:openResult", function(net, ok, reason)
    if not ok then
        Notify(reason or "This vehicle doesn't have a radio installed.")
        return
    end
    OpenCarPlay(net)
end)

if Config.Keybind and Config.Keybind ~= "" then
    RegisterKeyMapping(Config.Command, "Open CarPlay", "keyboard", Config.Keybind)
end

RegisterNUICallback("close", function(_, cb)
    CloseCarPlay()
    cb("ok")
end)

-------------------------------------------------
-- Mini Player toggle (per vehicle)
-------------------------------------------------
-- The Mini Player's on/off choice is remembered PER VEHICLE (keyed by the
-- vehicle's plate, same as saved songs), saved with KVP for this player so
-- it survives reconnects. Enabled in one car and disabled in another means
-- it shows in the first and stays hidden in the second. Vehicles that were
-- never toggled default to off. Whenever the player gets into a vehicle,
-- that vehicle's saved choice is loaded and pushed to the NUI.
local function MiniPlayerKey(veh)
    if not veh or veh == 0 then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    if type(plate) == "string" then
        plate = plate:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if not plate or plate == "" then
        -- No usable plate - fall back to the network id (lasts until restart).
        local net = NetworkGetNetworkIdFromEntity(veh)
        if not net or net == 0 then return nil end
        plate = "net_" .. net
    end
    return "x1s_carplay_mini_" .. plate
end

local function LoadMiniPlayerForVehicle(veh)
    local key = MiniPlayerKey(veh)
    miniPlayerEnabled = key ~= nil and GetResourceKvpInt(key) == 1
    SendNUIMessage({ action = "miniPlayerState", enabled = miniPlayerEnabled })
end

RegisterNUICallback("miniPlayerToggle", function(data, cb)
    local veh = getCurrentVehicle()
    local key = MiniPlayerKey(veh)

    if key then
        miniPlayerEnabled = data and data.enabled and true or false
        SetResourceKvpInt(key, miniPlayerEnabled and 1 or 0)
        SendNUIMessage({ action = "vehicleState", inVehicle = true })
    end

    cb("ok")
end)

-------------------------------------------------
-- Streamer Mode
-------------------------------------------------
-- Mutes all CarPlay music for THIS player only. The actual muting happens
-- in the NUI (xsound/SoundPlayer.js): the sound keeps playing silently so
-- the song-finished/queue logic in the main loop below keeps working and
-- other players in the car are unaffected. The choice is saved with KVP so
-- it survives reconnects.
local function SetStreamerMode(enabled)
    streamerMode = enabled and true or false
    SetResourceKvpInt("x1s_streamer_mode", streamerMode and 1 or 0)
    SendNUIMessage({ action = "streamerMode", enabled = streamerMode })

    if streamerMode then
        Notify("Streamer Mode ON - CarPlay music is muted for you.")
    else
        Notify("Streamer Mode OFF - CarPlay music is back on.")
    end
end

RegisterCommand(Config.StreamerCommand or "streamermode", function()
    SetStreamerMode(not streamerMode)
end, false)

-- Toggled from the CarPlay settings menu.
RegisterNUICallback("streamerMode", function(data, cb)
    SetStreamerMode(data and data.enabled)
    cb("ok")
end)

-- The NUI asks for the saved state as soon as its page loads.
RegisterNUICallback("streamerModeReady", function(_, cb)
    cb({ enabled = streamerMode })
end)

-------------------------------------------------
-- Notifications
-------------------------------------------------
RegisterNetEvent('x1s:notify', function(kind, message)
    if not message then return end

    if uiOpen then
        SendNUIMessage({ action = "notify", type = kind, message = message })
    else
        Notify(message)
    end
end)

-------------------------------------------------
-- Play Song
-------------------------------------------------
RegisterNUICallback("play", function(data, cb)
    local veh = getCurrentVehicle()
    if veh == 0 or not canControl(veh) then cb("fail"); return end

    local net = NetworkGetNetworkIdFromEntity(veh)
    vehicleNet = net
    soundId = "car_" .. net
    finishSent = false
    sawNearEnd = false
    stuckSince = nil

    TriggerServerEvent("x1s:playSong", {
        link = data.link,
        title = data.title,
        artist = data.artist,
        thumbnail = data.thumbnail,
        net = net
    })

    cb("ok")
end)

-------------------------------------------------
-- Add To Queue
-------------------------------------------------
RegisterNUICallback("queueAdd", function(data, cb)
    local veh = getCurrentVehicle()
    if veh == 0 or not canControl(veh) then cb("fail"); return end

    local net = NetworkGetNetworkIdFromEntity(veh)

    TriggerServerEvent("x1s:addToQueue", {
        link = data.link,
        title = data.title,
        artist = data.artist,
        thumbnail = data.thumbnail,
        net = net
    })

    cb("ok")
end)

-------------------------------------------------
-- Start Queue
-------------------------------------------------
RegisterNUICallback("startQueue", function(_, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:startQueue", vehicleNet)
    end
    cb("ok")
end)

-------------------------------------------------
-- Saved Songs
-------------------------------------------------
RegisterNUICallback("saveSong", function(_, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:saveSong", vehicleNet)
    end
    cb("ok")
end)

RegisterNUICallback("playSaved", function(data, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:playSavedSong", vehicleNet, data.index)
    end
    cb("ok")
end)

RegisterNUICallback("removeSaved", function(data, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:removeSavedSong", vehicleNet, data.index)
    end
    cb("ok")
end)

RegisterNUICallback("saveSongByLink", function(data, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:saveSongByLink", vehicleNet, {
            link = data.link,
            title = data.title,
            artist = data.artist,
            thumbnail = data.thumbnail
        })
    end
    cb("ok")
end)

RegisterNUICallback("savePlaylist", function(data, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:savePlaylistByLink", vehicleNet, {
            link = data.link
        })
    end
    cb("ok")
end)

RegisterNUICallback("queueSaved", function(data, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:queueSavedSong", vehicleNet, data.index)
    end
    cb("ok")
end)

-------------------------------------------------
-- Pause / Resume
-------------------------------------------------
RegisterNUICallback("pause", function(_, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:pause", vehicleNet)
    end
    cb("ok")
end)

RegisterNUICallback("resume", function(_, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:resume", vehicleNet)
    end
    cb("ok")
end)

-------------------------------------------------
-- Skip
-------------------------------------------------
RegisterNUICallback("skip", function(_, cb)
    if vehicleNet then
        finishSent = true
        skipLock = true

        TriggerServerEvent("x1s:skip", vehicleNet)

        SetTimeout(1500, function()
            skipLock = false
        end)
    end
    cb("ok")
end)

-------------------------------------------------
-- Seek
-------------------------------------------------
RegisterNUICallback("seek", function(data, cb)
    if vehicleNet then
        local time = tonumber(data.time)
        if time then
            finishSent = false
            sawNearEnd = false
            stuckSince = nil
            TriggerServerEvent("x1s:seek", vehicleNet, time)
        end
    end
    cb("ok")
end)

-------------------------------------------------
-- Remove Song From Queue
-------------------------------------------------
RegisterNUICallback("remove", function(data, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:removeFromQueue", vehicleNet, data.index)
    end
    cb("ok")
end)

-------------------------------------------------
-- Volume
-------------------------------------------------
RegisterNUICallback("volume", function(data, cb)
    if vehicleNet then
        TriggerServerEvent("x1s:setVolume", data.vol, vehicleNet)
    end
    cb("ok")
end)

RegisterNetEvent("x1s:updateVolume", function(vol, net)
    vehicleVolumes[net] = vol

    -- The Distance Fade loop applies the new base volume within ~50ms, eased
    -- with the distance/muffle multipliers - setting it here would briefly
    -- blast full volume at anyone who is standing away from the car.

    if (uiOpen or miniPlayerEnabled) and vehicleNet == net then
        SendNUIMessage({ action = "volumeSync", volume = vol })
    end
end)

-------------------------------------------------
-- Pause State Sync
-------------------------------------------------
RegisterNetEvent("x1s:setPaused", function(net, paused, elapsed)
    vehiclePaused[net] = paused

    local id = "car_" .. net
    if soundExists(id) then
        if paused then
            Pause(id)
        else
            if elapsed and elapsed > 0 then
                DebugPrint(("resume seek firing on '%s' -> %.2fs"):format(id, elapsed))
                setTimeStamp(id, elapsed)
            end
            Resume(id)
        end
    end

    if net == vehicleNet then
        finishSent = false
        sawNearEnd = false
        stuckSince = nil
        if uiOpen or miniPlayerEnabled then
            SendNUIMessage({ action = paused and "paused" or "resumed" })
        end
    end
end)

-------------------------------------------------
-- Seek Broadcast
-------------------------------------------------
RegisterNetEvent("x1s:seek", function(net, time)
    local id = "car_" .. net

    if soundExists(id) then
        DebugPrint(("manual seek firing on '%s' -> %.2fs"):format(id, time))
        setTimeStamp(id, time)
    end

    if net == vehicleNet then
        finishSent = false
        sawNearEnd = false
        stuckSince = nil

        if (uiOpen or miniPlayerEnabled) and soundExists(id) then
            local dur = getMaxDuration(id) or 0
            if dur > 0 then
                SendNUIMessage({
                    action = "progress",
                    current = time,
                    duration = dur
                })
            end
        end
    end
end)

-------------------------------------------------
-- Drift Correction
-------------------------------------------------
RegisterNetEvent("x1s:driftCorrect", function(net, elapsed)
    local id = "car_" .. net
    if not soundExists(id) then return end
    if vehiclePaused[net] then return end
    if (getMaxDuration(id) or 0) <= 0 then return end -- player not actually ready/loaded yet

    local cur = getTimeStamp(id) or 0
    local threshold = Config.DriftCorrectionThreshold or 1.0

    if math.abs(cur - elapsed) > threshold then
        DebugPrint(("driftCorrect firing on '%s' -> cur=%.2fs server=%.2fs"):format(id, cur, elapsed))
        setTimeStamp(id, elapsed)
    end
end)

-------------------------------------------------
-- Sync Song
-------------------------------------------------
RegisterNetEvent("x1s:syncSong", function(data)
    local veh = NetToVeh(data.net)
    if veh == 0 then return end

    local id = "car_" .. data.net

    vehicleSongs[data.net] = {
        title = data.title,
        artist = data.artist,
        thumbnail = data.thumbnail,
        link = data.link
    }
    vehicleVolumes[data.net] = data.volume or Config.DefaultVolume
    vehiclePaused[data.net] = false

    if vehicleNet == data.net then
        finishSent = false
        sawNearEnd = false
        stuckSince = nil
        skipLock = false
    end

    if soundExists(id) then
        Destroy(id)
        Wait(300)
    end

    PlayUrlPos(
        id,
        data.link,
        SeedVehicleAudio(data.net, veh),
        GetEntityCoords(veh),
        false
    )

    Distance(id, XSOUND_PASSTHRU_DISTANCE)

    if data.elapsed and data.elapsed > 0 then
        SafeSeek(id, data.elapsed)
    end

    activeSounds[data.net] = id

    if DEBUG then
        CreateThread(function()
            local last = nil
            for i = 1, 20 do -- ~4 seconds at 200ms
                if not soundExists(id) then return end
                local cur = getTimeStamp(id) or 0
                if last and (cur - last) > 1.75 then
                    DebugPrint(("RAW JUMP on '%s': %.2fs -> %.2fs (no seek call logged above? check timing)"):format(id, last, cur))
                else
                    DebugPrint(("raw sample '%s': %.2fs"):format(id, cur))
                end
                last = cur
                Wait(200)
            end
        end)
    end

    local pedVeh = getCurrentVehicle()

    if pedVeh == veh and (uiOpen or miniPlayerEnabled) then
        SendNUIMessage({
            action = "nowPlaying",
            song = vehicleSongs[data.net],
            volume = vehicleVolumes[data.net],
            paused = false
        })
    end
end)

-------------------------------------------------
-- Full Sync
-------------------------------------------------
RegisterNetEvent("x1s:fullSync", function(snapshot)
    for _, data in ipairs(snapshot) do
        local veh = NetToVeh(data.net)
        if veh ~= 0 then
            local id = "car_" .. data.net

            vehicleSongs[data.net] = {
                title = data.title,
                artist = data.artist,
                thumbnail = data.thumbnail,
                link = data.link
            }
            vehicleVolumes[data.net] = data.volume or Config.DefaultVolume
            vehiclePaused[data.net] = data.paused or false

            if not soundExists(id) then
                PlayUrlPos(
                    id,
                    data.link,
                    SeedVehicleAudio(data.net, veh),
                    GetEntityCoords(veh),
                    false
                )
                Distance(id, XSOUND_PASSTHRU_DISTANCE)

                if data.elapsed and data.elapsed > 0 then
                    SafeSeek(id, data.elapsed)
                end

                if data.paused then
                    Pause(id)
                end

                activeSounds[data.net] = id
            end

            if (uiOpen or miniPlayerEnabled) and vehicleNet == data.net then
                SendNUIMessage({
                    action = "nowPlaying",
                    song = vehicleSongs[data.net],
                    volume = vehicleVolumes[data.net],
                    paused = vehiclePaused[data.net]
                })
            end
        end
    end
end)

-------------------------------------------------
-- Queue Update
-------------------------------------------------
RegisterNetEvent("x1s:updateQueue", function(net, queue, queueActive)
    if uiOpen and vehicleNet == net then
        SendNUIMessage({
            action = "updateQueue",
            queue = queue,
            queueActive = queueActive or false
        })
    end
end)

-------------------------------------------------
-- Saved Songs Sync
-------------------------------------------------
RegisterNetEvent("x1s:savedSongsSync", function(net, songs)
    if uiOpen and vehicleNet == net then
        SendNUIMessage({
            action = "savedSongsSync",
            songs = songs or {}
        })
    end
end)

-------------------------------------------------
-- Playlist Import Result
-------------------------------------------------
RegisterNetEvent("x1s:playlistImportResult", function(success, err, added, total)
    if uiOpen then
        SendNUIMessage({
            action = "playlistImportResult",
            success = success,
            error = err,
            added = added,
            total = total
        })
    end
end)

-------------------------------------------------
-- Destroy Sound
-------------------------------------------------
RegisterNetEvent("x1s:destroyCarSound", function(net)
    local id = "car_" .. net

    if soundExists(id) then
        Destroy(id)
    end

    activeSounds[net] = nil
    vehicleSongs[net] = nil
    vehicleVolumes[net] = nil
    vehiclePaused[net] = nil
    vehicleAudio[net] = nil

    if vehicleNet == net then
        finishSent = false
        sawNearEnd = false
        stuckSince = nil
        skipLock = false
        if uiOpen or miniPlayerEnabled then
            SendNUIMessage({ action = "stop" })
        end
    end
end)

-------------------------------------------------
-- Joining Sync
-------------------------------------------------
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(500)
    end
    Wait(1500)
    TriggerServerEvent("x1s:requestSync")
end)

-------------------------------------------------
-- Fast Position Loop
-------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)

        local veh = getCurrentVehicle()
        if veh ~= 0 then
            local net = NetworkGetNetworkIdFromEntity(veh)
            local id = activeSounds[net]

            if id and soundExists(id) then
                Position(id, GetEntityCoords(veh))
            end
        end
    end
end)

-------------------------------------------------
-- Main Loop
-------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.PositionUpdateInterval or 200)

        local pedVeh = getCurrentVehicle()

        for net, id in pairs(activeSounds) do
            local veh = NetToVeh(net)

            if veh ~= 0 and DoesEntityExist(veh) then
                if soundExists(id) then
                    local isInside = pedVeh ~= 0 and pedVeh == veh

                    -- Volume/distance are handled by the Distance Fade loop.
                    if not isInside then
                        Position(id, GetEntityCoords(veh))
                    end
                end
            end
        end

        local pedNet = pedVeh ~= 0 and NetworkGetNetworkIdFromEntity(pedVeh) or nil

        if pedNet ~= lastTrackedNet then
            finishSent = false
            sawNearEnd = false
            stuckSince = nil
            skipLock = false
            lastTrackedNet = pedNet
            stuckLoggedNet = nil
        end

        if pedNet then
            local ridingSoundId = activeSounds[pedNet]

            if not ridingSoundId or not DoesEntityExist(pedVeh) then
                stuckSince = nil
                if (uiOpen or miniPlayerEnabled) and vehicleNet == pedNet then
                    SendNUIMessage({ action = "stop" })
                end
            elseif soundExists(ridingSoundId) then
                stuckLoggedNet = nil
                local cur = getTimeStamp(ridingSoundId) or 0
                local dur = getMaxDuration(ridingSoundId) or 0

                if DEBUG and dur > 0 and cur >= (dur - 6.0) then
                    DebugPrint(("nearing end '%s': cur=%.2fs dur=%.2fs sawNearEnd=%s finishSent=%s skipLock=%s paused=%s")
                        :format(ridingSoundId, cur, dur, tostring(sawNearEnd), tostring(finishSent), tostring(skipLock), tostring(vehiclePaused[pedNet])))
                end

                if dur > 0 then
                    if cur >= (dur - NEAR_END_THRESHOLD) then
                        sawNearEnd = true
                    elseif cur < (dur - NEAR_END_RESET_MARGIN) then
                        finishSent = false
                        sawNearEnd = false
                        stuckSince = nil
                    end
                end

                if not finishSent and not skipLock and not vehiclePaused[pedNet] then
                    if dur > 0 and cur >= (dur - NEAR_END_THRESHOLD) then
                        finishSent = true
                        DebugPrint(("songFinished SENT (primary path) net=%s cur=%.2fs dur=%.2fs"):format(tostring(pedNet), cur, dur))
                        TriggerServerEvent("x1s:songFinished", pedNet)
                    end
                end

                if dur > 0 and (uiOpen or miniPlayerEnabled) and vehicleNet == pedNet then
                    SendNUIMessage({
                        action = "progress",
                        current = cur,
                        duration = dur
                    })
                end

                stuckSince = nil
            elseif sawNearEnd and not finishSent and not skipLock and not vehiclePaused[pedNet] then
                finishSent = true
                DebugPrint(("songFinished SENT (sawNearEnd fallback, sound gone) net=%s"):format(tostring(pedNet)))
                TriggerServerEvent("x1s:songFinished", pedNet)
            elseif not finishSent and not skipLock and not vehiclePaused[pedNet] then
                if stuckLoggedNet ~= pedNet then
                    stuckLoggedNet = pedNet
                    DebugPrint(("sound '%s' gone but sawNearEnd=false finishSent=%s - starting stuck grace timer")
                        :format(tostring(ridingSoundId), tostring(finishSent)))
                end

                if not stuckSince then
                    stuckSince = GetGameTimer()
                elseif (GetGameTimer() - stuckSince) >= STUCK_GRACE_MS then
                    finishSent = true
                    stuckSince = nil
                    DebugPrint(("songFinished SENT (stuck-grace fallback) net=%s"):format(tostring(pedNet)))
                    TriggerServerEvent("x1s:songFinished", pedNet)
                end
            end
        end
    end
end)

-------------------------------------------------
-- Exit Vehicle Cleanup
-------------------------------------------------
CreateThread(function()
    local wasInVehicle = false
    local lastVeh = 0

    while true do
        Wait(500)

        local veh = getCurrentVehicle()
        local inVeh = veh ~= 0

        -- The Mini Player is only ever supposed to show while actually
        -- inside a vehicle - tell the NUI whenever that changes so it can
        -- hide itself immediately on foot, regardless of song state.
        if inVeh ~= wasInVehicle then
            SendNUIMessage({ action = "vehicleState", inVehicle = inVeh })
        end

        if inVeh and (not wasInVehicle or veh ~= lastVeh) then
            -- Load THIS vehicle's own Mini Player on/off choice.
            LoadMiniPlayerForVehicle(veh)

            -- Just got into a vehicle (any vehicle, could be a different
            -- one from last time). Every live-update sender below (volume
            -- changes, progress ticks, pause/resume, seeks) already checks
            -- "vehicleNet == net" before forwarding to the NUI - that was
            -- previously only ever set by opening the full menu, so the
            -- Mini Player got a one-time snapshot on entry and then nothing
            -- else. Setting it here too means those same checks pass for
            -- the Mini Player as well, not just the open main menu.
            local net = NetworkGetNetworkIdFromEntity(veh)
            if net and net ~= 0 then
                vehicleNet = net
                soundId = "car_" .. net
                SyncVehicleStateToNUI(net)
            end
        end

        if wasInVehicle and not inVeh then
            if uiOpen then
                CloseCarPlay()
            end
            -- Deliberately NOT clearing the Mini Player here: the vehicle's
            -- song keeps playing after you get out (that's the whole point
            -- of the muffled-from-outside effect), so wiping the display on
            -- exit just means it shows nothing on re-entry instead of the
            -- song that's actually still going. vehicleState above already
            -- hides the widget while on foot; the entry sync above puts the
            -- right song back the moment you get back in.

            vehicleNet = nil
            soundId = nil
            finishSent = false
            sawNearEnd = false
            stuckSince = nil
            skipLock = false
            miniPlayerEnabled = false -- on foot; the next vehicle loads its own choice
        end

        wasInVehicle = inVeh
        lastVeh = veh
    end
end)

-------------------------------------------------
-- Radio Install
-------------------------------------------------
local installingRadio = false

local function DrawInstallBar(pct, label)
    local x, y = 0.5, 0.88
    local width, height = 0.16, 0.020

    DrawRect(x, y, width + 0.006, height + 0.008, 0, 0, 0, 160)
    DrawRect(x - (width / 2) + ((width * pct) / 2), y, width * pct, height, 255, 255, 255, 220)

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry("STRING")
    AddTextComponentString(label)
    DrawText(x, y - 0.028)
end

RegisterNetEvent('x1s:radio:beginInstall', function(net, duration)
    if installingRadio then return end
    installingRadio = true

    local startedVeh = getCurrentVehicle()
    local startTime = GetGameTimer()

    CreateThread(function()
        while installingRadio do
            Wait(0)

            local veh = getCurrentVehicle()
            if veh == 0 or veh ~= startedVeh then
                installingRadio = false
                Notify("Installation cancelled - you left the vehicle.")
                break
            end

            local elapsed = GetGameTimer() - startTime
            if elapsed >= duration then
                installingRadio = false
                TriggerServerEvent('x1s:radio:finishInstall', net)
                break
            end

            local pct = math.min(elapsed / duration, 1.0)
            DrawInstallBar(pct, ("Installing radio... %d%%"):format(math.floor(pct * 100)))
        end
    end)
end)

-------------------------------------------------
-- ox_inventory integration
-------------------------------------------------
exports('x1s_useRadioItem', function(data, slot)
    if getCurrentVehicle() == 0 then
        Notify("You need to be seated in a vehicle to install a radio.")
        return
    end

    pcall(function()
        exports.ox_inventory:useItem(data, function(result)
            if not result then return end
            TriggerServerEvent('x1s:radio:tryBeginInstall')
        end)
    end)
end)

-------------------------------------------------
-- Cleanup
-------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
