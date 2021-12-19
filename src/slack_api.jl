
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

function upload_bytes(name, bytes::Vector{UInt8})
    mktempdir() do dir
        local_path = joinpath(dir, name)
        write(local_path, bytes)
        return upload_file(local_path)
    end
end


"""
    send_message(thread::SlackThread, text::AbstractString)

Sends a message to a Slack thread. If no thread exists, it creates one and
stores it in `thread` so future messages will go to that thread.

If the environmental variable `SLACK_TOKEN` is not set, then no message can be sent;
in that case, a `@warn` logging statement is issued, but no exception is reported.
"""
function send_message(thread::SlackThread, text::AbstractString)
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

    response = @maybecatch begin
        JSON3.read(readchomp(`curl -s -X POST -H $auth -H 'Content-type: application/json; charset=utf-8' --data $(data_str) $api`))
    end "Error when attempting to send message to Slack thread"

    response === nothing && return nothing
    @debug "Slack responded" response

    if thread.ts === nothing && hasproperty(response, :ts) === true
        thread.ts = response.ts
    end
    return response
end

upload_file(path) = upload_bytes(basename(path), read(path))

function upload_file(local_path::AbstractString)
    api = "https://slack.com/api/files.upload"

    token = get(ENV, "SLACK_TOKEN", nothing)
    if token === nothing
        @warn "No Slack token provided; file not sent." api local_path
        return nothing
    else
        @debug "Uploading slack file" api local_path
    end

    auth = "Authorization: Bearer $(token)"

    response = @maybecatch begin
        JSON3.read(readchomp(`curl -s -F file=@$(local_path) -H $auth $api`))
        # directly to thread:
        # JSON3.read(readchomp(`curl -s -F file=@$(local_path) -F "initial_comment=$(comment)" -F channels=$(thread.channel) -F thread_ts=$(thread.ts) -H $auth $api`))
    end "Error when attempting to upload file to Slack"

    response === nothing && return nothing
    @debug "Slack responded" response
    return response
end
