-------------------------------------------------
-- Startup Banner
-------------------------------------------------
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    print([[
 __   __  __   ____
 \ \ / / /_ | / ___|
  \ V /   | | \___ \
  / _ \   | |  ___) |
 /_/ \_\  |_| |____/

  X1Studios CarPlay
       v2.0.0
    ]])
end)

-------------------------------------------------
-- Vehicle State
-------------------------------------------------
local vehicleQueues = {}

local function GetVehicleState(net)
    if not vehicleQueues[net] then
        vehicleQueues[net] = {
            queue = {},
            current = nil,
            volume = Config.DefaultVolume,
            startedAt = 0,
            paused = false,
            pausedAt = nil,
            queueActive = false
        }
    end
    return vehicleQueues[net]
end

local function GetElapsed(state)
    if not state or not state.current then return 0 end
    local now = state.paused and state.pausedAt or GetGameTimer()
    local elapsed = (now - state.startedAt) / 1000.0
    if elapsed < 0 then elapsed = 0 end
    return elapsed
end

local function BroadcastQueue(net)
    local data = vehicleQueues[net]
    TriggerClientEvent("x1s:updateQueue", -1, net, data and data.queue or {}, data and data.queueActive or false)
end

local function NotifyPlayer(src, kind, message)
    if not src or not message then return end
    TriggerClientEvent("x1s:notify", src, kind, message)
end

-------------------------------------------------
-- Validation Helpers
-------------------------------------------------
local function ValidateControl(src, net)
    if not net or net <= 0 then return false end

    local veh = NetworkGetEntityFromNetworkId(net)
    if veh == 0 or not DoesEntityExist(veh) then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    if GetVehiclePedIsIn(ped, false) ~= veh then return false end

    if Config.DriverOnly then
        if GetPedInVehicleSeat(veh, -1) ~= ped then return false end
    end

    if Config.Radio and Config.Radio.RequireInstall then
        local plate = GetVehicleNumberPlateText(veh)
        if type(plate) == "string" then
            plate = plate:gsub("^%s+", ""):gsub("%s+$", "")
        end
        if plate == "" then plate = nil end

        if not plate or not X1SRadio.IsInstalled(plate) then return false end
    end

    return true
end

-------------------------------------------------
-- Blacklisted Songs
-------------------------------------------------
local function ExtractVideoId(link)
    if type(link) ~= "string" then return nil end

    local id = link:match("youtu%.be/([%w_%-]+)")
    if id then return id end

    id = link:match("[?&]v=([%w_%-]+)")
    if id then return id end

    id = link:match("youtube%.com/embed/([%w_%-]+)")
    if id then return id end

    id = link:match("youtube%.com/shorts/([%w_%-]+)")
    if id then return id end

    return nil
end

local blacklistedVideoIds = {}
for _, link in ipairs(Config.BlacklistedSongs or {}) do
    local id = ExtractVideoId(link)
    if id then
        blacklistedVideoIds[id] = true
    else
        print(("^3[X1S-CarPlay]^0 Couldn't read a video ID out of blacklisted link '%s' - "
            .. "skipping it. Make sure it's a normal youtube.com/watch?v=... or youtu.be/... link.")
            :format(tostring(link)))
    end
end

local function IsBlacklisted(link)
    local id = ExtractVideoId(link)
    return id ~= nil and blacklistedVideoIds[id] == true
end

local function SanitizeSongData(data)
    if type(data) ~= "table" then return nil end
    if type(data.link) ~= "string" or data.link == "" then return nil end
    -- Only allow http(s) links - never trust a client-supplied URL blindly.
    if not data.link:match("^https?://") then return nil end

    local function cleanText(v, fallback, maxLen)
        if type(v) ~= "string" or v == "" then return fallback end
        if #v > maxLen then v = v:sub(1, maxLen) end
        return v
    end

    return {
        link = data.link,
        title = cleanText(data.title, "Unknown Title", 120),
        artist = cleanText(data.artist, "Unknown Artist", 80),
        thumbnail = (type(data.thumbnail) == "string" and data.thumbnail:match("^https?://")) and data.thumbnail or ""
    }
