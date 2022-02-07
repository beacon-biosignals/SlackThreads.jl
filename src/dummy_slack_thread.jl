mutable struct DummyThread <: AbstractSlackThread
    channel::Union{String,Nothing}
    ts::Union{String,Nothing}
    messages::Vector{String}
    files::Vector{Tuple{String, Vector{String}}}
end

DummyThread() = DummyThread(nothing, nothing, String[], Tuple{String, Vector{String}}[])

StructTypes.StructType(::DummyThread) = StructTypes.Struct()

function send_message(d::DummyThread, msg)
    push!(d.messages, msg)
    return nothing
end

function upload_file(d::DummyThread, file; extra_args=String[])
    push!(d.files, (file, extra_args))
    return nothing
end
