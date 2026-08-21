local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

--  la garde du 173 et l'attention du compagnon demandent des traces : inutile de les faire a chaque tick
local UPDATE_RATE = 0.25
local next_update = 0

util.AddNetworkString( "scp131:bond_channel" )

--[[
    Progression du lien.

    Elle ne regarde que le pod : une variable reseau sur le SWEP serait diffusee a
    tout le serveur dix fois par seconde pendant l'incantation. Un message cible au
    proprietaire suffit, et rien ne remonte du client vers le serveur.
]]
function scp131.network_bond_channel( ply, target, progress )
    if not IsValid( ply ) or not ply:IsPlayer() then return end

    net.Start( "scp131:bond_channel" )
        net.WriteEntity( IsValid( target ) and target or NULL )
        net.WriteUInt( math.Clamp( math.floor( ( progress or 0 ) * 100 ), 0, 100 ), 7 )
    net.Send( ply )
end

local function notify( ply, text )
    if not IsValid( ply ) then return end
    if not DarkRP or not DarkRP.notify then return end

    DarkRP.notify( ply, 0, 5, text )
end


--=========================================================================
--  Degats : classe Safe, il ne tue pas et ne meurt pas
--=========================================================================

hook.Add( "PlayerShouldTakeDamage", "scp131:damage_rules", function( ply, attacker )
    --  un pod ne blesse personne
    if config131.harmless and attacker ~= ply and IsValid( attacker )
        and attacker:IsPlayer() and scp131.is_scp_131( attacker ) then
        return false
    end

    if config131.scp131_immortal and scp131.is_scp_131( ply ) then return false end
end )

