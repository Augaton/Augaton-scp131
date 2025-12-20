local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131
scp131 = scp131 or {}

-- On enregistre les joueurs qui portent l'arme du 131
scp131.filter = guthscp.players_filter:new( "weapon_scp131" ) -- Remplace par le nom exact de ton swep

if SERVER then
    scp131.filter:listen_disconnect()
    scp131.filter:listen_weapon_users( "weapon_scp131" )

    -- Configuration automatique au spawn/prise d'arme
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

-- Compatibilité clignement (Blink)
-- Empêche le 131 de cligner des yeux s'il est configuré comme tel
hook.Add( "guthscp173:can_blink", "scp131:prevent_blink", function( ply )
    if scp131.is_scp_131( ply ) then
        local res = config131.scp131_blink_res or 0
        if res == 0 then return false end 
    end
end )