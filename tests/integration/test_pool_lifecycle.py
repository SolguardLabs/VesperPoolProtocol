from __future__ import annotations

import boa

from tests.conftest import UNIT, seed_balanced_pool, wad


def test_full_pool_lifecycle_with_monitoring_components(deployed):
    fx = deployed
    seed_balanced_pool(fx)

    with boa.env.prank(fx.accounts.bob):
        fx.pool.swap(fx.token0.address, wad(20_000), 0, fx.accounts.bob)
        fx.pool.addLiquidity(wad(200_000), wad(200_000), 0, fx.accounts.bob)

    summary = fx.lens.poolSummary(fx.pool.address, fx.accounts.bob)
    assert summary[0] == fx.token0.address
    assert summary[1] == fx.token1.address
    assert summary[7] == fx.pool.balanceOf(fx.accounts.bob)
    assert summary[8] == fx.pool.invariant()

    bob_shares = fx.pool.balanceOf(fx.accounts.bob)
    with boa.env.prank(fx.accounts.bob):
        amount0, amount1 = fx.pool.removeLiquidity(bob_shares // 4, 0, 0, fx.accounts.bob)

    assert amount0 > 0
    assert amount1 > 0
    assert fx.pool.totalSupply() > 0


def test_oracle_quotes_match_pool_tokens(deployed):
    fx = deployed
    amount = wad(123)

    assert fx.oracle.quote(fx.token0.address, fx.token1.address, amount) == amount
    ok, deviation, price0, price1 = fx.oracle.pegStatus(fx.token0.address, fx.token1.address)
    assert ok
    assert deviation == 0
    assert price0 == UNIT
    assert price1 == UNIT
