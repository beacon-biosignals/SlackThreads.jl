"""
    SlackCallRecord

This object has fields

* `call::Symbol`: either `:DummyThread` or `:send_exception_message`
* `args::Tuple`: the arguments to the call
* `kwargs::NamedTuple`: any keyword arguments to the call

corresponding to function calls made with [`DummyThread`](@ref)s.
"""
struct SlackCallRecord
    call::Symbol
    args::Tuple
    kwargs::NamedTuple
end

StructTypes.StructType(::Type{SlackCallRecord}) = StructTypes.Struct()
# This makes it so JSON3 doesn't omit tuples/namedtuples if they are empty
@inline StructTypes.isempty(::Type{SlackCallRecord}, ::NamedTuple) = false
@inline StructTypes.isempty(::Type{SlackCallRecord}, ::Tuple) = false

"""
    DummyThread <: AbstractSlackThread

Provides a "dummy" SlackThread which does not make any API calls
to Slack, and instead logs messages to it's `logged` field.

This can be used for testing or to pass to code expecting an `AbstractSlackThread`
when you don't want to log anything to Slack.

The `logged` field is a `Vector{SlackCallRecord}` corresponding to logging calls.

See also: [`SlackCallRecord`](@ref).
"""
mutable struct DummyThread <: AbstractSlackThread
    channel::Union{String,Nothing}
    ts::Union{String,Nothing}
    logged::Vector{SlackCallRecord}
end

DummyThread() = DummyThread(nothing, nothing, [])

StructTypes.StructType(::Type{DummyThread}) = StructTypes.Struct()

function (d::DummyThread)(args...; kwargs...)
    push!(d.logged, SlackCallRecord(:DummyThread, args, NamedTuple(kwargs)))
    return nothing
end

function send_exception_message(d::DummyThread, msg)
    push!(d.logged, SlackCallRecord(:send_exception_message, tuple(msg), NamedTuple()))
    return nothing
end
