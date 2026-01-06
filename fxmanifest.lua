fx_version 'cerulean'
game 'gta5'

name 'sintic-imagecapture'
description 'Image capture tool for clothing, vehicles, and props'
author 'https://github.com/nethushadev'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.js'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/script.js',
    'in/vehicles.lua',
    'in/props.lua'
}

dependency 'screencapture'