end

-------------------------------------------------
-- Play Next Song
-------------------------------------------------
local function PlayNext(net)
    local data = vehicleQueues[net]
    if not data then return end

    TriggerClientEvent("x1s:destroyCarSound", -1, net)

    if not data.queueActive or #data.queue == 0 then
        data.current = nil
        data.paused = false
        data.pausedAt = nil

        if #data.queue == 0 then
            data.queueActive = false
        end

        BroadcastQueue(net)

        if #data.queue == 0 then
            vehicleQueues[net] = nil
        end
        return
    end

    local nextSong = table.remove(data.queue, 1)
    data.current = nextSong
    data.startedAt = GetGameTimer()
    data.paused = false
    data.pausedAt = nil

    TriggerClientEvent('x1s:syncSong', -1, {
        link = nextSong.link,
        net = net,
        title = nextSong.title,
        artist = nextSong.artist,
        thumbnail = nextSong.thumbnail,
        volume = data.volume,
        elapsed = 0
    })

    BroadcastQueue(net)
end

-------------------------------------------------
-- Immediate Playback
-------------------------------------------------
local function StartPlayback(net, state, songData)
    state.current = songData
    state.startedAt = GetGameTimer()
    state.paused = false
    state.pausedAt = nil

    TriggerClientEvent('x1s:syncSong', -1, {
        link = songData.link,
        net = net,
        title = songData.title,
        artist = songData.artist,
        thumbnail = songData.thumbnail,
        volume = state.volume,
        elapsed = 0
    })

    BroadcastQueue(net)
end

-------------------------------------------------
-- Play Song
-------------------------------------------------
RegisterNetEvent('x1s:playSong', function(rawData)
    local src = source
    if not rawData or not rawData.net or rawData.net <= 0 then return end
    if not ValidateControl(src, rawData.net) then
        NotifyPlayer(src, "error", "You're no longer able to control this CarPlay.")
        return
    end

    local songData = SanitizeSongData(rawData)
    if not songData then
        NotifyPlayer(src, "error", "That link couldn't be played.")
        return
    end

    if IsBlacklisted(songData.link) then
        NotifyPlayer(src, "error", "That song isn't allowed here.")
        return
    end

    local net = rawData.net
    local state = GetVehicleState(net)

    StartPlayback(net, state, songData)
    NotifyPlayer(src, "success", "Now playing " .. (songData.title or "your song") .. ".")
end)

-------------------------------------------------
-- Add To Queue
-------------------------------------------------
RegisterNetEvent('x1s:addToQueue', function(rawData)
    local src = source
    if not rawData or not rawData.net or rawData.net <= 0 then return end
    if not ValidateControl(src, rawData.net) then
        NotifyPlayer(src, "error", "You're no longer able to control this CarPlay.")
        return
    end

    local songData = SanitizeSongData(rawData)
    if not songData then
        NotifyPlayer(src, "error", "That link couldn't be added to the queue.")
        return
    end

    if IsBlacklisted(songData.link) then
        NotifyPlayer(src, "error", "That song isn't allowed here.")
        return
    end

    local net = rawData.net
    local state = GetVehicleState(net)

    if #state.queue >= (Config.MaxQueueSize or 50) then
        NotifyPlayer(src, "error", "Queue is full.")
        return
    end

    table.insert(state.queue, songData)
    BroadcastQueue(net)
    NotifyPlayer(src, "success", "Added \"" .. (songData.title or "song") .. "\" to the queue.")
end)

-------------------------------------------------
-- Start Queue
-------------------------------------------------
RegisterNetEvent('x1s:startQueue', function(net)
    local src = source
    if not ValidateControl(src, net) then
        NotifyPlayer(src, "error", "You're no longer able to control this CarPlay.")
        return
    end

    local state = vehicleQueues[net]
    if not state or #state.queue == 0 then
        NotifyPlayer(src, "error", "Queue is empty.")
        return
    end
    if state.queueActive then
        NotifyPlayer(src, "error", "Queue is already running.")
        return
    end

    state.queueActive = true

    if not state.current then
        PlayNext(net)
    else
        BroadcastQueue(net)
    end

    NotifyPlayer(src, "success", "Queue started.")
end)

