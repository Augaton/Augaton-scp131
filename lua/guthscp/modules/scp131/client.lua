--[[
    HUD et camera du SCP-131.

    Rien ici ne decide : tout se lit dans les variables reseau posees par le
    serveur et dans la velocite predite. La camera n'est plus enfoncee de force
    dans le sol : la hauteur de vue est celle du corps (shared.lua), la vue ne
    fait qu'ajouter l'inclinaison dans les virages et la vrille de l'etourdissement.
    Ces mouvements de camera passent sous scprp_reduce_flashes quand le serveur
    le propose (warning_menu) : amplitude reduite, jamais supprimee.
]]

local scp131 = guthscp.modules.scp131
local config131 = guthscp.configs.scp131

surface.CreateFont( "scp131:hud", {
    font = "Tahoma",
    size = 20,
    weight = 700,
    antialias = true,
} )

surface.CreateFont( "scp131:hud_small", {
    font = "Tahoma",
    size = 16,
    weight = 500,
    antialias = true,
} )

local color_shadow = Color( 0, 0, 0, 220 )
local color_text = Color( 235, 235, 235 )
local color_dim = Color( 190, 190, 190 )
local color_alert = Color( 220, 70, 60 )
local color_hold = Color( 120, 220, 130 )
local color_bar_back = Color( 0, 0, 0, 160 )

--  duree d'affichage du rappel des commandes a la prise du role
local HINT_TIME = 14
--  unites hammer -> km/h (1 unite = 1.905 cm)
local UNITS_TO_KMH = 0.01905 * 3.6

--  resolu a l'appel : l'ordre de chargement ne garantit pas que warning_menu soit passe
local reduce_cvar

local function reduce_motion()
    reduce_cvar = reduce_cvar or GetConVar( "scprp_reduce_flashes" )
    return reduce_cvar ~= nil and reduce_cvar:GetBool()
end

--  etat du lien en cours, pousse par le serveur uniquement au proprietaire
local bond_target, bond_progress, bond_expiry = NULL, 0, 0

net.Receive( "scp131:bond_channel", function()
    bond_target = net.ReadEntity()
    bond_progress = net.ReadUInt( 7 ) / 100

    --  filet de securite : si un message de fin se perd, la barre s'efface d'elle-meme
    bond_expiry = CurTime() + 1
end )

--  la liste des pods se lit dans un hook de rendu : on la rafraichit a la cadence de l'affichage
local POD_CACHE_RATE = 0.25
local next_pod_cache, cached_pods = 0, {}

local function get_cached_pods( ply )
    if CurTime() >= next_pod_cache then
        next_pod_cache = CurTime() + POD_CACHE_RATE
        cached_pods = scp131.get_pods( ply )
    end

    return cached_pods
end

local function variant_color( ply )
    return scp131.get_variant( ply ) == "B" and config131.color_b or config131.color_a
end

local function draw_text( text, font, x, y, color, align_x, align_y )
    draw.SimpleTextOutlined( text, font, x, y, color, align_x, align_y, 1, color_shadow )
end

local function draw_bar( x, y, width, height, ratio, color )
    surface.SetDrawColor( color_bar_back )
    surface.DrawRect( x - 1, y - 1, width + 2, height + 2 )
    surface.SetDrawColor( color )
    surface.DrawRect( x, y, width * math.Clamp( ratio, 0, 1 ), height )
end

--  fleche pointant vers une position hors champ, posee sur un cercle au centre de l'ecran
local function draw_offscreen_arrow( position, color )
    local center_x, center_y = ScrW() * 0.5, ScrH() * 0.5
    local screen = position:ToScreen()

    if screen.visible and screen.x >= 0 and screen.x <= ScrW() and screen.y >= 0 and screen.y <= ScrH() then
        return screen.x, screen.y, true
    end

    local angle = math.atan2( screen.y - center_y, screen.x - center_x )

    --  ToScreen renvoie une position miroir quand la cible est derriere le joueur
    if not screen.visible then
        angle = angle + math.pi
    end

    local radius = math.min( ScrW(), ScrH() ) * 0.22
    local x, y = center_x + math.cos( angle ) * radius, center_y + math.sin( angle ) * radius
    local size = 12

    local vertices = {}
    for index, offset in ipairs( { 0, 2.4, -2.4 } ) do
        vertices[index] = {
            x = x + math.cos( angle + offset ) * size,
            y = y + math.sin( angle + offset ) * size,
        }
    end

    draw.NoTexture()
    surface.SetDrawColor( color )
    surface.DrawPoly( vertices )

    return x, y, false
