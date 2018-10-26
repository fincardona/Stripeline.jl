using Quaternions
import Healpix
using StaticArrays
using LinearAlgebra
using AstroLib

export TENERIFE_LATITUDE_DEG, TENERIFE_LONGITUDE_DEG, TENERIFE_HEIGHT_M
export timetorotang, genpointings

TENERIFE_LATITUDE_DEG = 28.3
TENERIFE_LONGITUDE_DEG = -16.509722
TENERIFE_HEIGHT_M = 2390

"""
    timetorotang(time, rpm)

Convert a time into a rotation angle, given the number of rotations per minute.
The time should be expressed in seconds. The return value is in radians.
`time` can either be a scalar or a vector.
"""
function timetorotang(time_s, rpm)
    if rpm == 0
        0.0
    else
        2 * π * time_s * (rpm / 60)
    end
end


"""
    genpointings(wheelanglesfn, dir, timerange_s; latitude_deg=0.0, 
                 ground=false)

Generate a set of pointings for some STRIP detector. The parameter
`wheelanglesfn` must be a function which takes as input a time in seconds
and returns a 3-tuple containing the angles (in radians) of the three
motors:
1. The boresight motor
2. The altitude motor
3. The ground motor

The parameter `dir` must be a normalized vector which tells the pointing
direction of the beam (boresight is [0, 0, 1]). The parameter `timerange_s`
is either a range or a vector which specifies at which times (in second)
the pointings should be computed. The keyword `latitude_deg` should contain
the latitude (in degrees, N is positive) of the location where the observation
is made. The keyword `ground` must be a boolean: if true the angles will be 
referred to the ground coordinate system otherwise they will be expressed in 
equatorial coordinates; default is false.

Return a 2-tuple containing the directions (a N×2 array containing the
colatitude and the longitude) and the polarization angles at each time step.

Example:
`````julia
genpointings([0, 0, 1], 0:0.1:1) do time_s
    # Boresight motor keeps a constant angle equal to 0°
    # Altitude motor remains at 20° from the Zenith
    # Ground motor spins at 1 RPM
    return (0.0, deg2rad(20.0), timetorotang(time_s, 1))
end
`````
"""
function genpointings(wheelanglesfn,
                      dir,
                      timerange_s;
                      latitude_deg=0.0,
                      ground=false)
    
    dirs = Array{Float64}(undef, length(timerange_s), 2)
    ψ = Array{Float64}(undef, length(timerange_s))

    zaxis = [1; 0; 0]
    for (idx, time_s) = enumerate(timerange_s)
        (wheel1ang, wheel2ang, wheel3ang) = wheelanglesfn(time_s)
        
        qwheel1 = qrotation([0, 0, 1], wheel1ang)
        qwheel2 = qrotation([1, 0, 0], wheel2ang)
        qwheel3 = qrotation([0, 0, 1], wheel3ang)
        
        # This is in the ground reference frame
        groundq = qwheel3 * (qwheel2 * qwheel1)
        
        # Now from the ground reference frame to the Earth reference frame
        locq = qrotation([1, 0, 0], deg2rad(90 - latitude_deg))
        earthq = qrotation([0, 0, 1], 2 * π * time_s / 86400)

        quat = earthq * (locq * groundq)

        if ground
            rotmatr = rotationmatrix(groundq)
        else
            rotmatr = rotationmatrix(quat)
        end
        
        vector = rotmatr * dir
        poldir = rotmatr * zaxis

        # The North for a vector v is just -dv/dθ, as θ is the
        # colatitude and moves along the meridian
        (θ, ϕ) = Healpix.vec2ang(vector[1], vector[2], vector[3])
        dirs[idx, 1] = θ
        dirs[idx, 2] = ϕ
        northdir = @SArray [-cos(θ) * cos(ϕ), -cos(θ) * sin(ϕ), sin(θ)]
        
        cosψ = clamp(dot(northdir, poldir), -1, 1)
        crosspr = northdir × poldir
        sinψ = clamp(sqrt(dot(crosspr, crosspr)), -1, 1)
        ψ[idx] = atan(cosψ, sinψ)
    end
    
    (dirs, ψ)
