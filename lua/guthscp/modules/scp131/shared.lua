local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131
scp131 = scp131 or {}

local guth173 = guthscp.modules.guthscp173

scp131.filter = guthscp.players_filter:new( "weapon_scp131" )

if SERVER then
    scp131.filter:listen_disconnect()
    scp131.filter:listen_weapon_users( "weapon_scp131" )

    scp131.filter.event_added:add_listener( "scp131:setup", function( ply )
        ply:SetWalkSpeed( config131.walk_speed or 160 )
        ply:SetRunSpeed( config131.run_speed or 350 )
    end )
end

function scp131.get_scps_131()
    return scp131.filter:get_entities()
end

function scp131.is_scp_131( ply )
    if CLIENT and ply == nil then ply = LocalPlayer() end
    return scp131.filter:is_in( ply )
end