-------------------------------------------------
-- Manual Skip
-------------------------------------------------
local advanceCooldown = {}

local function TryAdvance(net)
    if advanceCooldown[net] then return false end
    advanceCooldown[net] = true
    PlayNext(net)
    SetTimeout(1200, function()
        advanceCooldown[net] = nil
    end)
    return true
end

RegisterNetEvent('x1s:skip', function(net)
    local src = source
    if not ValidateControl(src, net) then return end
    if not vehicleQueues[net] then return end

    TryAdvance(net)
end)

-------------------------------------------------
-- Auto Finish
-------------------------------------------------
RegisterNetEvent('x1s:songFinished', function(net)
    local src = source
    if not net or not vehicleQueues[net] then return end
    if not ValidateControl(src, net) then return end

    TryAdvance(net)
end)

-------------------------------------------------
-- Queue Re-Sync
-------------------------------------------------
RegisterNetEvent('x1s:requestQueue', function(net)
    local src = source
    if not net or net <= 0 then return end

    local state = vehicleQueues[net]
    TriggerClientEvent("x1s:updateQueue", src, net, state and state.queue or {}, state and state.queueActive or false)
end)

-------------------------------------------------
-- Remove From Queue
-------------------------------------------------
RegisterNetEvent("x1s:removeFromQueue", function(net, index)
    local src = source
    if not ValidateControl(src, net) then return end

    local state = vehicleQueues[net]
    if not state or not state.queue then return end

    local removeIndex = tonumber(index)
    if not removeIndex then return end

    removeIndex = removeIndex + 1
    if removeIndex < 1 or removeIndex > #state.queue then return end

    table.remove(state.queue, removeIndex)

    if #state.queue == 0 then
        state.queueActive = false
    end

    BroadcastQueue(net)
end)

-------------------------------------------------
-- Pause / Resume
-------------------------------------------------
RegisterNetEvent('x1s:pause', function(net)
    local src = source
    if not ValidateControl(src, net) then return end

    local state = vehicleQueues[net]
    if not state or not state.current or state.paused then return end

    state.paused = true
    state.pausedAt = GetGameTimer()

    TriggerClientEvent('x1s:setPaused', -1, net, true, GetElapsed(state))
end)

RegisterNetEvent('x1s:resume', function(net)
    local src = source
    if not ValidateControl(src, net) then return end

    local state = vehicleQueues[net]
    if not state or not state.current or not state.paused then return end

    local pausedDuration = GetGameTimer() - state.pausedAt
    state.startedAt = state.startedAt + pausedDuration
    state.paused = false
    state.pausedAt = nil

    TriggerClientEvent('x1s:setPaused', -1, net, false, GetElapsed(state))
end)

-------------------------------------------------
-- Seek
-------------------------------------------------
RegisterNetEvent('x1s:seek', function(net, time)
    local src = source
    if not ValidateControl(src, net) then return end

    local state = vehicleQueues[net]
    if not state or not state.current then return end

    time = tonumber(time)
    if not time or time < 0 then return end
    if time > 21600 then time = 21600 end

    local now = GetGameTimer()
    state.startedAt = now - (time * 1000)

    if state.paused then
        state.pausedAt = now
    end

    TriggerClientEvent('x1s:seek', -1, net, time)
end)

-------------------------------------------------
-- Volume Sync
-------------------------------------------------
RegisterNetEvent('x1s:setVolume', function(vol, net)
    local src = source
    if not ValidateControl(src, net) then return end

    vol = tonumber(vol)
    if not vol then return end

    local maxVol = Config.MaxVolume or 1.0
    if vol < 0 then vol = 0 end
    if vol > maxVol then vol = maxVol end

    local state = GetVehicleState(net)
    state.volume = vol

    TriggerClientEvent('x1s:updateVolume', -1, vol, net)
end)

-------------------------------------------------
-- Saved Songs
-------------------------------------------------
local savedPlaylists = {}