end


"""
    genpointings(wheelanglesfn, dir, timerange_s, t_start, t_stop; 
                 latitude_deg=0.0, longitude_deg, height_m)

Generate a set of pointings for some STRIP detector. The parameter
`wheelanglesfn` must be a function which takes as input a time in seconds
and returns a 3-tuple containing the angles (in radians) of the three
motors:
1. The boresight motor
2. The altitude motor
3. The ground motor

The parameter `dir` must be a normalized vector which tells the pointing
direction of the beam (boresight is [0, 0, 1]). The parameter `timerange_s`
is either a range or a vector which specifies at which times (in second)
the pointings should be computed. The parameter `t_start` and `t_start` must be 
two DateTime which tell the exact UTC date and time of the observation. The 
keywords `latitude_deg`, `longitude_deg` and `height_m` should contain the 
latitude (in degrees, N is positive), the longitude (in degrees, counterclockwise
is positive) and the height (in meters) of the location where the observation is 
made.

Return a 4-tuple containing the directions (a N×2 array containing the
colatitude and the longitude) expressed in local coordinates, the polarization 
angles, the sky directions (a N×2 array containing the Declination and the 
RightAscension) and the polarization angle given in equatorial coordinates, 
at each time step.

Example:
`````julia
genpointings([0, 0, 1], 
             0:0.1:1, 
             DateTime(2019, 01, 01, 0, 0, 0), 
             DateTime(2022, 04, 13, 21, 10, 10), 
             latitude_deg=10.0
             longitude_deg=20.0
             height_m = 1000) do time_s
    # Boresight motor keeps a constant angle equal to 0°
    # Altitude motor remains at 20° from the Zenith
    # Ground motor spins at 1 RPM
    return (0.0, deg2rad(20.0), timetorotang(time_s, 1))
end
`````
"""
function genpointings(wheelanglesfn,
                      dir,
                      timerange_s,
                      t_start,
                      t_stop;
                      latitude_deg=0.0,
                      longitude_deg=0.0,
                      height_m=0.0)
    
    dirs = Array{Float64}(undef, length(timerange_s), 2)
    ψ = Array{Float64}(undef, length(timerange_s))
    skydirs = Array{Float64}(undef, length(timerange_s), 2)
    
    jd_start = AstroLib.jdcnv(t_start)
    jd_stop = AstroLib.jdcnv(t_stop)
    jd_range = range(jd_start, stop=jd_stop, length=length(timerange_s))

    zaxis = [1; 0; 0]
    for (idx, time_s) = enumerate(timerange_s)
        (wheel1ang, wheel2ang, wheel3ang) = wheelanglesfn(time_s)
        
        qwheel1 = qrotation([0, 0, 1], wheel1ang)
        qwheel2 = qrotation([1, 0, 0], wheel2ang)
        qwheel3 = qrotation([0, 0, 1], wheel3ang)
        
        # This is in the ground reference frame
        groundq = qwheel3 * (qwheel2 * qwheel1)
        
        rotmatr = rotationmatrix(groundq)
        
        vector = rotmatr * dir
        poldir = rotmatr * zaxis

        (θ, ϕ) = Healpix.vec2ang(vector[1], vector[2], vector[3])
        dirs[idx, 1] = θ
        dirs[idx, 2] = ϕ

        Alt_rad = π/2 - θ 
        Az_rad = 2π - ϕ

        Ra_deg, Dec_deg, HA_deg = AstroLib.hor2eq(rad2deg(Alt_rad),
                                                  rad2deg(Az_rad),
                                                  jd_range[idx],
                                                  latitude_deg,
                                                  longitude_deg,
                                                  height_m,
                                                  precession=true,
                                                  nutate=true,
                                                  aberration=true)

        skydirs[idx, 1] = deg2rad(Dec_deg)
        skydirs[idx, 2] = deg2rad(Ra_deg)

    end
    
    (dirs, skydirs) # Must add the polarization angles
end

