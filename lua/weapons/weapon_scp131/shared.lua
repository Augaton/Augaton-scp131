AddCSLuaFile()

if not guthscp then
    error( "guthscp131 - fatal error! GuthSCP Base is required!" )
    return
end

local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

SWEP.Category               = "GuthSCP"
SWEP.PrintName              = "SCP-131"        
SWEP.Author                 = "Augaton"
SWEP.Instructions           = "Clic Gauche : Gazouiller (Chirp) | Recharger : Changer de mode de vue"
SWEP.ViewModel              = ""
SWEP.WorldModel             = ""

SWEP.Spawnable              = true
SWEP.AdminOnly              = false

SWEP.Primary.ClipSize       = -1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic      = false
SWEP.Primary.Ammo           = "None"

SWEP.Secondary.ClipSize     = -1
SWEP.Secondary.DefaultClip  = -1
SWEP.Secondary.Automatic    = false
SWEP.Secondary.Ammo         = "None"

SWEP.HoldType               = "normal"

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:Deploy() 
    if SERVER then
        local ply = self:GetOwner()
        ply:SetWalkSpeed(config131.walk_speed or 160)
        ply:SetRunSpeed(config131.run_speed or 350)
    end
    return true 
end

if CLIENT then
    guthscp.spawnmenu.add_weapon(SWEP, "SCPs")
end