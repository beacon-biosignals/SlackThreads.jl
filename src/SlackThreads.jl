module SlackThreads

using JSON3
using StructTypes
using FileIO

export SlackThread

mutable struct SlackThread
    channel::Union{String,Nothing}
    ts::Union{String,Nothing}
end

StructTypes.StructType(::Type{SlackThread}) = StructTypes.Struct()

const CATCH_EXCEPTIONS = Ref(true)
const EXCEPTION_LOG_STR = "Error when attempting to send message to Slack thread"

# We turn off exception handling for our tests, to ensure we aren't throwing exceptions
# that we're missing. But we have it on by default, since in ordinary usage we want to
# be sure we are catching all exceptions.
macro maybetry(expr)
    quote
        if CATCH_EXCEPTIONS[]
            try
                $(esc(expr))
            catch e
                @error EXCEPTION_LOG_STR exception = (e, catch_backtrace())
                nothing
            end
        else
            $(esc(expr))
        end
    end
end

function SlackThread(channel=get(ENV, "SLACK_CHANNEL", nothing))
    if channel === nothing
        #TODO: Use Preferences.jl for default channel?
        @warn "Channel not passed, nor `SLACK_CHANNEL` environmental variable set, so will only emit logging statements."
    end
    return SlackThread(channel, nothing)
end

function upload(item::Pair{<:AbstractString,<:Any})
    name, obj = item
    return upload(name, obj)
end

upload(file) = upload_file(file)

upload(name, v::Vector{UInt8}) = upload_bytes(name, v)
upload(name, v::AbstractString) = upload_bytes(name, Vector{UInt8}(v))

function upload(name, v)
    return mktempdir() do dir
        local_path = joinpath(dir, name)
        save(local_path, v)
        return upload_file(local_path)
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
function (thread::SlackThread)(text, uploads...)
    @maybetry begin
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
        return slack_message(thread, text)
    end
end

"""
    slack_message(thread::SlackThread, text::AbstractString)

Sends a message to a Slack thread. If no thread exists, it creates one and
stores it in `thread` so future messages will go to that thread.

If the environmental variable `SLACK_TOKEN` is not set, then no message can be sent;
in that case, a `@warn` logging statement is issued, but no exception is reported.
"""
function slack_message(thread::SlackThread, text::AbstractString)
    data = Dict("channel" => thread.channel, "text" => text)
    if thread.ts !== nothing
        data["thread_ts"] = thread.ts
    end
    data_str = JSON3.write(data)
    api = "https://slack.com/api/chat.postMessage"

    token = get(ENV, "SLACK_TOKEN", nothing)
    if token === nothing
        @warn "No Slack token provided; message not sent." data api
        return nothing
    elseif thread.channel === nothing
        @warn "No Slack channel provided; message not sent." data api
        return nothing
    else
        @debug "Sending slack message" data api
    end
    auth = "Authorization: Bearer $(token)"

    response = @maybetry begin
        JSON3.read(readchomp(`curl -s -X POST -H $auth -H 'Content-type: application/json; charset=utf-8' --data $(data_str) $api`))
    end
    response === nothing && return nothing
    @debug "Slack responded" response

    if thread.ts === nothing && hasproperty(response, :ts) === true
        thread.ts = response.ts
    end
    return response
end

function upload_bytes(name, bytes::Vector{UInt8})
    mktempdir() do dir
        local_path = joinpath(dir, name)
        write(local_path, bytes)
        return upload_file(local_path)
    end
end

upload_file(path) = upload_bytes(basename(path), read(path))

function upload_file(local_path::AbstractString)
    api = "https://slack.com/api/files.upload"

    token = get(ENV, "SLACK_TOKEN", nothing)
    if token === nothing
        @warn "No Slack token provided; file not sent." api
        return nothing
    else
        @debug "Uploading slack file" api
    end

    auth = "Authorization: Bearer $(token)"

    response = @maybetry begin
        JSON3.read(readchomp(`curl -s -F file=@$(local_path) -H $auth $api`))
        # directly to thread:
        # JSON3.read(readchomp(`curl -s -F file=@$(local_path) -F "initial_comment=$(comment)" -F channels=$(thread.channel) -F thread_ts=$(thread.ts) -H $auth $api`))
    end
    response === nothing && return nothing

    @debug "Slack responded" response
    return response
end

function format_slack_link(uri, msg=nothing)
    if msg === nothing
        return "<$(uri)>"
    else
        return "<$(uri)|$(msg)>"
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
    slack_message(thread, msg)
    return nothing
end

end # module
