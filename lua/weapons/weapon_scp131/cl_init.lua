include( "shared.lua" )

hook.Add( "CalcView", "SCP131:ViewAdjustment", function( ply, pos, angles, fov )
    local wep = ply:GetActiveWeapon()
    if not IsValid( wep ) or wep:GetClass() ~= "weapon_scp131" then return end
    if ply:ShouldDrawLocalPlayer() then return end

    local view = {}
    view.origin = pos - Vector( 0, 0, 40 )
    view.angles = angles
    view.fov = fov

    --  renverse : le pod part en vrille le temps de se remettre sur sa roue
    local stunned_until = ply:GetNWFloat( "scp131:stunned_until", 0 )
    if stunned_until > CurTime() then
        local stunned_from = ply:GetNWFloat( "scp131:stunned_from", stunned_until )
        local duration = math.max( stunned_until - stunned_from, 0.1 )
        local ratio = math.Clamp( ( stunned_until - CurTime() ) / duration, 0, 1 )

        view.angles = Angle( angles.p, angles.y, math.sin( CurTime() * 18 ) * 25 * ratio )
        view.origin = view.origin - Vector( 0, 0, 6 * ratio )
    end

    return view
end )
