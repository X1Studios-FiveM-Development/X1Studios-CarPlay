fx_version 'cerulean'
game 'gta5'

author 'X1Studios'
description 'CarPlay v2 - Fully Reworked UI and System (self-contained: bundles xSound, no separate resource needed)'
version '2.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',

    'html/xsound/functions.js',
    'html/xsound/SoundPlayer.js',
    'html/xsound/listener.js',
}

shared_scripts {
    'config.lua'
}

-- xsound/* must load before client.lua: client.lua calls its
-- functions (setVolume, PlayUrlPos, ...) directly now that both live
-- in this one resource, rather than through exports.xsound:*.
-- xsound/config.lua defines the lowercase `config` table its own
-- files use internally - unrelated to this resource's own `Config`
-- (capital C) in config.lua above.
client_scripts {
    'xsound/config.lua',
    'xsound/main.lua',
    'xsound/events.lua',
    'xsound/commands.lua',

    'xsound/exports/info.lua',
    'xsound/exports/play.lua',
    'xsound/exports/manipulation.lua',
    'xsound/exports/events.lua',
    'xsound/effects/main.lua',

    'client.lua'
}

server_scripts {
    'radio_server.lua',
    'server.lua'
}
