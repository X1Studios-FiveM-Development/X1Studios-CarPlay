Config = {}

-------------------------------------------------
-- Access
-------------------------------------------------
Config.DriverOnly = false

Config.Command = "carplay"

-- Toggles Streamer Mode: mutes ALL CarPlay music for you only (other players
-- still hear it, and the queue keeps advancing). Also in the CarPlay settings menu.
Config.StreamerCommand = "carplaystreamermode"
Config.Keybind = "9"

Config.Debug = false

-------------------------------------------------
-- Radio Item / Install
-------------------------------------------------
Config.Radio = {
    RequireInstall = false,

    Item = "car_radio",

    InstallTime = 8000,

    InstallDriverOnly = true,

    StandaloneUseCommand = "useradio",
    StandaloneGiveCommand = "giveradioitem",
}

-------------------------------------------------
-- Volume
-------------------------------------------------
Config.DefaultVolume = 0.5

Config.VolumeStep = 0.05

Config.MaxVolume = 1.0

-------------------------------------------------
-- Distance / Muffling
-------------------------------------------------
-- Walking away from a car fades its music out smoothly:
--   full volume within FadeStartDistance (meters) of the vehicle,
--   easing down to silent at SoundDistance (meters).
Config.SoundDistance = 10.0
Config.FadeStartDistance = 3.0

-- How quickly the volume follows the target (per second). Higher = snappier,
-- lower = softer/slower. ~10 is a good "smooth but responsive" value.
Config.FadeSmoothing = 10.0

Config.EnableMuffling = true
Config.MuffledVolumeMultiplier = 0.35

-- How fast the volume slides toward its target each PositionUpdateInterval tick
-- (0.0-1.0). Lower = smoother/slower fade between muffled and unmuffled instead
-- of an instant jump. 1.0 = old instant-snap behavior.
Config.MuffleSmoothing = 0.12

-- A sealed car muffles sound; if any of these are true and detected "open",
-- muffling is skipped entirely for that vehicle so sound comes through clearly.
Config.MuffleCheckDoors = true
Config.MuffleCheckRoof = true
Config.MuffleCheckWindows = true

-- GetVehicleDoorAngleRatio() value above which a door counts as "open" (0.0 = closed)
Config.DoorOpenRatioThreshold = 0.08

-------------------------------------------------
-- Sync
-------------------------------------------------
Config.PositionUpdateInterval = 200

Config.DriftCorrectionInterval = 30000
Config.DriftCorrectionThreshold = 6.0

-------------------------------------------------
-- Queue
-------------------------------------------------
Config.MaxQueueSize = 50

-------------------------------------------------
-- Blacklisted Songs
-------------------------------------------------
Config.BlacklistedSongs = {
    -- "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
}

-------------------------------------------------
-- Saved Songs
-------------------------------------------------
Config.MaxSavedSongs = 500

-------------------------------------------------
-- YouTube Playlist Import
-------------------------------------------------
Config.PipedInstances = {
    "https://pipedapi.kavin.rocks",
    "https://pipedapi.leptons.xyz",
    "https://pipedapi.adminforge.de",
    "https://pipedapi.nosebs.ru",
    "https://pipedapi-libre.kavin.rocks",
    "https://pipedapi.drgns.space",
}

Config.MaxPlaylistImport = 500