local function NormalizePlate(plate)
    if type(plate) ~= "string" then return nil end
    plate = plate:gsub("^%s+", ""):gsub("%s+$", "")
    if plate == "" then return nil end
    return plate
end

local function SavedSongsKvpKey(plate)
    return "x1s_carplay_saved_" .. plate
end

local function LoadSavedSongs(plate)
    if savedPlaylists[plate] then return savedPlaylists[plate] end

    local list = {}
    local raw = GetResourceKvpString(SavedSongsKvpKey(plate))

    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == "table" then
            list = decoded
        end
    end

    savedPlaylists[plate] = list
    return list
end

local function PersistSavedSongs(plate)
    SetResourceKvp(SavedSongsKvpKey(plate), json.encode(savedPlaylists[plate] or {}))
end

local function GetPlateForNet(net)
    local veh = NetworkGetEntityFromNetworkId(net)
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    return NormalizePlate(GetVehicleNumberPlateText(veh))
end

local function BroadcastSavedSongs(net, plate)
    TriggerClientEvent("x1s:savedSongsSync", -1, net, savedPlaylists[plate] or {})
end

RegisterNetEvent('x1s:requestSavedSongs', function(net)
    local src = source
    if not net or net <= 0 then return end

    local plate = GetPlateForNet(net)
    if not plate then return end

    TriggerClientEvent("x1s:savedSongsSync", src, net, LoadSavedSongs(plate))
end)

RegisterNetEvent('x1s:saveSong', function(net)
    local src = source
    if not ValidateControl(src, net) then
        NotifyPlayer(src, "error", "You're no longer able to control this CarPlay.")
        return
    end

    local plate = GetPlateForNet(net)
    if not plate then
        NotifyPlayer(src, "error", "Couldn't save that song.")
        return
    end

    local state = vehicleQueues[net]
    if not state or not state.current then
        NotifyPlayer(src, "error", "Nothing is playing to save.")
        return
    end

    local list = LoadSavedSongs(plate)

    for _, song in ipairs(list) do
        if song.link == state.current.link then
            TriggerClientEvent("x1s:savedSongsSync", src, net, list)
            NotifyPlayer(src, "error", "That song is already saved.")
            return
        end
    end

    if #list >= (Config.MaxSavedSongs or 25) then
        NotifyPlayer(src, "error", "Saved list is full.")
        return
    end

    table.insert(list, {
        link = state.current.link,
        title = state.current.title,
        artist = state.current.artist,
        thumbnail = state.current.thumbnail
    })

    PersistSavedSongs(plate)
    BroadcastSavedSongs(net, plate)
    NotifyPlayer(src, "success", "Saved \"" .. (state.current.title or "song") .. "\".")
end)

RegisterNetEvent('x1s:saveSongByLink', function(net, rawData)
    local src = source
    if not ValidateControl(src, net) then
        NotifyPlayer(src, "error", "You're no longer able to control this CarPlay.")
        return
    end

    local songData = SanitizeSongData(rawData)
    if not songData then
        NotifyPlayer(src, "error", "That link couldn't be saved.")
        return
    end

    if IsBlacklisted(songData.link) then
        NotifyPlayer(src, "error", "That song isn't allowed here.")
        return
    end

    local plate = GetPlateForNet(net)
    if not plate then
        NotifyPlayer(src, "error", "That link couldn't be saved.")
        return
    end

    local list = LoadSavedSongs(plate)

    for _, song in ipairs(list) do
        if song.link == songData.link then
            TriggerClientEvent("x1s:savedSongsSync", src, net, list)
            NotifyPlayer(src, "error", "That song is already saved.")
            return
        end
    end

    if #list >= (Config.MaxSavedSongs or 25) then
        NotifyPlayer(src, "error", "Saved list is full.")
        return
    end

    table.insert(list, songData)

    PersistSavedSongs(plate)
    BroadcastSavedSongs(net, plate)
    NotifyPlayer(src, "success", "Saved \"" .. (songData.title or "song") .. "\".")
end)

-------------------------------------------------
-- Save Playlists
-------------------------------------------------
local function ExtractPlaylistId(link)
    if type(link) ~= "string" then return nil end
    return link:match("[?&]list=([%w_%-]+)")
