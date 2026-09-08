AddCSLuaFile()

if not guthscp then
    error( "guthscp131 - fatal error! GuthSCP Base is required!" )
    return
end

--[[
    Porter cette arme, c'est etre SCP-131 : le module la filtre par sa classe.
    Le deplacement, le corps et la garde du 173 vivent dans le module, pas ici :
    ils doivent continuer quand le pod range l'arme (mains, carte). L'arme ne
    porte que le gazouillis et le lien avec un joueur.
]]

local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

SWEP.Category               = "GuthSCP"
SWEP.PrintName              = "SCP-131"
SWEP.Author                 = "Augaton"
SWEP.Instructions           = "Clic gauche : gazouiller | Clic droit maintenu sur un joueur : s'attacher ou se detacher | Sprint : pleine vitesse | Reculer : freiner | Saut maintenu face a un mur : grimper"
SWEP.ViewModel              = ""
SWEP.WorldModel             = ""

SWEP.Spawnable              = true
SWEP.AdminOnly              = true  --  donne par le metier, jamais spawnable par un joueur

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

--  le modele n'a aucune animation : rien a jouer, seulement le son
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire( CurTime() + math.max( config131.chirp_cooldown, 0.1 ) )

    if CLIENT then return end

    scp131.play_sound( self:GetOwner(), scp131.get_sounds( "chirp" ) )
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

        scp131.network_bond_channel( self:GetOwner(), nil, 0 )
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
            self.next_bond_update = 0
        end

        local progress = ( CurTime() - self.bond_started ) / math.max( config131.bond_time, 0.1 )

        if progress < 1 then
            --  la barre n'a pas besoin d'un message reseau a chaque tick
            if CurTime() >= ( self.next_bond_update or 0 ) then
                self.next_bond_update = CurTime() + BOND_UPDATE_RATE

                scp131.network_bond_channel( owner, target, progress )
            end

            return
        end

        --  viser son propre compagnon rompt le lien
        local companion = scp131.get_companion( owner )
        scp131.set_companion( owner, companion ~= target and target or nil )
        scp131.play_sound( owner, scp131.get_sounds( "chirp" ) )

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
