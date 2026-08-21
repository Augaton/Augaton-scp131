local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

--  etre SCP-131, c'est porter l'arme : meme convention que le module 173
scp131.filter = guthscp.players_filter:new( "weapon_scp131" )

--  perte de vitesse a partir de laquelle on considere que la roue a percute un mur
local CRASH_SPEED_RATIO = 0.45
--  en dessous, la roue est consideree a l'arret
local WHEEL_MIN_SPEED = 5
--  hauteur du rayon cherchant un mur a grimper, depuis les pieds
local CLIMB_TRACE_HEIGHT = 20
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

--  etourdi : ni roulade, ni escalade, ni contact visuel sur le 173
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


if SERVER then
    --=====================================================================
    --  Cycle de vie du role
    --=====================================================================

    function scp131.apply_speeds( ply )
        ply:SetWalkSpeed( config131.walk_speed )
        ply:SetRunSpeed( config131.run_speed )
    end

    function scp131.apply_color( ply )
        local color = scp131.get_variant( ply ) == "B" and config131.color_b or config131.color_a

        ply:SetColor( color )
        ply:SetPlayerColor( Vector( color.r / 255, color.g / 255, color.b / 255 ) )
    end

    --  le premier pod devient A, le second B
    function scp131.assign_variant( ply )
        local taken = {}

        for _, other in ipairs( scp131.get_scps_131() ) do
            if other == ply or not IsValid( other ) then continue end

            taken[scp131.get_variant( other )] = true
        end

        ply:SetNW2String( "scp131:variant", taken["A"] and not taken["B"] and "B" or "A" )
        scp131.apply_color( ply )
    end

    function scp131.set_companion( pod, companion )
        if not IsValid( pod ) then return end

        local previous = scp131.get_companion( pod )
        if previous == companion then return end

        pod:SetNW2Entity( "scp131:companion", companion or NULL )
        pod.scp131_last_attention = CurTime()

        hook.Run( "scp131:companion_changed", pod, companion, previous )
    end

    --[[
        Renverse le pod : il part en roulade et perd tout contact visuel.

        C'est la seule prise que les autres ont sur lui, puisqu'il ne peut pas
        mourir : sans ca, un 131 pose dans un couloir fige le 173 indefiniment.
    ]]
    function scp131.tumble( ply, force, duration, sounds )
        if not IsValid( ply ) then return end

        local time = CurTime()

        ply:SetNW2Float( "scp131:stunned_from", time )
        ply:SetNW2Float( "scp131:stunned_until", time + duration )
        ply.scp131_wheel_speed = 0
        ply.scp131_wheel_commanded = 0
        ply.scp131_climb_time = 0

        if force then
            ply:SetVelocity( force )
        end

        --  le contact avec le 173 doit tomber immediatement, sans attendre le prochain tick de garde
        ply:SetNW2Entity( "scp131:watched_173", NULL )

        if sounds and #sounds > 0 then
            guthscp.sound.play( ply, sounds, config131.sound_hear_distance, false, config131.sound_volume )
        end
    end

    scp131.filter.event_added:add_listener( "scp131:setup", function( ply )
        --  on garde les vitesses du metier pour pouvoir les rendre en sortant du role
        ply.scp131_previous_speeds = { walk = ply:GetWalkSpeed(), run = ply:GetRunSpeed() }
        ply.scp131_wheel_speed = 0
        ply.scp131_wheel_commanded = 0
        ply.scp131_climb_time = 0

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
        ply:SetColor( color_white )
        ply:SetPlayerColor( Vector( 1, 1, 1 ) )
    end )
end


--=========================================================================
--  Deplacement : la roue et l'escalade
--=========================================================================

local function trace_climbable_wall( ply, forward )
    local start = ply:GetPos() + Vector( 0, 0, CLIMB_TRACE_HEIGHT )

    return util.TraceHull( {
        start = start,
        endpos = start + forward * config131.climb_reach,
        mins = Vector( -6, -6, -6 ),
        maxs = Vector( 6, 6, 6 ),
        filter = ply,
        mask = MASK_PLAYERSOLID,
    } )
end