end

local function DecodeXmlEntities(s)
    if type(s) ~= "string" or s == "" then return s end
    s = s:gsub("&#x(%x+);", function(hex) return string.char(tonumber(hex, 16) % 256) end)
    s = s:gsub("&#(%d+);", function(n) return string.char(tonumber(n) % 256) end)
    s = s:gsub("&lt;", "<")
    s = s:gsub("&gt;", ">")
    s = s:gsub("&quot;", '"')
    s = s:gsub("&#39;", "'")
    s = s:gsub("&apos;", "'")
    s = s:gsub("&amp;", "&")
    return s
end

local function FetchPlaylistVideosFromYouTube(playlistId, cb)
    local url = "https://www.youtube.com/feeds/videos.xml?playlist_id=" .. playlistId

    PerformHttpRequest(url, function(statusCode, response, _headers)
        if statusCode ~= 200 or type(response) ~= "string" or response == "" then
            print(("^3[X1S-CarPlay]^0 YouTube playlist feed failed (status=%s) - falling back to Piped"):format(tostring(statusCode)))
            cb(false, nil)
            return
        end

        local videos = {}
        local cap = Config.MaxPlaylistImport or 50

        for entry in response:gmatch("<entry>(.-)</entry>") do
            if #videos >= cap then break end

            local videoId = entry:match("<yt:videoId>%s*([%w_%-]+)%s*</yt:videoId>")
            local title = entry:match("<title>(.-)</title>")
            local uploader = entry:match("<author>.-<name>(.-)</name>")
            local thumb = entry:match('<media:thumbnail url="(.-)"')

            if videoId then
                title = DecodeXmlEntities(title)
                uploader = DecodeXmlEntities(uploader)

                videos[#videos + 1] = {
                    link = "https://www.youtube.com/watch?v=" .. videoId,
                    title = (type(title) == "string" and title ~= "") and title or "Unknown Title",
                    artist = (type(uploader) == "string" and uploader ~= "") and uploader or "Unknown Artist",
                    thumbnail = (type(thumb) == "string") and thumb or ""
                }
            end
        end

        if #videos == 0 then
            cb(false, nil)
            return
        end

        cb(true, videos)
    end, "GET", "", {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        ["Accept"] = "application/atom+xml, application/xml, text/xml, */*"
    })
end

local function FetchPlaylistVideosFromPiped(playlistId, cb)
    local instances = Config.PipedInstances
    if type(instances) ~= "table" or #instances == 0 then
        instances = { Config.PipedInstance or "https://pipedapi.kavin.rocks" }
    end

    local function tryInstance(index)
        local base = instances[index]
        if not base then
            cb(false, nil, "Couldn't reach the playlist service.")
            return
        end

        local url = base .. "/playlists/" .. playlistId
        local finished = false

        local function finish(...)
            if finished then return end
            finished = true
            cb(...)
        end

        SetTimeout(6000, function()
            if finished then return end
            finished = true
            print(("^3[X1S-CarPlay]^0 Piped instance '%s' timed out - trying next"):format(base))
            tryInstance(index + 1)
        end)

        PerformHttpRequest(url, function(statusCode, response, _headers)
            if finished then return end

            if statusCode ~= 200 or not response then
                print(("^3[X1S-CarPlay]^0 Piped instance '%s' failed (status=%s) - trying next"):format(base, tostring(statusCode)))
                finished = true
                tryInstance(index + 1)
                return
            end

            local ok, decoded = pcall(json.decode, response)
            if not ok or type(decoded) ~= "table" or type(decoded.relatedStreams) ~= "table" then
                finished = true
                tryInstance(index + 1)
                return
            end

            local videos = {}
            local cap = Config.MaxPlaylistImport or 50

            for _, item in ipairs(decoded.relatedStreams) do
                if #videos >= cap then break end

                if type(item.url) == "string" and item.url:match("^/watch%?v=") then
                    videos[#videos + 1] = {
                        link = "https://www.youtube.com" .. item.url,
                        title = (type(item.title) == "string" and item.title ~= "") and item.title or "Unknown Title",
                        artist = (type(item.uploaderName) == "string" and item.uploaderName ~= "") and item.uploaderName or "Unknown Artist",
                        thumbnail = (type(item.thumbnail) == "string") and item.thumbnail or ""
                    }
                end
            end

            if #videos == 0 then
                finish(false, nil, "That playlist looks empty or private.")
                return
            end

            finish(true, videos, nil)
        end, "GET", "", {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            ["Accept"] = "application/json"
        })
    end

    tryInstance(1)
