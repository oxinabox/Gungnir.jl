using Gungnir
using Test
using InteractiveUtils

#@testset "Gungnir.jl" begin

#@testset "basic numbers" begin
    plus1_closure = (function()
        x=1
        return ()->x+1
    end)()
    
    plus_1_stabbed = specialize_closure(plus1_closure)
    

    @test plus_1_stabbed() == plus1_closure()


#end



#end  # outer testset