hook.Add( "SetupMove", "scp131:movement", function( ply, mv, cmd )
    if not scp131.is_scp_131( ply ) then return end

    --  noclip du staff, echelles, nage : on laisse le moteur faire son travail
    if ply:GetMoveType() ~= MOVETYPE_WALK then return end
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

    --  escalade des surfaces verticales : maintenir le saut face a un mur
    if config131.climb_enabled and not stunned and mv:KeyDown( IN_JUMP ) then
        local climb_time = ply.scp131_climb_time or 0
        local out_of_breath = config131.climb_max_time > 0 and climb_time >= config131.climb_max_time

        if not out_of_breath then
            local forward = move_angles:Forward()
            forward.z = 0
            forward:Normalize()

            local trace = trace_climbable_wall( ply, forward )

            --  une paroi, pas une pente : la normale doit etre quasi horizontale
            if trace.Hit and math.abs( trace.HitNormal.z ) < 0.3 then
                ply.scp131_climb_time = climb_time + delta
                ply.scp131_wheel_speed = 0
                ply.scp131_wheel_commanded = 0

                mv:SetVelocity( Vector(
                    -trace.HitNormal.x * CLIMB_STICK_SPEED,
                    -trace.HitNormal.y * CLIMB_STICK_SPEED,
                    config131.climb_speed
                ) )

                --  le saut du moteur viendrait contrarier la montee
                mv:SetButtons( bit.band( mv:GetButtons(), bit.bnot( IN_JUMP ) ) )
                mv:SetForwardSpeed( 0 )
                mv:SetSideSpeed( 0 )
                return
            end
        end
    end

    if not config131.wheel_enabled then
        if stunned then
            mv:SetForwardSpeed( 0 )
            mv:SetSideSpeed( 0 )
        end

        return
    end

    local velocity = mv:GetVelocity()
    local speed = ply.scp131_wheel_speed or 0
    local direction = ply.scp131_wheel_dir

    if not direction or direction:IsZero() then
        direction = move_angles:Forward()
        direction.z = 0
        direction:Normalize()
    end

    --  percuter un mur : la vitesse reelle s'effondre alors qu'on commandait une roulade rapide
    if SERVER and config131.crash_enabled and not stunned and ply:Alive() then
        local commanded = ply.scp131_wheel_commanded or 0

        if commanded >= config131.crash_min_speed and velocity:Length2D() < commanded * CRASH_SPEED_RATIO then
            local sounds = #config131.crash_sounds > 0 and config131.crash_sounds
                or ( #config131.distress_sounds > 0 and config131.distress_sounds or nil )

            --  le rebond passe par le CMoveData : une vitesse posee sur le joueur pendant
            --  SetupMove serait ecrasee par le deplacement du tick en cours
            scp131.tumble( ply, nil, config131.crash_stun_time, sounds )
            mv:SetVelocity( -direction * commanded * 0.35 + Vector( 0, 0, 80 ) )

            stunned = true
        end
    end

    --  etourdi : on lache le pilotage, le pod part sur son erre et le moteur le freine
    if stunned then
        ply.scp131_wheel_speed = 0
        ply.scp131_wheel_commanded = 0

        mv:SetForwardSpeed( 0 )
        mv:SetSideSpeed( 0 )
        mv:SetButtons( bit.band( mv:GetButtons(), bit.bnot( IN_JUMP ) ) )
        return
    end

    --  direction voulue par le joueur
    local wish = Vector( 0, 0, 0 )
    local forward_speed, side_speed = mv:GetForwardSpeed(), mv:GetSideSpeed()

    if forward_speed ~= 0 or side_speed ~= 0 then
        wish = move_angles:Forward() * forward_speed + move_angles:Right() * side_speed
        wish.z = 0

        if wish:IsZero() then
            wish = Vector( 0, 0, 0 )
        else
            wish:Normalize()
        end
    end

    local max_speed = config131.wheel_max_speed
    if scp131.is_swarming( ply ) then
        max_speed = max_speed * ( 1 + config131.swarm_speed_bonus / 100 )
    end

    if wish:IsZero() then
        --  pas de systeme de freinage : la roue continue sur son erre
        speed = math.max( 0, speed - config131.wheel_coast_deceleration * delta )

        if speed < WHEEL_MIN_SPEED then
            speed = 0
        end
    else
        speed = math.min( max_speed, speed + config131.wheel_acceleration * delta )

        --  plus la roue va vite, moins elle accroche : elle vire large
        local grip = Lerp( speed / max_speed, 1, config131.wheel_grip_min )
        local turn = math.Clamp( config131.wheel_turn_rate * grip * delta, 0, 1 )

        direction = LerpVector( turn, direction, wish )
        direction.z = 0

        if direction:IsZero() then
            direction = wish
        else
            direction:Normalize()
        end
    end

    ply.scp131_wheel_speed = speed
    ply.scp131_wheel_dir = direction
    ply.scp131_wheel_commanded = on_ground and speed or 0

    if on_ground then
        mv:SetVelocity( Vector( direction.x * speed, direction.y * speed, velocity.z ) )
    end

    --  le moteur ne doit ni accelerer ni freiner a notre place
    mv:SetForwardSpeed( 0 )
    mv:SetSideSpeed( 0 )
end )
