using Test
using EclatFIM

@testset "Fashion TC6 spatial encoding" begin
    checks = EclatFIM.FashionTCSpatial.run_unit_checks!()
    @test all(==("PASS"), values(checks))
end
