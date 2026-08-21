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

local function draw_pod_hud( ply )
    local color = variant_color( ply )
    local center_x = ScrW() * 0.5

    draw_text( scp131.get_name( ply ), "scp131:hud", center_x, ScrH() * 0.9, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

    if scp131.is_stunned( ply ) then
        draw_text( "ETOURDI", "scp131:hud", center_x, ScrH() * 0.66, color_alert, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end

    --  contact visuel sur le 173
    local watched = scp131.get_watched_173( ply )
    if watched then
        draw_text(
            "SCP-173 TENU DU REGARD",
            "scp131:hud", center_x, ScrH() * 0.7, color_hold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end

    --  compagnon : direction et distance, pour pouvoir le suivre sans le perdre
    local companion = scp131.get_companion( ply )
    if IsValid( companion ) then
        local position = companion:EyePos()
        local x, y, on_screen = draw_offscreen_arrow( position, color )
        local distance = math.floor( ply:GetPos():Distance( companion:GetPos() ) / 52.49 )  --  unites -> metres

        draw_text(
            companion:Nick() .. "  " .. distance .. " m",
            "scp131:hud_small", x, y - ( on_screen and 24 or 22 ), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end

    --  progression du lien en cours
    local target = bond_target
    if not IsValid( target ) or CurTime() > bond_expiry then return end

    local progress = math.Clamp( bond_progress, 0, 1 )
    local width, height = 260, 10
    local x, y = center_x - width * 0.5, ScrH() * 0.62

    surface.SetDrawColor( 0, 0, 0, 180 )
    surface.DrawRect( x - 1, y - 1, width + 2, height + 2 )
    surface.SetDrawColor( color )
    surface.DrawRect( x, y, width * progress, height )

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
        draw_pod_hud( ply )
        return
    end

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
