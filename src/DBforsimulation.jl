export get_info_from_DB
import Random


"""
    function get_info_from_DB(db, horns)
    
        This function can be used to take information about specific horns from the STRIP instrument database.

        Given:
        -The database (db = Stripeline.InstrumentDB())
        -A vector containg the names of the horns of interest  (e.g. ["Y0", "I1", "R6"])

        It returns 5 arrays, containing for each horn:
        - the 3D vector containing the orientation of the horn in the sky
        - the unique ID of the polarimeter associated to the horn
        - the estimated bandwidth, in Hz
        - the estimated noise temperature, in K
        - the estimated knee frequency, in Hz
        
        For those polarimeters without an available measurement of the knee frequency (13 out of 49)
        the function randomly picks a value from a vector containing all the 36 fknee measurements available in the database.

"""
function get_info_from_DB(db, horns)

    orientations=[]
    polarimeters = Array{Int64}(undef, length(horns))
    β_hz = Array{Float64}(undef,length(horns))
    tnoise_k = Array{Float64}(undef,length(horns))
    fknee_hz = Array{Float64}(undef,length(horns))

    measured_fknees = Float64[]
    for i in 1:length(horns)
        polarimeters[i] = db.focalplane[horns[i]].polid
        if(db.detectors[polarimeters[i]].spectrum.fknee_q_hz !=0)
            push!(measured_fknees, db.detectors[polarimeters[i]].spectrum.fknee_q_hz)
        end
    end

    rng = Random.MersenneTwister(1234)

    for i in 1:length(horns)
        append!(orientations, [db.focalplane[horns[i]].orientation])
        β_hz[i] = db.detectors[polarimeters[i]].bandshape.bandwidth_hz
        tnoise_k[i] = db.detectors[polarimeters[i]].tnoise.tnoise_k
          
        if(db.detectors[polarimeters[i]].spectrum.fknee_q_hz ==0)
            fknee_hz[i] = rand(rng, measured_fknees)
        else
            fknee_hz[i] = db.detectors[polarimeters[i]].spectrum.fknee_q_hz
        end
    end
    return orientations, polarimeters, β_hz, tnoise_k, fknee_hz

end
