mutable struct DummyThread <: AbstractSlackThread
    channel::Union{String,Nothing}
    ts::Union{String,Nothing}
    logged::Vector{Any}
end

DummyThread() = DummyThread(nothing, nothing, [])

StructTypes.StructType(::DummyThread) = StructTypes.Struct()

function (d::DummyThread)(args...)
    push!(d.logged, args)
    return nothing
end

function send_exception_message(d::DummyThread, msg)
    push!(d.logged, tuple(msg))
    return nothing
end
