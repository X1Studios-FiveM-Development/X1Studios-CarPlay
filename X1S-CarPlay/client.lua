-------------------------------------------------
-- State
-------------------------------------------------
local vehicleNet = nil
local soundId = nil
local finishSent = false
local skipLock = false
local uiOpen = false
local sawNearEnd = false

local activeSounds = {}
local vehicleSongs = {}
local vehicleVolumes = {}
local vehiclePaused = {}

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

local function SafeSeek(id, time)
    if not time or time <= 0 then return end

    CreateThread(function()
        local tries = 0
        while tries < 50 do
            if not exports.xsound:soundExists(id) then return end
            if (exports.xsound:getMaxDuration(id) or 0) > 0 then
                DebugPrint(("SafeSeek firing on '%s' -> %.2fs"):format(id, time))
                exports.xsound:setTimeStamp(id, time)
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

    local id = "car_" .. net
    if exports.xsound:soundExists(id) then
        exports.xsound:setVolume(id, vol)
    end

    if uiOpen and vehicleNet == net then
        SendNUIMessage({ action = "volumeSync", volume = vol })
    end
end)

-------------------------------------------------
-- Pause State Sync
-------------------------------------------------
RegisterNetEvent("x1s:setPaused", function(net, paused, elapsed)
    vehiclePaused[net] = paused

    local id = "car_" .. net
    if exports.xsound:soundExists(id) then
        if paused then
            exports.xsound:Pause(id)
        else
            if elapsed and elapsed > 0 then
                DebugPrint(("resume seek firing on '%s' -> %.2fs"):format(id, elapsed))
                exports.xsound:setTimeStamp(id, elapsed)
            end
            exports.xsound:Resume(id)
        end
    end

    if net == vehicleNet then
        finishSent = false
        sawNearEnd = false
        stuckSince = nil
        if uiOpen then
            SendNUIMessage({ action = paused and "paused" or "resumed" })
        end
    end
end)

-------------------------------------------------
-- Seek Broadcast
-------------------------------------------------
RegisterNetEvent("x1s:seek", function(net, time)
    local id = "car_" .. net

    if exports.xsound:soundExists(id) then
        DebugPrint(("manual seek firing on '%s' -> %.2fs"):format(id, time))
        exports.xsound:setTimeStamp(id, time)
    end

    if net == vehicleNet then
        finishSent = false
        sawNearEnd = false
        stuckSince = nil

        if uiOpen and exports.xsound:soundExists(id) then
            local dur = exports.xsound:getMaxDuration(id) or 0
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
    if not exports.xsound:soundExists(id) then return end
    if vehiclePaused[net] then return end
    if (exports.xsound:getMaxDuration(id) or 0) <= 0 then return end -- player not actually ready/loaded yet

    local cur = exports.xsound:getTimeStamp(id) or 0
    local threshold = Config.DriftCorrectionThreshold or 1.0

    if math.abs(cur - elapsed) > threshold then
        DebugPrint(("driftCorrect firing on '%s' -> cur=%.2fs server=%.2fs"):format(id, cur, elapsed))
        exports.xsound:setTimeStamp(id, elapsed)
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

    if exports.xsound:soundExists(id) then
        exports.xsound:Destroy(id)
        Wait(300)
    end

    exports.xsound:PlayUrlPos(
        id,
        data.link,
        vehicleVolumes[data.net],
        GetEntityCoords(veh),
        false
    )

    exports.xsound:Distance(id, Config.SoundDistance)

    if data.elapsed and data.elapsed > 0 then
        SafeSeek(id, data.elapsed)
    end

    activeSounds[data.net] = id

    if DEBUG then
        CreateThread(function()
            local last = nil
            for i = 1, 20 do -- ~4 seconds at 200ms
                if not exports.xsound:soundExists(id) then return end
                local cur = exports.xsound:getTimeStamp(id) or 0
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

    if pedVeh == veh and uiOpen then
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

            if not exports.xsound:soundExists(id) then
                exports.xsound:PlayUrlPos(
                    id,
                    data.link,
                    vehicleVolumes[data.net],
                    GetEntityCoords(veh),
                    false
                )
                exports.xsound:Distance(id, Config.SoundDistance)

                if data.elapsed and data.elapsed > 0 then
                    SafeSeek(id, data.elapsed)
                end

                if data.paused then
                    exports.xsound:Pause(id)
                end

                activeSounds[data.net] = id
            end

            if uiOpen and vehicleNet == data.net then
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

    if exports.xsound:soundExists(id) then
        exports.xsound:Destroy(id)
    end

    activeSounds[net] = nil
    vehicleSongs[net] = nil
    vehicleVolumes[net] = nil
    vehiclePaused[net] = nil

    if vehicleNet == net then
        finishSent = false
        sawNearEnd = false
        stuckSince = nil
        skipLock = false
        if uiOpen then
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

            if id and exports.xsound:soundExists(id) then
                exports.xsound:Position(id, GetEntityCoords(veh))
                exports.xsound:Distance(id, 10000.0)
                exports.xsound:setVolume(id, vehicleVolumes[net] or Config.DefaultVolume)
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
                if exports.xsound:soundExists(id) then
                    local isInside = pedVeh ~= 0 and pedVeh == veh

                    if not isInside then
                        exports.xsound:Position(id, GetEntityCoords(veh))
                        exports.xsound:Distance(id, Config.SoundDistance)
                    end

                    if Config.EnableMuffling then
                        local baseVol = vehicleVolumes[net] or Config.DefaultVolume
                        local targetVol = isInside and baseVol or (baseVol * Config.MuffledVolumeMultiplier)
                        exports.xsound:setVolume(id, targetVol)
                    end
                end
            else
                activeSounds[net] = nil
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
                if uiOpen and vehicleNet == pedNet then
                    SendNUIMessage({ action = "stop" })
                end
            elseif exports.xsound:soundExists(ridingSoundId) then
                stuckLoggedNet = nil
                local cur = exports.xsound:getTimeStamp(ridingSoundId) or 0
                local dur = exports.xsound:getMaxDuration(ridingSoundId) or 0

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

                if dur > 0 and uiOpen and vehicleNet == pedNet then
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

    while true do
        Wait(500)

        local ped = PlayerPedId()
        local inVeh = IsPedInAnyVehicle(ped, false)

        if wasInVehicle and not inVeh then
            if uiOpen then
                CloseCarPlay()
            end

            vehicleNet = nil
            soundId = nil
            finishSent = false
            sawNearEnd = false
            stuckSince = nil
            skipLock = false
        end

        wasInVehicle = inVeh
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