end


--=========================================================================
--  Interface du SCP-131
--=========================================================================

--  moment de la prise du role, pour n'afficher le rappel des commandes qu'au debut
local became_pod_at

local function draw_hint( center_x, y )
    if not became_pod_at or CurTime() - became_pod_at > HINT_TIME then return end

    local lines = {}

    if config131.wheel_enabled then
        lines[#lines + 1] = "Sprint : pleine vitesse  |  Reculer : freiner  |  Pas de frein a l'arret des touches"
    end

    if config131.climb_enabled then
        lines[#lines + 1] = "Saut maintenu face a un mur : grimper"
    end

    lines[#lines + 1] = "Clic gauche : gazouiller  |  Clic droit maintenu sur un joueur : s'attacher ou se detacher"

    for index, line in ipairs( lines ) do
        draw_text( line, "scp131:hud_small", center_x, y + ( index - 1 ) * 18, color_dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end
end

local function draw_speedometer( ply, center_x, y, color )
    if not config131.wheel_enabled then return end

    local speed = scp131.get_wheel_speed( ply )
    local ratio = speed / math.max( scp131.get_max_speed( ply, true ), 1 )
    local width, height = 180, 5

    draw_bar( center_x - width * 0.5, y, width, height, ratio, color )
    draw_text(
        math.floor( speed * UNITS_TO_KMH ) .. " km/h",
        "scp131:hud_small", center_x, y - 12, color_dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
    )
end

--  souffle restant pendant l'escalade
local function draw_climb( ply, center_x, y, color )
    if not config131.climb_enabled or config131.climb_max_time <= 0 then return end
    if ply:OnGround() then return end

    local climb_time = ply.scp131_climb_time or 0
    if climb_time <= 0 then return end

    local width, height = 120, 4
    draw_bar( center_x - width * 0.5, y, width, height, 1 - climb_time / config131.climb_max_time, color )
    draw_text( "PRISE", "scp131:hud_small", center_x, y - 11, color_dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
end

local function draw_pod_hud( ply )
    local color = variant_color( ply )
    local center_x = ScrW() * 0.5

    draw_text( scp131.get_name( ply ), "scp131:hud", center_x, ScrH() * 0.9, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    draw_speedometer( ply, center_x, ScrH() * 0.925, color )
    draw_climb( ply, center_x, ScrH() * 0.56, color )
    draw_hint( center_x, ScrH() * 0.8 )

    if scp131.is_stunned( ply ) then
        draw_text( "SONNE", "scp131:hud", center_x, ScrH() * 0.66, color_alert, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end

    --  contact visuel sur le 173
    if scp131.get_watched_173( ply ) then
        draw_text(
            "SCP-173 TENU DU REGARD",
            "scp131:hud", center_x, ScrH() * 0.7, color_hold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end

    --  compagnon : direction et distance, pour pouvoir le suivre sans le perdre
    local companion = scp131.get_companion( ply )
    if IsValid( companion ) then
        local x, y, on_screen = draw_offscreen_arrow( companion:EyePos(), color )
        local distance = math.floor( ply:GetPos():Distance( companion:GetPos() ) * 0.01905 )

        draw_text(
            companion:Nick() .. "  " .. distance .. " m",
            "scp131:hud_small", x, y - ( on_screen and 24 or 22 ), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end

    --  progression du lien en cours
    local target = bond_target
    if not IsValid( target ) or CurTime() > bond_expiry then return end

    local width, height = 260, 10
    local y = ScrH() * 0.62

    draw_bar( center_x - width * 0.5, y, width, height, bond_progress, color )

    local is_breaking = scp131.get_companion( ply ) == target

    draw_text(
        ( is_breaking and "Se detacher de " or "S'attacher a " ) .. target:Nick(),
        "scp131:hud_small", center_x, y - 14, color_text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
    )
end


--=========================================================================
--  Interface du SCP-173 et des compagnons
--=========================================================================

local function draw_173_hud( ply )
    local watcher = scp131.get_watcher( ply )
    if not IsValid( watcher ) then return end

    draw_text(
        scp131.get_name( watcher ) .. " VOUS FIXE",
        "scp131:hud", ScrW() * 0.5, ScrH() * 0.7, variant_color( watcher ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
    )
    draw_text(
        "Son oeil ne cligne pas : il faut le renverser",
        "scp131:hud_small", ScrW() * 0.5, ScrH() * 0.73, color_dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
    )
end

local function draw_companion_hud( ply )
    local pods = get_cached_pods( ply )
    if #pods == 0 then return end

    local y = ScrH() * 0.78

    for _, pod in ipairs( pods ) do
        draw_text(
            scp131.get_name( pod ) .. " vous suit",
            "scp131:hud_small", ScrW() * 0.5, y, variant_color( pod ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )

        y = y + 18
    end
end

hook.Add( "HUDPaint", "scp131:hud", function()
    local ply = LocalPlayer()
    if not IsValid( ply ) or not ply:Alive() then return end

    if scp131.is_scp_131( ply ) then
        became_pod_at = became_pod_at or CurTime()
        draw_pod_hud( ply )
        return
    end

    became_pod_at = nil

    local guthscp173 = guthscp.modules.guthscp173
    if guthscp173 and guthscp173.is_scp_173( ply ) then
        draw_173_hud( ply )
    end

    draw_companion_hud( ply )
end )

--  chacun voit qui le tient : le pod son 173, le 173 son pod
hook.Add( "PreDrawHalos", "scp131:halos", function()
    local ply = LocalPlayer()
    if not IsValid( ply ) then return end

    if scp131.is_scp_131( ply ) then
        local watched = scp131.get_watched_173( ply )
        if watched then
            halo.Add( { watched }, color_hold, 2, 2, 1 )
        end

        return
    end

    local guthscp173 = guthscp.modules.guthscp173
    if not guthscp173 or not guthscp173.is_scp_173( ply ) then return end

    local watcher = scp131.get_watcher( ply )
    if not IsValid( watcher ) then return end

    halo.Add( { watcher }, variant_color( watcher ), 3, 3, 2 )
end )


--=========================================================================
--  Camera : inclinaison dans les virages, vrille quand il est sonne
--=========================================================================

local view_roll, view_fov_boost = 0, 0

hook.Add( "CalcView", "scp131:view", function( ply, pos, angles, fov )
    if not scp131.is_scp_131( ply ) then return end
    if ply:ShouldDrawLocalPlayer() then return end

    local soft = reduce_motion()
    local roll, fov_boost = 0, 0

    --  la roue penche dans les virages et le champ s'ouvre avec la vitesse
    if config131.wheel_enabled then
        local velocity = ply:GetVelocity()
        local max_speed = math.max( config131.wheel_max_speed, 1 )
        local side = math.Clamp( angles:Right():Dot( velocity ) / max_speed, -1, 1 )
        local ahead = math.Clamp( angles:Forward():Dot( velocity ) / max_speed, 0, 1.2 )

        roll = side * ( soft and 3 or 8 )
        fov_boost = ahead * ( soft and 3 or 8 )
    end

    --  sonne : le pod part en vrille le temps de se remettre sur sa roue (~2 Hz, hors bande a risque)
    local stunned_until = ply:GetNW2Float( "scp131:stunned_until", 0 )
    if stunned_until > CurTime() then
        local stunned_from = ply:GetNW2Float( "scp131:stunned_from", stunned_until )
        local duration = math.max( stunned_until - stunned_from, 0.1 )
        local ratio = math.Clamp( ( stunned_until - CurTime() ) / duration, 0, 1 )

        roll = roll + math.sin( CurTime() * 12 ) * ( soft and 5 or 18 ) * ratio
    end

    --  lisse pour que la camera ne saute pas au premier tick d'un virage
    local blend = math.Clamp( FrameTime() * 10, 0, 1 )
    view_roll = Lerp( blend, view_roll, roll )
    view_fov_boost = Lerp( blend, view_fov_boost, fov_boost )

    return {
        origin = pos,
        angles = Angle( angles.p, angles.y, view_roll ),
        fov = fov + view_fov_boost,
        drawviewer = false,
    }
end )
