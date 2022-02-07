"""
    DummyThread <: AbstractSlackThread

Provides a "dummy" SlackThread which does not make any API calls
to Slack, and instead logs messages to it's `logged` field.

This can be used for testing or to pass to code expecting an `AbstractSlackThread`
when you don't want to log anything to Slack.

The `logged` field is a `Vector{Any}` such that each element is a tuple whose first entry
is a text message, and the following entries correspond to attachments.
"""
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
