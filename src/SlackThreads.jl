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

include("slack_api.jl")


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
        if length(uploads) == 1
            # special case: upload directly to thread
            # TODO. For now, fallback to the general approach,
            # which is fine but just leaves an `edited` note
            # on the message.
        end
        for item in uploads
            r = upload(item)
            r === nothing && continue
            text *= format_slack_link(r.file.permalink, " ")
        end
        send_message(thread, text)
    end "Error when attempting to send message to Slack thread"
end

function slack_log_exception(f, thread::SlackThread; interrupt_text=INTERRUPT_TEXT, exception_text=exception_text)
    try
        f()
    catch exception
        slack_log_exception(exception, catch_backtrace(); thread, interrupt_text,
        exception_text)
        rethrow()
    end
end

const INTERRUPT_TEXT = """
                       `InterruptException` recieved.

                       Probably you know about this already.
                       """

exception_text(exception, backtrace) = """
            :alert: Error occured! :alert:

            ```
            $(sprint(Base.display_error, exception, backtrace))
            ```
            """

function slack_log_exception(exception, backtrace; thread, interrupt_text=INTERRUPT_TEXT,
                             exception_text=exception_text)
    msg = exception isa InterruptException ? interrupt_text :
          exception_text(exception, backtrace)
    send_message(thread, msg)
    return nothing
end

end # module
