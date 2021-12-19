#####
##### Attachments
#####

# Upload dispatch strategy:
# We need a local file to upload.
#
# entrypoint is `upload(item)`.
# Pairs are destructured to to the two argument `upload(name, object)` methods.
# Non-pairs are assumed to be file paths and are dispached to `upload_file(path)`.
upload(item::Pair) = upload(item...)
upload(file) = upload_file(file)

# Two-argument `upload`. Second argument is assumed to be an object to write, not a filepath
# (since that is only allowed in the 1-arg case). Bytes are passed on as-is; strings are converted
# to bytes, and everything else uses `FileIO.save`.
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

# If the `path` is not a `AbstractString`, we assume it isn't a local path
# (maybe it's an S3Path, etc.). So we conservatively write a new local file to upload.
# Thus, we only generically require `basename` and `read` to be supported for path types.
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
        # directly to thread: (not supported yet)
        # JSON3.read(readchomp(`curl -s -F file=@$(local_path) -F "initial_comment=$(comment)" -F channels=$(thread.channel) -F thread_ts=$(thread.ts) -H $auth $api`))
    end "Error when attempting to upload file to Slack"

    response === nothing && return nothing
    @debug "Slack responded" response
    return response
end

#####
##### Messages
#####

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
