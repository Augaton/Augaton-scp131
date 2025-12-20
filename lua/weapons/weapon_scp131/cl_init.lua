include("shared.lua")

local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

hook.Add("CalcView", "SCP131:ViewAdjustment", function(ply, pos, angles, fov)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() != "weapon_scp131" then return end
    if ply:ShouldDrawLocalPlayer() then return end

    local view = {}
    view.origin = pos - Vector(0, 0, 40)
    view.angles = angles
    view.fov = fov
    
    return view
end)

hook.Add("HUDPaint", "SCP131:Target173Indicator", function()
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() != "weapon_scp131" then return end

    local tr = ply:GetEyeTrace()
    if IsValid(tr.Entity) and tr.Entity:GetNWString("guthscp_role") == "scp173" then
        draw.SimpleTextOutlined("173 DÉTECTÉ - CONTACT VISUEL MAINTENU", "DermaDefaultBold", ScrW() / 2, ScrH() * 0.7, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0))
    end
end)
