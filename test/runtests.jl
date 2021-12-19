using SlackThreads
using Test
using JET

status = SlackThreads.CATCH_EXCEPTIONS[]
SlackThreads.CATCH_EXCEPTIONS[] = false
try
    @testset "SlackThreads.jl" begin
        if VERSION >= v"1.7"
            @testset "JET with args $args" for args in [("hi",), ("hi", "str" => "hello")]
                thread = SlackThread()
                @test_call target_modules = (SlackThreads,) thread(args...)
                @test_call target_modules = (SlackThreads,) mode = :sound broken = true thread(args...)
            end
        end
    end
finally
    # reset
    SlackThreads.CATCH_EXCEPTIONS[] = status
end
