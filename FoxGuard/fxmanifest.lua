fx_version 'cerulean'
game 'gta5'

author 'FoxGuard Dev Team'
description 'FoxGuard integration for FoxCore Framework'
version '1.0.0'

server_scripts {
    'foxguard_server.lua'
}

client_scripts {
    'foxguard_client.lua'
}

server_exports {
    'VerifyPlayer',
    'IsFoxGuardEnabled',
    'SetFoxGuardEnabled',
    'GetFramework',
    'RegisterGlobalBan'
}