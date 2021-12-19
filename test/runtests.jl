using SlackThreads
using Test
using JET
using Mocking
using JSON3
Mocking.activate()

function readchomp_reply_patch(reply)
    p = @patch Base.readchomp(cmd) = JSON3.write(reply)
    return p
end

function readchomp_input_patch(check)
    p = @patch function Base.readchomp(cmd)
        check(cmd)
        return JSON3.write(Dict("ok" => true, "file" => Dict("permalink" => "LINK")))
    end
    return p
end

function JET_tests()
    @testset "JET with args $args" for args in [("hi",), ("hi", "str" => "hello"),
                                                ("hi", "str.txt" => "hello", "a" => "b")]
        thread = SlackThread()
        @test_call target_modules = (SlackThreads,) thread(args...)
        @test_call target_modules = (SlackThreads,) mode = :sound broken = true thread(args...)
    end
end

# These can be run in both paths (with exceptions or without),
# since they don't involve throwing exceptions.
function tests_without_errors()
    withenv("SLACK_TOKEN" => "hi", "SLACK_CHANNEL" => nothing) do
        thread = (@test_logs (:warn, r"Channel") SlackThread())
        @test thread.ts === nothing
        @test thread.channel === nothing
    end

    withenv("SLACK_TOKEN" => "hi", "SLACK_CHANNEL" => "bye") do
        thread = SlackThread()
        Mocking.apply(readchomp_reply_patch(Dict("ok" => true, "ts" => "abc"))) do
            @test thread("hi").ok == true
            @test thread.ts == "abc"
        end

        hi_patch = readchomp_input_patch() do cmd
            # Just a reference test; we don't really want to hit up the Slack API
            # from CI here, so let's just check the curl query is one that works
            # from manual testing.
            # This could break for innocuous reasons; in that case, just update it here
            # or find a better test.
            @test cmd ==
                  `curl -s -X POST -H 'Authorization: Bearer hi' -H 'Content-type: application/json; charset=utf-8' --data '{"channel":"bye","thread_ts":"abc","text":"hi"}' https://slack.com/api/chat.postMessage`
        end

        Mocking.apply(hi_patch) do
            @test thread("hi").ok == true
        end

        Mocking.apply(readchomp_reply_patch(Dict("ok" => true))) do
            @test thread("bye").ok == true
            # `ts` doesn't change
            @test thread.ts == "abc"
        end

        Mocking.apply(readchomp_reply_patch(Dict("ok" => true,
                                                 "file" => Dict("permalink" => "LINK")))) do
            @test thread("hi again", "file.txt" => "this is a string",
                         "file2.txt" => "abc").ok == true
        end

        file_patch = readchomp_input_patch() do cmd
            str = string(cmd)
            # Either we're uploading the two files...
            case1 = contains(str, "-F file=@") &&
                    (contains(str, "file.txt") || contains(str, "file2.txt"))
            # Or sending the message with the links
            case2 = contains(str, "hi again<LINK| ><LINK| >")
            @test case1 ⊻ case2
        end

        Mocking.apply(file_patch) do
            @test thread("hi again", "file.txt" => "this is a string",
                         "file2.txt" => "abc").ok == true
        end
    end
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
        VERSION >= v"1.7" && JET_tests()

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

                Mocking.apply(readchomp_reply_patch(Dict("ok" => true, "ts" => "x"))) do
                    @test thread("bye").ok == true
                    # `ts` still doesn't change
                    @test thread.ts == "abc"

                    @test thread("hi again", "file.txt" => "this is a string").ok == true

                    # We didn't pass a `file` back in our reply
                    @test_throws KeyError thread("hi again",
                                                 "file.txt" => "this is a string",
                                                 "file2.txt" => "abc")
                end

                Mocking.apply(readchomp_reply_patch(Dict("ok" => false, "error" => "no"))) do
                    @test_throws SlackThreads.SlackError("no") thread("bye")
                end

                Mocking.apply(readchomp_reply_patch(Dict("ok" => false))) do
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

                Mocking.apply(readchomp_reply_patch(Dict("ok" => true, "ts" => "x"))) do
                    @test thread("bye").ok == true
                    # `ts` still doesn't change
                    @test thread.ts == "abc"

                    @test thread("hi again", "file.txt" => "this is a string").ok == true

                    # We didn't pass a `file` back in our reply
                    msg = "Error when attempting to send message to Slack thread"
                    result = @test_logs (:error, msg) thread("hi again",
                                                             "file.txt" => "this is a string",
                                                             "file2.txt" => "abc")
                    @test result === nothing
                end

                Mocking.apply(readchomp_reply_patch(Dict("ok" => false, "error" => "no"))) do
                    @test (@test_logs (:error, r"Slack API") thread("bye")) === nothing
                end

                Mocking.apply(readchomp_reply_patch(Dict("ok" => false))) do
                    @test (@test_logs (:error, r"Slack API") thread("bye")) === nothing
                end
            end
        end
    finally
        # reset
        SlackThreads.CATCH_EXCEPTIONS[] = status
    end
end
