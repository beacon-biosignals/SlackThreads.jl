module SlackThreads

using JSON3
using StructTypes
using FileIO

export SlackThread

mutable struct SlackThread
    channel::String
    ts::Union{String,Nothing}
end

StructTypes.StructType(::Type{SlackThread}) = StructTypes.Struct()

function SlackThread(channel=get(ENV, "SLACK_CHANNEL", nothing))
    if channel === nothing
        throw(ArgumentError("TODO"))
    end
    return SlackThread(channel, nothing)
end

function upload(item::Pair{<:AbstractString, <:Any})
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

* a pair of the form `name => object`,
* or a path to a file

Valid `object`s are:

* a vector of bytes (`Vector{UInt8}`)
* a string
* an object supporting `FileIO.save`
"""
function (thread::SlackThread)(text, uploads...)
    for item in uploads
        r = upload(item)
        text *= format_slack_link(r.file.permalink, " ")
    end
    return slack_message(thread, text)
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
    else
        @debug "Sending slack message" data api
    end
    auth = "Authorization: Bearer $(token)"

    response = try
        JSON3.read(readchomp(`curl -s -X POST -H $auth -H 'Content-type: application/json; charset=utf-8' --data $(data_str) $api`))
    catch e
        @error "Error when attempting to send message to Slack thread" exception = (e,
                                                                                    catch_backtrace())
    end
    @debug "Slack responded" response

    if thread.ts === nothing
        thread.ts = response.ts
    end
    return response
end

# """
#     slack_image(thread::SlackThread, bytes::Vector{UInt8}; comment="Test image.")
#     slack_image(thread::SlackThread, path::AbstractFilePath; comment="Test image.")

# Sends an image to a Slack thread. If no thread exists, it creates one and
# stores it in `thread` so future messages will go to that thread.

# If the environmental variable `SLACK_TOKEN` is not set, then no message can be sent;
# in that case, a `@warn` logging statement is issued, but no exception is reported.
# """
# function slack_image(thread::SlackThread, bytes::Vector{UInt8}, name="image";
#                      comment="Test image.")
#     api = "https://slack.com/api/files.upload"

#     token = get(ENV, "SLACK_TOKEN", nothing)
#     if token === nothing
#         @warn "No Slack token provided; image not sent." comment api name
#         return nothing
#     else
#         @debug "Sending slack image" comment api name
#     end

#     auth = "Authorization: Bearer $(token)"

#     response = mktempdir() do dir
#         local_path = joinpath(dir, name)
#         write(local_path, bytes)
#         return try
#             JSON3.read(readchomp(`curl -s -F file=@$(local_path) -F "initial_comment=$(comment)" -F channels=$(thread.channel) -F thread_ts=$(thread.ts) -H $auth $api`))
#         catch e
#             @error "Error when attempting to send image to Slack thread" exception = (e,
#                                                                                       catch_backtrace())
#         end
#     end
#     @debug "Slack responded" response

#     if thread.ts === nothing
#         thread.ts = response.ts
#     end
#     return response
# end

function upload_bytes(name, bytes::Vector{UInt8})
    mktempdir() do dir
        local_path = joinpath(dir, name)
        write(local_path, bytes)
        upload_file(local_path)
    end
end

upload_file(path) = upload_bytes(basename(path), read(path))

function upload_file(local_path::AbstractString)
    api = "https://slack.com/api/files.upload"

    token = get(ENV, "SLACK_TOKEN", nothing)
    if token === nothing
        @warn "No Slack token provided; file not sent." api name
        return nothing
    else
        @debug "Uploading slack file" api name
    end

    auth = "Authorization: Bearer $(token)"

    response = return try
            JSON3.read(readchomp(`curl -s -F file=@$(local_path) -H $auth $api`))
        catch e
            @error "Error when attempting to send image to Slack thread" exception = (e,
                                                                                      catch_backtrace())
        end
    @debug "Slack responded" response
    return response
end

# function slack_image(thread::SlackThread, path::AbstractFilePath; comment="Test image.")
#     return slack_image(thread, read(path), basename(path); comment)
# end

# Let's use an alias, since they are the same function in fact ;)
# const slack_file = slack_image

function format_slack_link(uri, msg=nothing)
    if msg === nothing
        return "<$(uri)>"
    else
        return "<$(uri)|$(msg)>"
    end
end

const INTERRUPT_TEXT =  """
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
