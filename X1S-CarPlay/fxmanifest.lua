fx_version 'cerulean'
game 'gta5'

author 'X1Studios'
description 'CarPlay v2.5 - Fully Reworked UI and System (self-contained: bundles xSound, no separate resource needed)'
version '2.5.0'

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
