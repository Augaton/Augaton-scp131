--[[
    SCP-131 : les Eye Pods.

    Deux principes tiennent ce fichier :

    - Le deplacement est SANS ETAT. La vitesse de la roue n'est stockee nulle part,
      elle EST la velocite du joueur : SetupMove la lit, la corrige et la repose.
      Tout champ Lua accumule dans SetupMove (vitesse, direction) derape a la
      re-prediction du client, qui rejoue plusieurs fois le meme tick sans
      restaurer les tables Lua ; la velocite, elle, fait partie de l'etat predit.
      Pour que la velocite survive d'un tick a l'autre, la friction moteur du
      joueur est mise a zero : l'erre et le freinage sont entierement a nous.

    - Le corps est celui d'une creature de 30 cm. Hull, hauteur de vue et friction
      ne sont PAS repliques par le moteur : ils sont poses dans les deux realms
      (evenements du filtre, qui se synchronise aussi cote client), sinon le client
      predit avec un corps humain et le serveur corrige a chaque tick.
]]

local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

--  etre SCP-131, c'est porter l'arme : meme convention que le module 173
scp131.filter = guthscp.players_filter:new( "weapon_scp131" )

--  perte de vitesse a partir de laquelle on considere que la roue a percute un mur
local CRASH_SPEED_RATIO = 0.45
--  en dessous, la roue est consideree a l'arret
local WHEEL_MIN_SPEED = 5
--  pousser a contresens au-dela de cet angle freine au lieu de tourner
local BRAKE_DOT = -0.3
--  un pod sonne perd son erre plus vite qu'une roue qui roule droit
local STUN_DRAG = 3
--  vitesse a laquelle le pod se colle au mur pendant l'escalade
local CLIMB_STICK_SPEED = 30

if SERVER then
    scp131.filter:listen_disconnect()
    scp131.filter:listen_weapon_users( "weapon_scp131" )
end


--=========================================================================
--  Etat d'un SCP-131
--=========================================================================

function scp131.get_scps_131()
    return scp131.filter:get_entities()
end

function scp131.is_scp_131( ply )
    if CLIENT and ply == nil then ply = LocalPlayer() end

    return scp131.filter:is_in( ply )
end

--  "A" (orange brule) ou "B" (jaune moutarde)
function scp131.get_variant( ply )
    if not IsValid( ply ) then return "A" end

    return ply:GetNW2String( "scp131:variant", "A" )
end

function scp131.get_name( ply )
    return "SCP-131-" .. scp131.get_variant( ply )
end

--  etourdi : ni pilotage, ni escalade, ni contact visuel sur le 173
function scp131.is_stunned( ply )
    if not IsValid( ply ) then return false end

    return ply:GetNW2Float( "scp131:stunned_until", 0 ) > CurTime()
end

--  les deux pods se donnent du courage quand ils roulent ensemble
function scp131.is_swarming( ply )
    local distance = config131.swarm_distance
    if distance <= 0 then return false end

    --  appele a chaque tick par le deplacement : le cas courant (un seul pod) sort tout de suite
    local pods = scp131.get_scps_131()
    if #pods < 2 then return false end

    local origin, distance_sqr = ply:GetPos(), distance * distance

    for _, other in ipairs( pods ) do
        if other == ply or not IsValid( other ) then continue end
        if origin:DistToSqr( other:GetPos() ) <= distance_sqr then return true end
    end

    return false
end

--  vitesse de roulement actuelle, lue sur la velocite (voir le bandeau)
function scp131.get_wheel_speed( ply )
    if not IsValid( ply ) then return 0 end

    return ply:GetVelocity():Length2D()
end

--  plafond de vitesse du moment, sprint et essaim compris
function scp131.get_max_speed( ply, sprinting )
    local max_speed = config131.wheel_max_speed

    if not sprinting then
        max_speed = max_speed * config131.wheel_cruise_ratio
    end

    if scp131.is_swarming( ply ) then
        max_speed = max_speed * ( 1 + config131.swarm_speed_bonus / 100 )
    end

    return max_speed
end

--  le 173 fige actuellement par ce pod
function scp131.get_watched_173( ply )
    if not IsValid( ply ) then return end

    local ent = ply:GetNW2Entity( "scp131:watched_173", NULL )
    return IsValid( ent ) and ent or nil
end

--  le pod qui fige actuellement ce 173
function scp131.get_watcher( scp )
    if not IsValid( scp ) then return end

    local ent = scp:GetNW2Entity( "scp131:watcher", NULL )
    return IsValid( ent ) and ent or nil