end

local function FetchPlaylistVideos(playlistId, cb)
    FetchPlaylistVideosFromYouTube(playlistId, function(ok, videos)
        if ok then
            cb(true, videos, nil)
            return
        end

        FetchPlaylistVideosFromPiped(playlistId, cb)
    end)
end

RegisterNetEvent('x1s:savePlaylistByLink', function(net, rawData)
    local src = source
    if not ValidateControl(src, net) then
        TriggerClientEvent("x1s:playlistImportResult", src, false, "You're no longer able to control this CarPlay.")
        return
    end
    if type(rawData) ~= "table" or type(rawData.link) ~= "string" then return end

    local playlistId = ExtractPlaylistId(rawData.link)
    if not playlistId then
        TriggerClientEvent("x1s:playlistImportResult", src, false, "That doesn't look like a YouTube playlist link.")
        return
    end

    local plate = GetPlateForNet(net)
    if not plate then
        TriggerClientEvent("x1s:playlistImportResult", src, false, "Couldn't import that playlist.")
        return
    end

    FetchPlaylistVideos(playlistId, function(ok, videos, err)
        if not ok then
            TriggerClientEvent("x1s:playlistImportResult", src, false, err)
            return
        end

        local list = LoadSavedSongs(plate)
        local cap = Config.MaxSavedSongs or 25
        local added = 0

        for _, video in ipairs(videos) do
            if #list >= cap then break end

            if not IsBlacklisted(video.link) then
                local exists = false
                for _, song in ipairs(list) do
                    if song.link == video.link then
                        exists = true
                        break
                    end
                end

                if not exists then
                    table.insert(list, video)
                    added = added + 1
                end
            end
        end

        if added > 0 then
            PersistSavedSongs(plate)
            BroadcastSavedSongs(net, plate)
        end

        TriggerClientEvent("x1s:playlistImportResult", src, true, nil, added, #videos)
    end)
end)

RegisterNetEvent('x1s:removeSavedSong', function(net, index)
    local src = source
    if not ValidateControl(src, net) then return end

    local plate = GetPlateForNet(net)
    if not plate then return end

    local list = LoadSavedSongs(plate)
    local removeIndex = tonumber(index)
    if not removeIndex then return end

    removeIndex = removeIndex + 1
    if removeIndex < 1 or removeIndex > #list then
        BroadcastSavedSongs(net, plate)
        return
    end

    table.remove(list, removeIndex)
    PersistSavedSongs(plate)
    BroadcastSavedSongs(net, plate)
end)

RegisterNetEvent('x1s:playSavedSong', function(net, index)
    local src = source
    if not ValidateControl(src, net) then
        NotifyPlayer(src, "error", "You're no longer able to control this CarPlay.")
        return
    end

    local plate = GetPlateForNet(net)
    if not plate then
        NotifyPlayer(src, "error", "Couldn't play that song.")
        return
    end

    local list = LoadSavedSongs(plate)
    local playIndex = tonumber(index)
    if not playIndex then
        NotifyPlayer(src, "error", "Couldn't play that song.")
        return
    end

    playIndex = playIndex + 1
    local songData = list[playIndex]
    if not songData then
        NotifyPlayer(src, "error", "Couldn't play that song.")
        return
    end

    if IsBlacklisted(songData.link) then
        NotifyPlayer(src, "error", "That song isn't allowed here.")
        return
    end

    local state = GetVehicleState(net)
    StartPlayback(net, state, songData)
    NotifyPlayer(src, "success", "Now playing " .. (songData.title or "your song") .. ".")
end)

RegisterNetEvent('x1s:queueSavedSong', function(net, index)
    local src = source
    if not ValidateControl(src, net) then
        NotifyPlayer(src, "error", "You're no longer able to control this CarPlay.")
        return
    end

    local plate = GetPlateForNet(net)
    if not plate then
        NotifyPlayer(src, "error", "Couldn't add that to the queue.")
        return
    end

    local list = LoadSavedSongs(plate)
    local queueIndex = tonumber(index)
    if not queueIndex then
        NotifyPlayer(src, "error", "Couldn't add that to the queue.")
        return
    end

    queueIndex = queueIndex + 1
    local songData = list[queueIndex]
    if not songData then
        NotifyPlayer(src, "error", "Couldn't add that to the queue.")
        return
    end

    if IsBlacklisted(songData.link) then
        NotifyPlayer(src, "error", "That song isn't allowed here.")
        return
    end

    local state = GetVehicleState(net)
    if #state.queue >= (Config.MaxQueueSize or 50) then
        NotifyPlayer(src, "error", "Queue is full.")
        return
    end

    table.insert(state.queue, {
        link = songData.link,
        title = songData.title,
        artist = songData.artist,
        thumbnail = songData.thumbnail
    })

    BroadcastQueue(net)
    NotifyPlayer(src, "success", "Added \"" .. (songData.title or "song") .. "\" to the queue.")
end)

-------------------------------------------------
-- Sync For New
-------------------------------------------------
RegisterNetEvent('x1s:requestSync', function()
    local src = source
    local snapshot = {}

    for net, state in pairs(vehicleQueues) do
        if state.current then
            snapshot[#snapshot + 1] = {
                net = net,
                link = state.current.link,
                title = state.current.title,
                artist = state.current.artist,
                thumbnail = state.current.thumbnail,
                volume = state.volume,
                elapsed = GetElapsed(state),
                paused = state.paused
            }
        end
    end

    if #snapshot > 0 then
        TriggerClientEvent('x1s:fullSync', src, snapshot)
    end
end)

-------------------------------------------------
-- Vehicle Delete Detection
-------------------------------------------------
CreateThread(function()
    while true do
        Wait(2000)

        for net, _ in pairs(vehicleQueues) do
            local veh = NetworkGetEntityFromNetworkId(net)

            if veh == 0 or not DoesEntityExist(veh) then
                TriggerClientEvent("x1s:destroyCarSound", -1, net)
                vehicleQueues[net] = nil
            end
        end
    end
end)

-------------------------------------------------
-- Periodic Drift Correction
-------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.DriftCorrectionInterval or 30000)

        for net, state in pairs(vehicleQueues) do
            if state.current and not state.paused then
                local elapsed = GetElapsed(state)
                if elapsed > 12 then
                    TriggerClientEvent('x1s:driftCorrect', -1, net, elapsed)
                end
            end
        end
    end
