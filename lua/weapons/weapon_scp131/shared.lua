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
SWEP.Instructions           = "Clic gauche : gazouiller | Clic droit maintenu sur un joueur : s'attacher ou se detacher | Saut maintenu face a un mur : grimper"
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

--  niveau de carte magnetique, tenu a jour par le module sur changement de configuration
SWEP.GuthSCPLVL             = 0

--  cadence de mise a jour de la barre de progression du lien
local BOND_UPDATE_RATE = 0.1

function SWEP:Initialize()
    self:SetHoldType( "normal" )
end

function SWEP:Deploy()
    if SERVER then
        local owner = self:GetOwner()

        if IsValid( owner ) then
            scp131.apply_speeds( owner )
        end
    end

    return true
end

--  gazouillis
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire( CurTime() + math.max( config131.chirp_cooldown, 0.1 ) )

    local owner = self:GetOwner()
    if not IsValid( owner ) then return end

    owner:SetAnimation( PLAYER_ATTACK1 )

    if CLIENT then return end

    local sounds = config131.chirp_sounds
    if not sounds or #sounds == 0 then return end

    guthscp.sound.play( owner, sounds, config131.sound_hear_distance, false, config131.sound_volume )
end

--  le lien se noue en maintenant le clic droit : tout se joue dans Think
function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire( CurTime() + 0.1 )
end


if SERVER then
    --  joueur vise, a portee de bras : ni soi-meme, ni l'autre pod
    function SWEP:get_bond_target()
        local owner = self:GetOwner()
        if not IsValid( owner ) then return end

        local entity = guthscp.world.player_trace_attack( owner, config131.bond_range, Vector( 8, 8, 8 ) ).Entity
        if not IsValid( entity ) or not entity:IsPlayer() then return end
        if not entity:Alive() or scp131.is_scp_131( entity ) then return end

        return entity
    end

    function SWEP:reset_bond_channel()
        if not self.bond_target then return end

        self.bond_target = nil
        self.bond_started = nil

        self:SetNWEntity( "scp131:bond_target", NULL )
        self:SetNWFloat( "scp131:bond_progress", 0 )
    end

    function SWEP:Think()
        local owner = self:GetOwner()
        if not IsValid( owner ) then return end

        if not config131.bond_enabled or not owner:KeyDown( IN_ATTACK2 ) or scp131.is_stunned( owner ) then
            self.bond_locked = false

            return self:reset_bond_channel()
        end

        --  un clic droit maintenu ne doit pas nouer puis denouer le lien en boucle
        if self.bond_locked then return end

        local target = self:get_bond_target()
        if not target then
            return self:reset_bond_channel()
        end

        if self.bond_target ~= target then
            self.bond_target = target
            self.bond_started = CurTime()

            self:SetNWEntity( "scp131:bond_target", target )
        end

        local progress = ( CurTime() - self.bond_started ) / math.max( config131.bond_time, 0.1 )

        if progress < 1 then
            --  la barre n'a pas besoin d'un message reseau a chaque tick
            if CurTime() >= ( self.next_bond_update or 0 ) then
                self.next_bond_update = CurTime() + BOND_UPDATE_RATE

                self:SetNWFloat( "scp131:bond_progress", progress )
            end

            return
        end

        --  viser son propre compagnon rompt le lien
        local companion = scp131.get_companion( owner )
        scp131.set_companion( owner, companion ~= target and target or nil )

        local sounds = config131.chirp_sounds
        if sounds and #sounds > 0 then
            guthscp.sound.play( owner, sounds, config131.sound_hear_distance, false, config131.sound_volume )
        end

        self.bond_locked = true
        self:reset_bond_channel()
    end

    function SWEP:OnRemove()
        self:reset_bond_channel()
    end
end


if CLIENT then
    guthscp.spawnmenu.add_weapon( SWEP, "SCPs" )
end
