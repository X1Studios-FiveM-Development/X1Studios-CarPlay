fx_version 'cerulean'
game 'gta5'

author 'X1Studios'
description 'CarPlay v2 - Fully Reworked UI and System'
version '2.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'radio_server.lua',
    'server.lua'
}
