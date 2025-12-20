local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

hook.Add( "PlayerShouldTakeDamage", "scp131:no_damage", function( ply )
    if config131.scp131_immortal and scp131.is_scp_131( ply ) then
        return false
    end
end )

hook.Add( "Think", "scp131:block_173_logic", function()
    if not config131.scp131_anti173 then return end

    local scps_131 = scp131.get_scps_131()
    if #scps_131 == 0 then return end

    local scps_173 = guthscp.modules.guthscp173.get_scps_173()
    if #scps_173 == 0 then return end

    for _, v173 in ipairs( scps_173 ) do
        if not IsValid( v173 ) or not v173:Alive() then continue end

        if v173:GetNWBool( "guthscp173:looked", false ) then continue end

        for _, v131 in ipairs( scps_131 ) do
            if not IsValid( v131 ) or not v131:Alive() then continue end

            if guthscp.modules.guthscp173.is_looking_at( v131, v173 ) then
                v173:SetNWBool( "guthscp173:looked", true )
                break
            end
        end
    end
end )