end)

-------------------------------------------------
-- Update Checker
-------------------------------------------------
local resourceName = GetCurrentResourceName()
local currentVersion = GetResourceMetadata(resourceName, 'version', 0)

local versionUrl = "https://raw.githubusercontent.com/X1Studios/X1Studios-CarPlay/main/version.txt"

local function CheckForUpdates()
    PerformHttpRequest(versionUrl, function(statusCode, responseText, headers)
        if statusCode ~= 200 then
            print("^1[Update Checker] Unable to check for updates (HTTP Error " .. statusCode .. ")^0")
            return
        end

        local latestVersion = responseText:gsub("%s+", "")

        if latestVersion == currentVersion then
            print("^2[Update Checker] " .. resourceName .. " is up to date! (v" .. currentVersion .. ")^0")
        else
            print("^3-------------------------------------------------------^0")
            print("^1[Update Checker] Update Available for " .. resourceName .. "!^0")
            print("^3Current Version:^0 " .. currentVersion)
            print("^2Latest Version:^0 " .. latestVersion)
            print("^5Download:^0 https://github.com/X1Studios/X1Studios-CarPlay")
            print("^3-------------------------------------------------------^0")
        end
    end, "GET")
end

CreateThread(function()
    Wait(3000)
    CheckForUpdates()
end)
