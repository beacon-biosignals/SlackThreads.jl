module SlackThreads

using JSON3
using StructTypes
using FileIO
using Mocking

using CURL_jll

export AbstractSlackThread, SlackThread, slack_log_exception
export DummyThread, SlackCallRecord

abstract type AbstractSlackThread end

mutable struct SlackThread <: AbstractSlackThread
    channel::Union{String,Nothing}
    ts::Union{String,Nothing} # In Slack terminology, `ts_thread`: the ID of another un-threaded message to reply to (https://api.slack.com/reference/messaging/payload)
end

function Base.copyto!(thread::SlackThread, obj)
    thread.channel = obj.channel
    thread.ts = obj.ts
    return thread
end

StructTypes.StructType(::Type{SlackThread}) = StructTypes.Struct()

const CATCH_EXCEPTIONS = Ref(true)

# We turn off exception handling for our tests, to ensure we aren't throwing exceptions
# that we're missing. But we have it on by default, since in ordinary usage we want to
# be sure we are catching all exceptions.
# We wrap all public API methods in this, which should make it very difficult to throw
# an exception.
macro maybecatch(expr, log_str)
    quote
        if CATCH_EXCEPTIONS[]
            try
                $(esc(expr))
            catch e
                @error $(log_str) exception = (e, catch_backtrace())
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

Constructs a `SlackThread`. A channel should be specified by it's ID (a number
like `C1H9RESGL` at the bottom of the "About" section of the channel).
"""
function SlackThread(channel=get(ENV, "SLACK_CHANNEL", nothing))
    thread = @maybecatch begin
        if channel === nothing
            #TODO: Use Preferences.jl for default channel?
            @warn "`channel` not passed, nor `SLACK_CHANNEL` environmental variable set, so will only emit logging statements."
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
    (thread::SlackThread)(text::AbstractString, uploads...;
                          combine_texts=combine_texts, options...)

Sends a message to the Slack thread with the contents `text`. If this is the
first message sent by `thread`, this starts a new thread (in `thread.channel`),
otherwise it updates the existing thread.

You can also include plots, images, and files by passing file paths or lists of
pairs as `uploads`.

Returns:

* If the request is successful, returns Slack's response for the message as a
  `JSON3.Object`. If more than one upload is present, or `options` are passed,
  the response will be for a text-only request, since the file uploads will
  be processed separately (using the strategy from
  https://stackoverflow.com/a/63391026/12486544).
* If the request is not successful, returns `nothing`.

## Uploads

Each item in `uploads` may be:

* a `Pair` of the form `name_with_extension::AbstractString => object`,
* or a path to a file (i.e. anything that supports `read` and `basename`)

Valid `object`s are:

* a vector of bytes (`Vector{UInt8}`)
* a string
* an object supporting `FileIO.save`

!!! note
    When using the pair syntax, including a file extension in the name
    helps Slack choose how to display the object, and helps FileIO choose how to
    save the object. E.g. `"my_plot.png"` instead of `"my_plot"`.

## Logging

* Emits `@debug` logs when sending requests and recieving responses from the Slack API.
* Emits `@warn` logs with the contents of requests to the Slack API when the channel or token is not configured correctly (in lieu of sending a request)
* Emits `@error` logs when an exception is encountered or Slack returns an error response.

## Message splitting

By default, [`SlackThreads.combine_texts`](@ref) is used to combine the message text and attachment link text
into a set of messages, which returns multiple messages in the case of many attachments.
One may pass any function to the `combine_texts` keyword argument which accepts and returns a vector of strings,
for example, `texts -> SlackThreads.combine_texts(texts; max_length=100, message_count_suffix=(i, n) -> "")`
to split messages after 100 characters, and to not add a `[\$i / \$n]` suffix to the messages.

## Options

One may pass any optional arguments supported by [`chat.postMessage`](https://api.slack.com/methods/chat.postMessage#args),
e.g. `link_names = true`, as keyword arguments.
"""
function (thread::SlackThread)(text::AbstractString, uploads...;
                               combine_texts=combine_texts, options...)
    return @maybecatch begin
        if thread.channel === nothing
            @warn "No Slack channel configured; message not sent." text uploads
            return nothing
        end
        if isempty(uploads)
            # send directly
            return send_message(thread, text; options...)
        end
        mktempdir() do dir
            if length(uploads) == 1 && thread.ts !== nothing && isempty(options)
                # special case: upload directly to thread
                # cannot do this if we don't have a `ts` already because
                # the response doesn't give us a `ts` to use.
                # i.e. we can post the message but don't have the `ts`
                # to thread from it. So in that case, we fallback
                # to the general case. We also can't do this if the user has passed
                # any options, since those are likely only valid for `chat.postMessage`.
                extra_args = ["-F", "initial_comment=$(text)", "-F",
                              "channels=$(thread.channel)", "-F", "thread_ts=$(thread.ts)"]
                return upload_file(local_file(only(uploads); dir); extra_args)
            end

            texts = String[text]

            for item in uploads
                r = upload_file(local_file(item; dir))
                r === nothing && continue
                push!(texts, format_slack_link(r.file.permalink, " "))
            end

            messages = combine_texts(texts)
            local r
            for msg in messages
                r = send_message(thread, msg; options...)
            end
            return r # return last response
        end
    end "Error when attempting to send message to Slack thread"
end

include("slack_api.jl")
include("slack_log_exception.jl")
include("utilities.jl")
include("dummy_slack_thread.jl")

end # module
