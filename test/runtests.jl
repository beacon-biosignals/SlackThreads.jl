using SlackThreads
using Test
using JET
using Mocking
using HTTP
using JSON3
using CairoMakie
using Logging
using Aqua

Mocking.activate()

const OK_REPLY = Dict("ok" => true)
const FILE_OK_REPLY = Dict("ok" => true, "file" => Dict("permalink" => "LINK"))

function request_reply_patch(reply, count=Ref(0))
    p = @patch function HTTP.post(api, headers, body)
        count[] += 1
        return (; body=JSON3.write(reply))
    end
    return p
end

function request_input_patch(check)
    p = @patch function HTTP.post(api, headers, body)
        check(api, headers, body)
        return (; body=JSON3.write(FILE_OK_REPLY))
    end
    return p
end

function JET_tests(ThreadType; sound_broken=false)
    @testset "JET with args $args" for args in [("hi",), ("hi", "str" => "hello"),
                                                ("hi", "str.txt" => "hello", "a" => "b")]
        thread = withenv(() -> ThreadType(), "SLACK_CHANNEL" => "hi")

        # `@test_call` needs JET v0.5, which needs Julia 1.7
        # We need `@static` here since macroexpansion happens before runtime,
        # i.e. a runtime check is not enough.
        @static if VERSION >= v"1.7"
            @test_call target_modules = (SlackThreads,) thread(args...)
            @test_call target_modules = (SlackThreads,) mode = :sound broken = sound_broken thread(args...)
        end
    end
end

# These can be run in both paths (with exceptions or without),
# since they don't involve throwing exceptions.
function tests_without_errors()
    withenv("SLACK_TOKEN" => "hi", "SLACK_CHANNEL" => nothing) do
        thread = (@test_logs (:warn, r"channel") SlackThread())
        @test thread.ts === nothing
        @test thread.channel === nothing
    end

    withenv("SLACK_TOKEN" => "hi", "SLACK_CHANNEL" => "bye") do
        thread = SlackThread()
        Mocking.apply(request_reply_patch(Dict("ok" => true, "ts" => "abc"))) do
            @test thread("hi").ok == true
            @test thread.ts == "abc"
        end

        @testset "copyto!" begin
            t = SlackThread()
            copyto!(t, (; channel="c", ts="123"))
            @test t.channel == "c"
            @test t.ts == "123"

            # Test we can roundtrip through JSON,
            # then update an existing SlackThread with `copyto!`
            # (since this can be a useful thing to do)
            json = JSON3.write(t)
            new_thread = SlackThread()
            copyto!(new_thread, JSON3.read(json))
            @test new_thread.channel == "c"
            @test new_thread.ts == "123"
        end

        hi_patch = request_input_patch() do api, headers, body
            # Just a reference test; we don't really want to hit up the Slack API
            # from CI here, so let's just check the HTTP.post query is one that works
            # from manual testing.
            # This could break for innocuous reasons; in that case, just update it here
            # or find a better test.
            # Currently, this is the only test that checks that the requests we are making
            # are reasonable; we could emit nonsense and all the other tests would pass!
            @test api == "https://slack.com/api/chat.postMessage"
            @test headers == ["Authorization" => "Bearer hi",
                              "Content-type" => "application/json; charset=utf-8"]
            @test body == raw"""{"channel":"bye","thread_ts":"abc","text":"hi"}"""
        end

        Mocking.apply(hi_patch) do
            @test thread("hi").ok == true
        end

        option_patch = request_input_patch() do api, headers, body
            # Another reference test
            @test api == "https://slack.com/api/chat.postMessage"
            @test headers == ["Authorization" => "Bearer hi",
                              "Content-type" => "application/json; charset=utf-8"]
            @test body ==
                  raw"""{"channel":"bye","thread_ts":"abc","link_names":true,"text":"hi"}"""
        end

        Mocking.apply(option_patch) do
            @test thread("hi"; link_names=true).ok == true
        end

        count = Ref(0)
        Mocking.apply(request_reply_patch(Dict("ok" => true, "ts" => "123",
                                               "file" => Dict("permalink" => "LINK")),
                                          count)) do
            t = SlackThread()
            @test t("bye", "file.txt" => "hi").ok == true
            # `ts` is correctly set
            @test t.ts == "123"
        end
        # we need the general fallback when doing 1 attachment and starting a thread,
        # therefore we get 2 API calls
        @test count[] == 2

        count = Ref(0)
        Mocking.apply(request_reply_patch(OK_REPLY, count)) do
            @test thread("bye").ok == true
            # `ts` doesn't change
            @test thread.ts == "abc"
        end
        @test count[] == 1

        count = Ref(0)
        Mocking.apply(request_reply_patch(FILE_OK_REPLY, count)) do
            @test thread("hi again", "file.txt" => "this is a string",
                         "file2.txt" => "abc").ok == true
        end
        @test count[] == 3 # two file uploads plus the message

        file_patch = request_input_patch() do api, headers, body
            # Either we're uploading the two files...
            # (Form.data contains 2x elements for each form item: header + data)
            case1 = body isa HTTP.Forms.Form &&
                    body.data[2] isa IOStream &&
                    occursin(r"file2?.txt", body.data[2].name)
            # Or sending the message with the links
            case2 = body isa String && contains(body, "hi again<LINK| ><LINK| >")
            @test case1 ⊻ case2
        end

        Mocking.apply(file_patch) do
            @test thread("hi again", "file.txt" => "this is a string",
                         "file2.txt" => "abc").ok == true
        end

        count = Ref(0)
        Mocking.apply(request_reply_patch(OK_REPLY, count)) do
            @test_throws DomainError slack_log_exception(thread) do
                return sqrt(-1)
            end
        end
        @test count[] == 1

        count = Ref(0)
        Mocking.apply(request_reply_patch(OK_REPLY, count)) do
            try
                sqrt(-1)
            catch e
                slack_log_exception(thread, e, catch_backtrace())
            end
        end
        @test count[] == 1

        # Suppress annoying "No strict ticks found" logging messages
        plt1 = with_logger(NullLogger()) do
            return scatter([1.0f0, 2.0f0, 3.0f0], [0.5f0, 4.0f0, 6.0f0])
        end
        plt2 = with_logger(NullLogger()) do
            return scatter(1:10, 1:10)
        end
        Mocking.apply(request_reply_patch(FILE_OK_REPLY)) do
            @test thread("hi", "plot.png" => plt1).ok == true
            @test thread.ts == "abc"

            @test thread("hi", "plot.png" => plt1, "plot2.png" => plt2).ok == true
        end
    end
