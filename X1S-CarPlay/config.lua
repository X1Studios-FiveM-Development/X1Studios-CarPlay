Config = {}

-------------------------------------------------
-- Access
-------------------------------------------------
Config.DriverOnly = false

Config.Command = "carplay"
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
Config.SoundDistance = 10.0

Config.EnableMuffling = true
Config.MuffledVolumeMultiplier = 0.35

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
