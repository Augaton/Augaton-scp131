AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

SWEP.GuthSCPLVL = 0

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1.5)

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local sounds = config131.chirp_sounds
    if sounds and #sounds > 0 then
        owner:EmitSound(sounds[math.random(#sounds)], 75, math.random(90, 110))
    end
    
    owner:SetAnimation(PLAYER_ATTACK1)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
end

function SWEP:Think()
    if self.GuthSCPLVL != (config131.keycard_level or 0) then
        self.GuthSCPLVL = config131.keycard_level or 0
    end
end