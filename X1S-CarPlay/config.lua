Config = {}

Config.DriverOnly = false

Config.Command = "carplay"

-- Toggles Streamer Mode: mutes ALL CarPlay music for you only (other players
-- still hear it, and the queue keeps advancing). Also in the CarPlay settings menu.
Config.StreamerCommand = "carplaystreamermode"
Config.Keybind = "9"

Config.Debug = false

Config.Radio = {
    RequireInstall = false,

    Item = "car_radio",

    InstallTime = 8000,

    InstallDriverOnly = true,

    StandaloneUseCommand = "useradio",
    StandaloneGiveCommand = "giveradioitem",
}

Config.DefaultVolume = 0.5

Config.VolumeStep = 0.05

Config.MaxVolume = 1.0

Config.SoundDistance = 10.0
Config.FadeStartDistance = 3.0

Config.FadeSmoothing = 10.0

Config.EnableMuffling = true
Config.MuffledVolumeMultiplier = 0.35

Config.MuffleSmoothing = 0.12

Config.MuffleCheckDoors = true
Config.MuffleCheckRoof = true
Config.MuffleCheckWindows = true

Config.DoorOpenRatioThreshold = 0.08

Config.PositionUpdateInterval = 200

Config.DriftCorrectionInterval = 30000
Config.DriftCorrectionThreshold = 6.0

Config.MaxQueueSize = 50

Config.BlacklistedSongs = {
    -- "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
}

Config.MaxSavedSongs = 500

-- DO NOT TOUCH
Config.PipedInstances = {
    "https://pipedapi.kavin.rocks",
    "https://pipedapi.leptons.xyz",
    "https://pipedapi.adminforge.de",
    "https://pipedapi.nosebs.ru",
    "https://pipedapi-libre.kavin.rocks",
    "https://pipedapi.drgns.space",
}

Config.MaxPlaylistImport = 500
