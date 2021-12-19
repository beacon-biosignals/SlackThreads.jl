module SlackThreads

using JSON3
using StructTypes
using FileIO

export SlackThread, slack_log_exception

mutable struct SlackThread
    channel::Union{String,Nothing}
    ts::Union{String,Nothing}
end

StructTypes.StructType(::Type{SlackThread}) = StructTypes.Struct()

const CATCH_EXCEPTIONS = Ref(true)

# We turn off exception handling for our tests, to ensure we aren't throwing exceptions
# that we're missing. But we have it on by default, since in ordinary usage we want to
# be sure we are catching all exceptions.
# We wrap all public API methods in this, which should make it very difficult to throw
# an exception.
macro maybecatch(expr, exception_string)
    quote
        if CATCH_EXCEPTIONS[]
            try
                $(esc(expr))
            catch e
                @error $(exception_string) exception = (e, catch_backtrace())
                nothing
            end
        else
            let # introduce a local scope like `try` does
                $(esc(expr))
            end
        end
    end
end

"""
    SlackThread(channel=get(ENV, "SLACK_CHANNEL", nothing))

Constructs a `SlackThread`. A channel should be specified by it's ID
(a number like `C1H9RESGL` at the bottom of the "About" section of the channel).
"""
function SlackThread(channel=get(ENV, "SLACK_CHANNEL", nothing))
    thread = @maybecatch begin
        if channel === nothing
            #TODO: Use Preferences.jl for default channel?
            @warn "Channel not passed, nor `SLACK_CHANNEL` environmental variable set, so will only emit logging statements."
        end
        SlackThread(channel, nothing)
    end "Error when constructing `SlackThread`"
    thread === nothing && return SlackThread(nothing, nothing)
    return thread
end

function format_slack_link(uri, msg=nothing)
    if msg === nothing
        return "<$(uri)>"
    else
        return "<$(uri)|$(msg)>"
    end
end

"""
    (thread::SlackThread)(text, uploads...)

Each item in `uploads` may be:

* a pair of the form `name_with_extension::AbstractString => object`,
* or a path to a file (i.e. anything that supports `read` and `basename`)

Valid `object`s are:

* a vector of bytes (`Vector{UInt8}`)
* a string
* an object supporting `FileIO.save`

Note when using the pair syntax, including a file extension in the name helps
Slack choose how to display the object, and helps FileIO choose how to save the
object. E.g. `"my_plot.png"` instead of `"my_plot"`.
"""
function (thread::SlackThread)(text::AbstractString, uploads...)
    return @maybecatch begin
        if isempty(uploads)
            return send_message(thread, text)
        end
        mktempdir() do dir
            if length(uploads) == 1
                # special case: upload directly to thread
                extra_args = [`-F "initial_comment=$(text)"`]
                if !isnothing(thread.channel)
                    push!(extra_args, `-F channels=$(thread.channel)`)
                end
                if !isnothing(thread.ts)
                    push!(extra_args, `-F thread_ts=$(thread.ts)`)
                end
                return upload_file(local_file(only(uploads); dir); extra_args)
            end

            for item in uploads
                r = upload_file(local_file(item; dir))
                r === nothing && continue
                text *= format_slack_link(r.file.permalink, " ")
            end

            return send_message(thread, text)
        end

    end "Error when attempting to send message to Slack thread"
end

include("slack_api.jl")
include("slack_log_exception.jl")

end # module
