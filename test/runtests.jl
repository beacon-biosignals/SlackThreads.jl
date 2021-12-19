using SlackThreads
using Test
using JET

@testset "SlackThreads.jl" begin
    if VERSION >= v"1.7"
        @testset "JET with args $args" for args in [("hi",), ("hi", "str" => "hello")]
            thread = SlackThread()
            @test_call target_modules = (SlackThreads,) thread(args...)
            @test_call target_modules = (SlackThreads,) mode = :sound broken=true thread(args...)
        end
    end
end
