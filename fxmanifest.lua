fx_version 'cerulean'
game 'gta5'

author 'takenncs'
description 'Arveetemenüü | bsfrp 2.0 (by takenncs)'
version '2.1'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/main.js',
    'web/style.css',
    'config.lua',
}

server_exports {
    'BillPlayer',
    'BillPlayerOffline',
}

client_exports {
    'OpenBillingMenu',
    'CloseBillingMenu',
}