from __future__ import annotations

import boa

from tests.conftest import ROOT, seed_balanced_pool, wad


def test_scenario_lens_reports_reserve_and_peg_stress(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    lens = boa.load(str(ROOT / "src" / "monitoring" / "VesperScenarioLens.vy"))

    result = lens.scenario(fx.pool.address, fx.oracle.address, 0, 0, 0, 0)
    assert result[0] == wad(1_000_000)
    assert result[1] == wad(1_000_000)
    assert result[2] == wad(2_000_000)
    assert result[3] == wad(2_000_000)
    assert result[4] == 0
    assert result[5] == 0
    assert result[6] > 0

    stressed = lens.scenario(fx.pool.address, fx.oracle.address, wad(100_000), 0, 1_000, 0)
    assert stressed[0] == wad(900_000)
    assert stressed[1] == wad(1_000_000)
    assert stressed[2] == wad(2_000_000)
    assert stressed[3] == wad(1_810_000)
    assert stressed[4] == 950
    assert stressed[5] == wad(190_000) * 10_000 // wad(1_810_000)


def test_scenario_lens_rejects_invalid_shock_and_excess_withdrawal(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    lens = boa.load(str(ROOT / "src" / "monitoring" / "VesperScenarioLens.vy"))

    with boa.reverts("SHOCK"):
        lens.scenario(fx.pool.address, fx.oracle.address, 0, 0, 10_001, 0)
    with boa.reverts("RESERVE"):
        lens.scenario(fx.pool.address, fx.oracle.address, wad(1_000_001), 0, 0, 0)
