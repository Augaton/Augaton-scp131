local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

scp173 = guthscp.modules.scp173

hook.Add( "PlayerShouldTakeDamage", "scp131:no_damage", function( ply )
    if config131.scp131_immortal and scp131.is_scp_131( ply ) then
        return false
    end
end )

hook.Add( "guthscp173:can_freeze_173", "scp131freeze173", function( ent, scp )
    if ent:IsPlayer() and scp131.is_scp_131(ent) then
        return true
    end
end )

hook.Add( "guthscp173:should_blink", "scp131noblink", function( ent )
    if ent:IsPlayer() and scp131.is_scp_131(ent) then
        return false
    end
end )