end

@testset "SlackThreads" begin
    @testset "Aqua" begin
        Aqua.test_all(SlackThreads; ambiguities=false)
    end

    @testset "Utilities" begin
        message_count_suffix = (i, n) -> ""
        messages = SlackThreads.combine_texts(["abcdef", "abc"]; max_length=1,
                                              message_count_suffix)
        @test messages == ["abcdef", "abc"] # 2 messages

        messages = SlackThreads.combine_texts(["abcdef", "abcdef", "a", "b"]; max_length=2,
                                              message_count_suffix)
        @test messages == ["abcdef", "abcdef", "ab"] # 3 messages

        messages = SlackThreads.combine_texts(["abcdef", "abc", "d"]; max_length=4,
                                              message_count_suffix)
        @test messages == ["abcdef", "abcd"]  # can combine last two

        messages = SlackThreads.combine_texts(["d", "abcdef", "abc"]; max_length=4,
                                              message_count_suffix)
        @test messages == ["d", "abcdef", "abc"] # cannot combine anything

        vals = (x for x in ("d", "x", "abcdef", "abc")) # test iterator
        messages = SlackThreads.combine_texts(vals; max_length=4, message_count_suffix)
        @test messages == ["dx", "abcdef", "abc"] # can combine first two

        # Edge case: 1 message
        for max_length in (0, 1, 5)
            messages = SlackThreads.combine_texts(["a"]; max_length, message_count_suffix)
            @test messages == ["a"]
        end

        # Test `message_count_suffix`
        messages = SlackThreads.combine_texts(["a"]; message_count_suffix=(i, n) -> "$i/$n")
        @test messages == ["a1/1"]
    end

    @testset "DummyThreads" begin
        JET_tests(DummyThread)
        d = DummyThread()
        d("hi")
        @test d.logged[1] isa SlackCallRecord
        @test d.logged[1].args == tuple("hi")
        @test d.logged[1].call == :DummyThread
        @test isempty(d.logged[1].kwargs)
        d("hi", "a" => "b")
        @test d.logged[2].args == ("hi", "a" => "b")
        try
            slack_log_exception(d) do
                return sqrt(-1)
            end
        catch DomainError
        end
        @test contains(d.logged[3].args[1], ":alert: Error occured! :alert:")
        @test d.logged[3].call == :send_exception_message

        d("bye"; unfurl_media=true)
        @test d.logged[4].call == :DummyThread
        @test d.logged[4].args == tuple("bye")
        @test d.logged[4].kwargs == (; unfurl_media=true)

        # Properties
        @test propertynames(d) == (:channel, :ts, :logged)
        d.channel = "hi" # no error
        d.ts = "bye" # no error
        @test_throws ErrorException("type DummyThread has no field xyz") d.xyz
        @test_throws MethodError d.channel = 1
        @test_throws MethodError d.ts = 1
        @test d.channel === nothing
        @test d.ts === nothing

        # (de)-Serialization
        roundtrip = JSON3.read(JSON3.write(d), DummyThread)
        @test roundtrip.logged[1] == d.logged[1]
        @test roundtrip.logged[2].kwargs == d.logged[2].kwargs
        # for some reason, JSON3 deserializes a Pair to a Dict (which is a collection of Pairs)
        @test only(roundtrip.logged[2].args[2]) == d.logged[2].args[2]
        @test roundtrip.logged[3] == d.logged[3]
    end

    # Now we test with `SlackThreads.CATCH_EXCEPTIONS[] = false`, i.e.
    # with throwing exceptions. This option exists only for testing, really.
    # The point is we don't want our tests to "pass" while logging exceptions
    # all over the place. If we disable our special "log exceptions instead of throwing"
    # code, do we still pass our tests?
    @testset "With exceptions" begin
        status = SlackThreads.CATCH_EXCEPTIONS[]
        SlackThreads.CATCH_EXCEPTIONS[] = false
        try
            JET_tests(SlackThread; sound_broken=true)

            @testset "Non-throwing tests" begin
                tests_without_errors()
            end

            @testset "`SlackThread` constructor exceptions" begin
                @test_throws MethodError SlackThread(1)
            end

            @testset "`thread` message exceptions" begin
                withenv("SLACK_TOKEN" => "hi", "SLACK_CHANNEL" => "bye") do
                    thread = SlackThread()
                    thread.ts = "abc"

                    Mocking.apply(request_reply_patch(Dict("ok" => true, "ts" => "x"))) do
                        @test thread("bye").ok == true
                        # `ts` still doesn't change
                        @test thread.ts == "abc"

                        @test thread("hi again", "file.txt" => "this is a string").ok ==
                              true

                        # We didn't pass a `file` back in our reply
                        @test_throws KeyError thread("hi again",
                                                     "file.txt" => "this is a string",
                                                     "file2.txt" => "abc")
                    end

                    Mocking.apply(request_reply_patch(Dict("ok" => false, "error" => "no"))) do
                        @test_throws SlackThreads.SlackError("no") thread("bye")
                    end

                    Mocking.apply(request_reply_patch(Dict("ok" => false))) do
                        @test_throws SlackThreads.SlackError("No error field returned") thread("bye")
                    end
                end
            end

        finally
            # reset
            SlackThreads.CATCH_EXCEPTIONS[] = status
        end
    end

    # Here, we check that our special "exceptions as logs" machinery works
    # correctly and emits logs.
    @testset "Exceptions as logs" begin
        status = SlackThreads.CATCH_EXCEPTIONS[]
        SlackThreads.CATCH_EXCEPTIONS[] = true
        try
            @testset "Non-throwing tests" begin
                tests_without_errors()
            end

            @testset "`SlackThread` constructor exceptions" begin
                msg = "Error when constructing `SlackThread`"
                thread = (@test_logs (:error, msg) SlackThread(1))
                @test thread.ts === nothing
                @test thread.channel === nothing
            end

            @testset "`thread` message exceptions" begin
                withenv("SLACK_TOKEN" => "hi", "SLACK_CHANNEL" => "bye") do
                    thread = SlackThread()
                    thread.ts = "abc"

                    Mocking.apply(request_reply_patch(Dict("ok" => true, "ts" => "x"))) do
                        @test thread("bye").ok == true
                        # `ts` still doesn't change
                        @test thread.ts == "abc"

                        @test thread("hi again", "file.txt" => "this is a string").ok ==
                              true

                        # We didn't pass a `file` back in our reply
                        msg = "Error when attempting to send message to Slack thread"
                        result = @test_logs (:error, msg) thread("hi again",
                                                                 "file.txt" => "this is a string",
                                                                 "file2.txt" => "abc")
                        @test result === nothing
                    end

                    Mocking.apply(request_reply_patch(Dict("ok" => false, "error" => "no"))) do
                        @test (@test_logs (:error, r"Slack API") thread("bye")) === nothing
                    end

                    Mocking.apply(request_reply_patch(Dict("ok" => false))) do
                        @test (@test_logs (:error, r"Slack API") thread("bye")) === nothing
                    end

                    count = Ref(0)
                    Mocking.apply(request_reply_patch(Dict("ok" => false), count)) do
                        @test_logs (:error, "Error reported by Slack API") begin
                            @test_throws DomainError slack_log_exception(thread) do
                                return sqrt(-1)
                            end
                        end
                    end
                    @test count[] == 1
                end
            end
        finally
            # reset
            SlackThreads.CATCH_EXCEPTIONS[] = status
        end
    end
end
