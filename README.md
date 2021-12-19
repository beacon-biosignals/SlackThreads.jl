# SlackThreads

[![Build Status](https://github.com/ericphanson/SlackThreads.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ericphanson/SlackThreads.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ericphanson/SlackThreads.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ericphanson/SlackThreads.jl)

Provides a simple way to update a running Slack thread with text and attachments (files, images, etc).

## Requirements

This package needs a Slack OAuth token associated to a Slack app with the permissions `chat:write` and `files:write` (only needed for uploading files/images). You can make an app at <https://api.slack.com/apps>. Then install it to a workplace and add the permissions, and get an "Bot User OAuth Token". Set this as the environmental variable `SLACK_TOKEN`. You can do this in a running Julia session via

```julia
ENV["SLACK_TOKEN"] = read(Base.getpass("Slack token"), String)
```

and pasting it in. You will need to do this every session, or set the variable elsewhere (e.g. in a shell startup script, CI secret, Kubernetes secret, etc.)

One also needs to specify a Slack channel to create threads in. You will likely need to invite your bot app into that channel (an easy way is to ping them and then click invite to channel). Once you have a channel for which your bot app has access, get the channel ID (a value like `C1H9RESGL` which you can find at the bottom of the "About" section of a channel). You can pass this to the `SlackThread` constructor or set an environmental variable `SLACK_CHANNEL`.

## Usage

The main object of interest is a `SlackThread`, constructed by `thread = SlackThread()` (one may pass a `channel` and the default is `ENV["SLACK_CHANNEL"]`).

The first time a message is sent with a particular `SlackThread`, a new thread is started in the channel. Subsequent messages will be posted to that thread.

The `thread` can be called as a function to send a message. Additionally, file paths or pairs of the form `name_with_extension => object` may be passed to add attachments to the message. See the docstring for more details.

```julia
julia> using SlackThreads, CairoMakie

julia> thread = SlackThread();

julia> thread("New thread!");

julia> thread("Update", "plot1.png" => scatter(rand(10), rand(10)),
                        "plot2.png" => lines(rand(10)));
```

## Exceptions

SlackThreads does not throw any exceptions when:

* constructing a `SlackThread`
* sending a message to Slack by calling `thread::SlackThread` object

Instead, `@error` and `@warn` logs are used. This is so that `SlackThreads`
can easily be incorporated into long-running computations without the risk
of introducing runtime errors.

SlackThreads can also be used to log exceptions to a thread, via `slack_log_exception`.
For example,

```julia
slack_log_exception(thread) do
    sqrt(-1)
end
```

This *will* rethrow the exception, after logging it (and the stacktrace) to the Slack thread
Any errors encountered while logging the message (e.g. due to network issues or authentication problems) will be caught and emitted as `@error` logs.
