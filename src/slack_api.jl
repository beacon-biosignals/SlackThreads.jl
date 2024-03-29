#####
##### Exceptions
#####

struct SlackError <: Exception
    error::String
end

#####
##### Attachments
#####

# Upload dispatch strategy:
# We need a local file to upload.
#
# entrypoint is `local_file(item)`.
# Pairs are destructured to to the two argument `local_file(name, object)` methods.
# Non-pairs are assumed to be file paths and are dispached to `local_file(path)`.
local_file(item::Pair; kw...) = local_file(first(item), last(item); kw...)
local_file(file::AbstractString; kw...) = file

# If the `path` is not a `AbstractString`, we assume it isn't a local path
# (maybe it's an S3Path, etc.). So we conservatively write a new local file to upload.
# Thus, we only generically require `basename` and `read` to be supported for path types.
local_file(file; kw...) = local_file(basename(file), read(file); kw...)

# Two-argument `local_file`. Second argument is assumed to be an object to write, not a filepath
# (since that is only allowed in the 1-arg case). Bytes and strings are written to a file and everything else uses `FileIO.save`.

function local_file(name, object; dir=mktempdir())
    local_path = joinpath(dir, name)
    if object isa Union{Vector{UInt8},<:AbstractString}
        write(local_path, object)
    else
        save(local_path, object)
    end
    return local_path
end

function upload_file(local_path::AbstractString; extra_body=Dict())
    api = "https://slack.com/api/files.upload"

    token = get(ENV, "SLACK_TOKEN", nothing)
    if token === nothing
        @warn "No Slack token provided; file not sent." api local_path
        return nothing
    else
        @debug "Uploading slack file" api local_path
    end

    headers = ["Authorization" => "Bearer $(token)"]
    response = @maybecatch begin
        open(local_path, "r") do file
            body = HTTP.Form(vcat(collect(extra_body), ["file" => file]))
            response = @mock HTTP.post(api, headers, body)
            return JSON3.read(response.body)
        end
    end "Error when attempting to upload file to Slack"

    response === nothing && return nothing

    if haskey(response, :ok) === true && response[:ok] != true
        return @maybecatch begin
            err = haskey(response, :error) ? string(response.error) :
                  "No error field returned"
            throw(SlackError(err))
        end "Error reported by Slack API"
    end

    @debug "Slack responded" response
    return response
end

#####
##### Messages
#####

function send_message(thread::SlackThread, text::AbstractString; options...)
    data = Dict{String,Any}(string(k) => v for (k, v) in pairs(options))
    data["channel"] = thread.channel
    data["text"] = text
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
        @warn "No Slack channel configured; message not sent." data api
        return nothing
    else
        @debug "Sending slack message" data api
    end

    headers = ["Authorization" => "Bearer $(token)",
               "Content-type" => "application/json; charset=utf-8"]

    response = @maybecatch begin
        response = @mock HTTP.post(api, headers, data_str)
        JSON3.read(response.body)
    end "Error when attempting to send message to Slack thread"

    response === nothing && return nothing
    @debug "Slack responded" response

    if haskey(response, :ok) === true && response[:ok] === false
        return @maybecatch begin
            err = haskey(response, :error) ? string(response.error) :
                  "No error field returned"
            throw(SlackError(err))
        end "Error reported by Slack API"
    end

    if thread.ts === nothing && hasproperty(response, :ts) === true
        thread.ts = response.ts
    end
    return response
end