end


--=========================================================================
--  Lien avec un joueur
--=========================================================================

--  le joueur suivi par ce pod
function scp131.get_companion( ply )
    if not IsValid( ply ) then return end

    local ent = ply:GetNW2Entity( "scp131:companion", NULL )
    return IsValid( ent ) and ent or nil
end

--  les pods lies a ce joueur (deux au maximum, une boucle suffit)
function scp131.get_pods( ply )
    local pods = {}
    if not IsValid( ply ) then return pods end

    for _, pod in ipairs( scp131.get_scps_131() ) do
        if not IsValid( pod ) then continue end
        if scp131.get_companion( pod ) ~= ply then continue end

        pods[#pods + 1] = pod
    end

    return pods
end

--  regard porte sur une entite : le module 173 sait deja le faire, on ne le refait pas
function scp131.is_looking_at( ply, ent )
    if not IsValid( ply ) or not IsValid( ent ) then return false end

    local guthscp173 = guthscp.modules.guthscp173
    if guthscp173 and guthscp173.is_looking_at then
        return guthscp173.is_looking_at( ply, ent )
    end

    --  repli si le module 173 venait a disparaitre : simple test de champ de vision
    local dot = ply:GetAimVector():Dot( ( ent:GetPos() - ply:GetPos() ):GetNormal() )
    return dot > 0.7 and ply:IsLineOfSightClear( ent:GetPos() )
end


--=========================================================================
--  Corps : hull, vue et friction, dans les deux realms
--=========================================================================

--[[
    Le moteur ne replique ni le hull ni la friction : cette fonction tourne sur
    le serveur ET sur chaque client (le filtre guthscp se synchronise et declenche
    ses evenements des deux cotes). Les valeurs d'origine sont gardees sur le
    joueur pour etre rendues telles quelles a la sortie du role, quel que soit
    l'addon qui les avait posees.
]]
--  cotes voulues, avec replis : cote client, le filtre peut se synchroniser avant la config
local function get_body_size()
    local radius = config131.hull_radius or 10
    local height = config131.hull_height or 22
    local view = math.min( config131.view_height or 16, height - 2 )

    return radius, height, view
end

function scp131.apply_body( ply )
    if not IsValid( ply ) then return end

    local radius, height, view = get_body_size()

    if not ply.scp131_body_backup then
        local hull_mins, hull_maxs = ply:GetHull()
        local duck_mins, duck_maxs = ply:GetHullDuck()

        --  si le corps est deja le notre (rechargement a chaud), on garde les cotes standard du joueur
        if hull_maxs.z == height then
            hull_mins, hull_maxs = Vector( -16, -16, 0 ), Vector( 16, 16, 72 )
            duck_mins, duck_maxs = Vector( -16, -16, 0 ), Vector( 16, 16, 36 )
        end

        ply.scp131_body_backup = {
            hull_mins = hull_mins,
            hull_maxs = hull_maxs,
            duck_mins = duck_mins,
            duck_maxs = duck_maxs,
            view = hull_maxs.z == 72 and Vector( 0, 0, 64 ) or ply:GetViewOffset(),
            view_ducked = hull_maxs.z == 72 and Vector( 0, 0, 28 ) or ply:GetViewOffsetDucked(),
            friction = 1,
        }
    end

    local mins, maxs = Vector( -radius, -radius, 0 ), Vector( radius, radius, height )

    --  pas d'accroupissement : un pod n'a rien a plier
    ply:SetHull( mins, maxs )
    ply:SetHullDuck( mins, maxs )

    local offset = Vector( 0, 0, view )
    ply:SetViewOffset( offset )
    ply:SetViewOffsetDucked( offset )
end

--[[
    Verifie le corps a chaque tick de deplacement.

    Le poser une fois ne suffit pas : la classe joueur remet hull et vue humains
    a chaque spawn (dont le respawn d'un changement de metier, ou le filtre ne
    relance pas son evenement puisque le joueur y est deja), et la synchro du
    filtre cote client peut arriver apres la config. Le moteur recopie la vue
    "debout" dans la vue courante a chaque tick : si un realm a 64 et l'autre
    16, la camera saute de l'un a l'autre a chaque correction de prediction.
    Deux lectures par tick, pas plus : on n'ecrit que sur difference.
]]
function scp131.enforce_body( ply )
    local radius, height, view = get_body_size()
    local _, maxs = ply:GetHull()

    if maxs.z ~= height or maxs.x ~= radius or ply:GetViewOffset().z ~= view then
        scp131.apply_body( ply )
    end
end

function scp131.restore_body( ply )
    if not IsValid( ply ) then return end

    local backup = ply.scp131_body_backup
    if not backup then return end

    ply.scp131_body_backup = nil

    ply:SetHull( backup.hull_mins, backup.hull_maxs )
    ply:SetHullDuck( backup.duck_mins, backup.duck_maxs )
    ply:SetViewOffset( backup.view )
    ply:SetViewOffsetDucked( backup.view_ducked )
    ply:SetFriction( backup.friction )
end

scp131.filter.event_added:add_listener( "scp131:body", scp131.apply_body )
scp131.filter.event_removed:add_listener( "scp131:body", scp131.restore_body )

--  la config arrive (ou change) dans les deux realms : les pods en jeu prennent les cotes sans repasser par le metier
hook.Add( "guthscp.config:applied", "scp131:body", function( id )
    if id ~= "scp131" then return end

    for _, pod in ipairs( scp131.get_scps_131() ) do
        scp131.apply_body( pod )
    end
end )


if SERVER then
    --=====================================================================
    --  Cycle de vie du role
    --=====================================================================

    function scp131.apply_speeds( ply )
        ply:SetWalkSpeed( config131.walk_speed )
        ply:SetRunSpeed( config131.run_speed )
    end

    --  le modele porte ses deux robes : skin 1 orange (A), skin 0 jaune (B).
    --  Une teinte SetColor salirait l'oeil et le pneu, on n'y touche pas.
    function scp131.apply_skin( ply )
        ply:SetSkin( scp131.get_variant( ply ) == "B" and 0 or 1 )
    end

    --  le premier pod devient A, le second B
    function scp131.assign_variant( ply )
        local taken = {}

        for _, other in ipairs( scp131.get_scps_131() ) do
            if other == ply or not IsValid( other ) then continue end

            taken[scp131.get_variant( other )] = true
        end

        ply:SetNW2String( "scp131:variant", taken["A"] and not taken["B"] and "B" or "A" )
        scp131.apply_skin( ply )
    end

    function scp131.set_companion( pod, companion )
        if not IsValid( pod ) then return end

        local previous = scp131.get_companion( pod )
        if previous == companion then return end

        pod:SetNW2Entity( "scp131:companion", companion or NULL )
        pod.scp131_last_attention = CurTime()

        hook.Run( "scp131:companion_changed", pod, companion, previous )
    end

    --  sons ponctuels : EmitSound suffit et lit aussi bien les fichiers de base que les fichiers custom
    function scp131.play_sound( ply, sounds )
        if not IsValid( ply ) then return end
        if not istable( sounds ) or #sounds == 0 then return end

        local path = sounds[math.random( #sounds )]
        if not isstring( path ) or path == "" then return end

        ply:EmitSound( path, config131.sound_level, math.random( 95, 110 ), config131.sound_volume, CHAN_VOICE )
    end

    --  chaque famille de sons se replie sur la precedente quand elle est vide
    function scp131.get_sounds( kind )
        if kind == "crash" and #config131.crash_sounds > 0 then return config131.crash_sounds end
        if kind ~= "chirp" and #config131.distress_sounds > 0 then return config131.distress_sounds end

        return config131.chirp_sounds
    end

    --[[
        Renverse le pod : il part en roulade et perd tout contact visuel.

        C'est la seule prise que les autres ont sur lui, puisqu'il ne peut pas
        mourir : sans ca, un 131 pose dans un couloir fige le 173 indefiniment.
        La force est ajoutee a la velocite (c'est ce que fait SetVelocity sur un
        joueur) et coule ensuite sur l'erre de la roue.
    ]]
    function scp131.tumble( ply, force, duration, kind )
        if not IsValid( ply ) then return end

        local time = CurTime()

        ply:SetNW2Float( "scp131:stunned_from", time )
        ply:SetNW2Float( "scp131:stunned_until", time + duration )

        if force then
            ply:SetVelocity( force )
        end

        --  le contact avec le 173 doit tomber immediatement, sans attendre le prochain tick de garde
        ply:SetNW2Entity( "scp131:watched_173", NULL )

        scp131.play_sound( ply, scp131.get_sounds( kind or "distress" ) )
    end

    scp131.filter.event_added:add_listener( "scp131:setup", function( ply )
        --  on garde les vitesses du metier pour pouvoir les rendre en sortant du role
        ply.scp131_previous_speeds = { walk = ply:GetWalkSpeed(), run = ply:GetRunSpeed() }
        ply.scp131_last_speed = 0

        scp131.apply_speeds( ply )
        scp131.assign_variant( ply )
    end )

    scp131.filter.event_removed:add_listener( "scp131:cleanup", function( ply )
        if not IsValid( ply ) then return end

        local previous = ply.scp131_previous_speeds
        if previous then
            ply:SetWalkSpeed( previous.walk )
            ply:SetRunSpeed( previous.run )
            ply.scp131_previous_speeds = nil
        end

        scp131.set_companion( ply, nil )

        ply:SetNW2String( "scp131:variant", "A" )
        ply:SetNW2Float( "scp131:stunned_until", 0 )
        ply:SetNW2Entity( "scp131:watched_173", NULL )
        ply:SetSkin( 0 )
    end )
end


--=========================================================================
--  Deplacement : la roue et l'escalade
--=========================================================================

local function trace_wall( ply, forward, height )
    local start = ply:GetPos() + Vector( 0, 0, height )

    return util.TraceHull( {
        start = start,
        endpos = start + forward * config131.climb_reach,
        mins = Vector( -4, -4, -2 ),
        maxs = Vector( 4, 4, 2 ),
        filter = ply,
        mask = MASK_PLAYERSOLID,
    } )
end

local function strip_buttons( mv, buttons )
    mv:SetButtons( bit.band( mv:GetButtons(), bit.bnot( buttons ) ) )
end

--[[
    Escalade : saut maintenu face a une paroi.

    Deux rayons, l'un au sommet du corps, l'autre aux pieds. Tant que le sommet
    touche le mur, le pod monte en s'y collant. Quand seul le bas touche encore,
    le corps depasse le rebord : on le bascule par-dessus au lieu de le laisser
    retomber, c'est ce qui rendait l'ancienne escalade penible en haut des murs.
    Le compteur de souffle est un champ Lua, il n'avance qu'au premier passage
    du tick pour ne pas doubler a la re-prediction ; une petite derive y est
    sans consequence, il ne borne qu'une duree.
]]
local function try_climb( ply, mv, move_angles, delta )
    local climb_time = ply.scp131_climb_time or 0
    if config131.climb_max_time > 0 and climb_time >= config131.climb_max_time then return false end

    local forward = move_angles:Forward()
    forward.z = 0
    if forward:IsZero() then return false end
    forward:Normalize()

    local _, maxs = ply:GetHull()
    local high = trace_wall( ply, forward, maxs.z - 3 )
    local low = trace_wall( ply, forward, 4 )
    local wall = high.Hit and high or ( low.Hit and low or nil )

    --  une paroi, pas une pente : le moteur monte les pentes tout seul
    if not wall or math.abs( wall.HitNormal.z ) >= 0.3 then return false end

    if IsFirstTimePredicted() then
        ply.scp131_climb_time = climb_time + delta
    end

    if high.Hit then
        mv:SetVelocity( Vector(
            -high.HitNormal.x * CLIMB_STICK_SPEED,
            -high.HitNormal.y * CLIMB_STICK_SPEED,
            config131.climb_speed
        ) )
    else
        mv:SetVelocity( forward * config131.climb_speed + Vector( 0, 0, config131.climb_speed ) )
    end

    --  le saut du moteur viendrait contrarier la montee
    strip_buttons( mv, IN_JUMP )
    mv:SetForwardSpeed( 0 )
    mv:SetSideSpeed( 0 )

    return true
end

hook.Add( "SetupMove", "scp131:movement", function( ply, mv, cmd )
    if not scp131.is_scp_131( ply ) then return end

    scp131.enforce_body( ply )

    --  noclip du staff, echelles, nage : on laisse le moteur faire son travail
    if ply:GetMoveType() ~= MOVETYPE_WALK then return end

    --  un pod ne s'accroupit pas
    strip_buttons( mv, IN_DUCK )

    if ply:WaterLevel() >= 2 then return end

    --  SetupMove tourne une fois par tick sur les deux realms : le pas de temps doit
    --  etre identique de chaque cote, sinon la prediction du client derape
    local delta = engine.TickInterval()
    local stunned = scp131.is_stunned( ply )
    local move_angles = mv:GetMoveAngles()
    local on_ground = ply:OnGround()

    if on_ground then
        ply.scp131_climb_time = 0
    end

    if config131.climb_enabled and not stunned and mv:KeyDown( IN_JUMP )
        and try_climb( ply, mv, move_angles, delta ) then
        return
    end

    if not config131.wheel_enabled then
        if ply:GetFriction() ~= 1 then ply:SetFriction( 1 ) end

        if stunned then
            mv:SetForwardSpeed( 0 )
            mv:SetSideSpeed( 0 )
            strip_buttons( mv, IN_JUMP )
        end

        return
    end

    --  la friction du moteur mangerait 12 % de la velocite a chaque tick : l'erre est a nous
    if ply:GetFriction() ~= 0 then ply:SetFriction( 0 ) end

    local velocity = mv:GetVelocity()
    local flat = Vector( velocity.x, velocity.y, 0 )
    local speed = flat:Length()
    local direction = speed > WHEEL_MIN_SPEED and flat / speed or nil

    --  percuter un mur : la vitesse reelle s'effondre par rapport a celle posee au tick precedent.
    --  Decide par le serveur seul : l'etourdissement est un etat reseau, pas une prediction.
    if SERVER and config131.crash_enabled and not stunned and on_ground then
        local last_speed = ply.scp131_last_speed or 0

        if last_speed >= config131.crash_min_speed and speed < last_speed * CRASH_SPEED_RATIO then
            scp131.tumble( ply, nil, config131.crash_stun_time, "crash" )

            --  le rebond passe par le CMoveData : une vitesse posee sur le joueur pendant
            --  SetupMove serait ecrasee par le deplacement du tick en cours
            local last_direction = ply.scp131_last_direction or -move_angles:Forward()
            mv:SetVelocity( -last_direction * last_speed * 0.3 + Vector( 0, 0, 90 ) )

            stunned = true
        end
    end

    --  etourdi : on lache le pilotage, le pod part sur son erre et s'y epuise
    if stunned then
        if on_ground then
            speed = math.max( 0, speed - config131.wheel_coast_deceleration * STUN_DRAG * delta )

            if direction and speed >= WHEEL_MIN_SPEED then
                mv:SetVelocity( Vector( direction.x * speed, direction.y * speed, velocity.z ) )
            else
                mv:SetVelocity( Vector( 0, 0, velocity.z ) )
            end
        end

        mv:SetForwardSpeed( 0 )
        mv:SetSideSpeed( 0 )
        strip_buttons( mv, IN_JUMP )

        if SERVER then
            ply.scp131_last_speed = 0
        end

        return
    end

    --  direction voulue par le joueur
    local wish
    local forward_speed, side_speed = mv:GetForwardSpeed(), mv:GetSideSpeed()

    if forward_speed ~= 0 or side_speed ~= 0 then
        wish = move_angles:Forward() * forward_speed + move_angles:Right() * side_speed
        wish.z = 0

        if wish:IsZero() then
            wish = nil
        else
            wish:Normalize()
        end
    end

    --  en l'air, la roue ne mord sur rien : on garde l'elan tel quel
    if on_ground then
        local max_speed = scp131.get_max_speed( ply, mv:KeyDown( IN_SPEED ) )

        if not wish then
            --  pas de systeme de freinage : la roue continue sur son erre
            speed = math.max( 0, speed - config131.wheel_coast_deceleration * delta )
        elseif direction and direction:Dot( wish ) < BRAKE_DOT then
            --  pousser a contresens, c'est freiner : la direction ne change pas, la vitesse tombe
            speed = math.max( 0, speed - config131.wheel_brake_deceleration * delta )
        else
            direction = direction or wish

            --  plus la roue va vite, moins elle accroche : elle vire large
            local grip = Lerp( math.min( speed / max_speed, 1 ), 1, config131.wheel_grip_min )
            local turn = math.Clamp( config131.wheel_turn_rate * grip * delta, 0, 1 )

            direction = LerpVector( turn, direction, wish )
            direction.z = 0

            if direction:IsZero() then
                direction = wish
            else
                direction:Normalize()
            end

            if speed <= max_speed then
                speed = math.min( max_speed, speed + config131.wheel_acceleration * delta )
            else
                --  au-dessus du plafond (sprint relache, bourrade) : on redescend en douceur
                speed = math.max( max_speed, speed - config131.wheel_brake_deceleration * delta )
            end
        end

        if speed < WHEEL_MIN_SPEED then
            speed = 0
        end

        if direction and speed > 0 then
            mv:SetVelocity( Vector( direction.x * speed, direction.y * speed, velocity.z ) )
        else
            mv:SetVelocity( Vector( 0, 0, velocity.z ) )
        end
    end

    if SERVER then
        ply.scp131_last_speed = on_ground and speed or 0
        ply.scp131_last_direction = direction
    end

    --  le moteur ne doit ni accelerer ni freiner a notre place
    mv:SetForwardSpeed( 0 )
    mv:SetSideSpeed( 0 )
end )
