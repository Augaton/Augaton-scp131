local MODULE = {
    name = "SCP-131",
    author = "Augaton",
    version = "1.0.0",
    description = [[SCP 131 system for players, including compatibility with 173 system.]],
    icon = "icon16/eye.png",
    version_url = "https://raw.githubusercontent.com/Augaton/Augaton-scp131/refs/heads/main/lua/guthscp/modules/scp131/main.lua",
    dependencies = {
        base = "2.4.0",
        guthscp173 = "2.1.0",
        guthscpkeycard = "optional:2.1.6",
    },
    requires = {
        ["server.lua"] = guthscp.REALMS.SERVER,
        ["shared.lua"] = guthscp.REALMS.SHARED,
    },
}

MODULE.menu = {
    config = {
        form = {
            "General",
            {
                type = "Number",
                name = "Keycard Level",
                id = "keycard_level",
                desc = [[Set a keycard level for SCP-131's swep to open doors.]],
                default = 3,
                min = 0,
                max = function( self, numwang )
                    if self:is_disabled() then return 0 end
                    return guthscp.modules.guthscpkeycard.max_keycard_level
                end,
                is_disabled = function( self, numwang )
                    return guthscp.modules.guthscpkeycard == nil
                end,
            },
            {
                type = "Bool",
                name = "Immortal",
                id = "scp131_immortal",
                desc = "If checked, the player as SCP-131 can't take damage.",
                default = true,
            },
            {
                type = "Number",
                name = "Walk Speed",
                id = "walk_speed",
                desc = "Walking speed of the player.",
                default = 160,
            },
            {
                type = "Number",
                name = "Run Speed",
                id = "run_speed",
                desc = "Running speed of the player (SCP-131 is usually fast).",
                default = 350,
            },
            
        },
    },
    details = {
        {
            text = "CC-BY-SA",
            icon = "icon16/page_white_key.png",
        },
        "Social",
        {
            text = "Github",
            icon = "guthscp/icons/github.png",
            url = "https://github.com/Augaton/Augaton-scp131",
        },
        {
            text = "Discord",
            icon = "guthscp/icons/discord.png",
            url = "https://discord.gg/kJFQe95pgh",
        },
    },
}

function MODULE:init()
    self:info("SCP-131 Player Module loaded.")
end

guthscp.module.hot_reload( "scp131" )
return MODULE