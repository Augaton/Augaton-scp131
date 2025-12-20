hook.Add( "HUDPaint", "SCP131:Targeting173", function()
    local ply = LocalPlayer()
    if not ply:Alive() or ply:GetNWString("guthscp_role") ~= "scp131" then return end

    local tr = ply:GetEyeTrace()
    if IsValid( tr.Entity ) and tr.Entity:GetNWString("guthscp_role") == "scp173" then
        draw.SimpleText( "STATUE FIXÉE", "DermaDefault", ScrW() / 2, ScrH() / 2 + 50, Color( 255, 0, 0 ), TEXT_ALIGN_CENTER )
    end
end )