--[[
    Increvable, mais pas inamovible.

    Les degats qu'il encaisse le renversent : il part en roulade et lache le
    173 quelques secondes. Sans cette prise, un pod immortel fige le 173
    indefiniment et personne ne peut rien y faire.
]]
hook.Add( "EntityTakeDamage", "scp131:tumble", function( target, dmginfo )
    local attacker = dmginfo:GetAttacker()

    --  un pod ne fait pas de degats, meme aux props et aux PNJ
    if config131.harmless and IsValid( attacker ) and attacker ~= target
        and attacker:IsPlayer() and scp131.is_scp_131( attacker ) then
        dmginfo:SetDamage( 0 )
        return
    end

    if not config131.tumble_enabled then return end
    if not target:IsPlayer() or not scp131.is_scp_131( target ) then return end
    if scp131.is_stunned( target ) then return end

    local time = CurTime()
    if time < ( target.scp131_next_tumble or 0 ) then return end
    target.scp131_next_tumble = time + config131.tumble_cooldown

    --  direction de la bourrade : la force des degats, sinon le sens attaquant -> pod
    local force = dmginfo:GetDamageForce()
    local direction = Vector( force.x, force.y, 0 )

    if direction:IsZero() and IsValid( attacker ) then
        local offset = target:GetPos() - attacker:GetPos()
        direction = Vector( offset.x, offset.y, 0 )
    end

    if direction:IsZero() then
        direction = Vector( 1, 0, 0 )
    else
        direction:Normalize()
    end

    local sounds = #config131.distress_sounds > 0 and config131.distress_sounds
        or ( #config131.chirp_sounds > 0 and config131.chirp_sounds or nil )

    scp131.tumble(
        target,
        direction * config131.tumble_force + Vector( 0, 0, config131.tumble_lift ),
        config131.tumble_stun_time,
        sounds
    )
end )


--=========================================================================
--  Gardien du SCP-173
--=========================================================================

--[[
    Le pod ne cligne jamais des yeux : tant qu'il regarde le 173, celui-ci reste fige.

    On renvoie explicitement false hors de portee (ou etourdi) plutot que nil :
    le module 173 traite nil comme "applique tes regles habituelles", et ses
    regles excluent les SCP de la liste des regards qui figent.
]]
hook.Add( "guthscp173:can_freeze_173", "scp131:guard_173", function( ent, scp )
    if not ent:IsPlayer() or not scp131.is_scp_131( ent ) then return end
    if scp131.is_stunned( ent ) then return false end
    if ent:GetMoveType() == MOVETYPE_NOCLIP then return false end  --  staff en noclip

    local distance = config131.guard_distance
    if distance > 0 and ent:GetPos():DistToSqr( scp:GetPos() ) > distance * distance then return false end

    return true
end )

hook.Add( "guthscp173:should_blink", "scp131:never_blink", function( ent )
    if not ent:IsPlayer() or not scp131.is_scp_131( ent ) then return end

    --  sonne, il cligne comme tout le monde : c'est la fenetre du 173
    if scp131.is_stunned( ent ) then return end

    return false
end )


--=========================================================================
--  Boucle d'entretien : garde du 173 et attention du compagnon
--=========================================================================

hook.Add( "Think", "scp131:think", function()
    if CurTime() < next_update then return end
    next_update = CurTime() + UPDATE_RATE

    local pods = scp131.get_scps_131()
    local guthscp173 = guthscp.modules.guthscp173
    local scps_173 = guthscp173 and guthscp173.get_scps_173() or {}

    --  sans pod, il reste a effacer le gardien encore affiche chez les 173
    if #pods == 0 and #scps_173 == 0 then return end

    local guard_distance = config131.guard_distance
    local guard_distance_sqr = guard_distance * guard_distance
    local attention_distance_sqr = config131.bond_attention_distance * config131.bond_attention_distance
    local time = CurTime()
    local watchers = {}

    for _, pod in ipairs( pods ) do
        if not IsValid( pod ) or not pod:Alive() then continue end

        --  quel 173 ce pod tient-il sous son oeil ?
        local watched = nil

        if not scp131.is_stunned( pod ) then
            local origin = pod:GetPos()

            for _, scp in ipairs( scps_173 ) do
                if not IsValid( scp ) or not scp:Alive() then continue end
                if guard_distance > 0 and origin:DistToSqr( scp:GetPos() ) > guard_distance_sqr then continue end
                if not scp131.is_looking_at( pod, scp ) then continue end

                watched = scp
                watchers[scp] = watchers[scp] or pod
                break
            end
        end

        --  ecriture seulement sur changement : cette boucle passe quatre fois par seconde
        if pod:GetNW2Entity( "scp131:watched_173", NULL ) ~= ( watched or NULL ) then
            pod:SetNW2Entity( "scp131:watched_173", watched or NULL )
        end

        --  le lien se defait tout seul si le compagnon ne s'occupe plus de lui
        if config131.bond_enabled then
            local companion = scp131.get_companion( pod )

            if companion then
                if not companion:Alive() then
                    scp131.set_companion( pod, nil )
                elseif pod:GetPos():DistToSqr( companion:GetPos() ) <= attention_distance_sqr
                    and scp131.is_looking_at( companion, pod ) then
                    pod.scp131_last_attention = time
                elseif config131.bond_timeout > 0
                    and time - ( pod.scp131_last_attention or time ) > config131.bond_timeout then
                    scp131.set_companion( pod, nil )
                end
            end
        end
    end

    --  cote 173 : savoir qui le tient, sinon il subit sans comprendre
    for _, scp in ipairs( scps_173 ) do
        if not IsValid( scp ) then continue end

        local watcher = watchers[scp] or NULL
        if scp:GetNW2Entity( "scp131:watcher", NULL ) ~= watcher then
            scp:SetNW2Entity( "scp131:watcher", watcher )
        end
    end
end )


--=========================================================================
--  Retours joueur sur le lien
--=========================================================================

hook.Add( "scp131:companion_changed", "scp131:notify", function( pod, companion, previous )
    local name = scp131.get_name( pod )

    if IsValid( previous ) then
        notify( previous, name .. " se detourne de vous." )
    end

    if IsValid( companion ) then
        notify( companion, name .. " s'attache a vous et vous suit." )
        notify( pod, "Vous vous attachez a " .. companion:Nick() .. "." )
    elseif IsValid( previous ) then
        notify( pod, "Vous vous lassez de " .. previous:Nick() .. "." )
    end
end )


hook.Add( "PlayerSpawn", "scp131:reset_wheel", function( ply )
    ply.scp131_wheel_speed = 0
    ply.scp131_wheel_commanded = 0
    ply.scp131_climb_time = 0
end )


--=========================================================================
--  Niveau de carte magnetique et ressources
--=========================================================================

--  le SWEP lisait la config a chaque tick : une mise a jour sur changement suffit
local function refresh_keycard_level()
    local swep = weapons.GetStored( "weapon_scp131" )
    if not swep then return end

    swep.GuthSCPLVL = config131.keycard_level or 0
end

hook.Add( "guthscp.config:applied", "scp131:keycard_level", function( id )
    if id ~= "scp131" then return end

    refresh_keycard_level()
end )

timer.Simple( 0, refresh_keycard_level )

--  sans envoi explicite, les clients n'ont aucun des sons configures
for _, sounds in ipairs( { config131.chirp_sounds, config131.distress_sounds, config131.crash_sounds } ) do
    for _, path in ipairs( sounds or {} ) do
        if not isstring( path ) or path == "" then continue end
        if not file.Exists( "sound/" .. path, "GAME" ) then continue end

        resource.AddFile( "sound/" .. path )
    end
end
