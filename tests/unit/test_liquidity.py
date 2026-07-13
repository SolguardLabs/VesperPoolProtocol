from __future__ import annotations

import boa

from tests.conftest import UNIT, seed_balanced_pool, wad


def test_initial_liquidity_mints_lp_shares_and_tracks_reserves(deployed):
    fx = deployed
    quoted = fx.pool.quoteAddLiquidity(wad(1_000_000), wad(1_000_000))

    shares = seed_balanced_pool(fx)

    assert shares == quoted
    assert fx.pool.balanceOf(fx.accounts.alice) == shares
    assert fx.pool.totalSupply() == shares + 1_000
    assert fx.pool.reserves() == (wad(1_000_000), wad(1_000_000))
    assert fx.pool.activeReserves() == (wad(1_000_000), wad(1_000_000))
    assert fx.pool.invariant() > wad(1_000_000)


def test_second_lp_receives_proportional_shares(deployed):
    fx = deployed
    first = seed_balanced_pool(fx)

    quote = fx.pool.quoteAddLiquidity(wad(250_000), wad(250_000))
    with boa.env.prank(fx.accounts.bob):
        minted = fx.pool.addLiquidity(wad(250_000), wad(250_000), quote, fx.accounts.bob)

    assert minted == quote
    assert minted * 4 >= first - 4_000
    assert fx.pool.balanceOf(fx.accounts.bob) == minted
    assert fx.pool.reserves() == (wad(1_250_000), wad(1_250_000))


def test_balanced_remove_returns_proportional_assets(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    shares = fx.pool.balanceOf(fx.accounts.alice) // 5
    quoted0, quoted1 = fx.pool.quoteRemoveLiquidity(shares)

    before0 = fx.token0.balanceOf(fx.accounts.alice)
    before1 = fx.token1.balanceOf(fx.accounts.alice)
    with boa.env.prank(fx.accounts.alice):
        amount0, amount1 = fx.pool.removeLiquidity(shares, quoted0, quoted1, fx.accounts.alice)

    assert amount0 == quoted0
    assert amount1 == quoted1
    assert fx.token0.balanceOf(fx.accounts.alice) == before0 + amount0
    assert fx.token1.balanceOf(fx.accounts.alice) == before1 + amount1
    assert fx.pool.balanceOf(fx.accounts.alice) > 0


def test_router_can_add_and_remove_balanced_liquidity(deployed):
    fx = deployed
    deadline = boa.env.timestamp + 600

    with boa.env.prank(fx.accounts.bob):
        shares = fx.router.addLiquidity(
            fx.pool.address,
            wad(100_000),
            wad(100_000),
            0,
            fx.accounts.bob,
            deadline,
        )

    assert fx.pool.balanceOf(fx.accounts.bob) == shares

    remove_shares = shares // 2
    quote0, quote1 = fx.router.quoteRemoveLiquidity(fx.pool.address, remove_shares)
    with boa.env.prank(fx.accounts.bob):
        amount0, amount1 = fx.router.removeLiquidity(
            fx.pool.address,
            remove_shares,
            quote0,
            quote1,
            fx.accounts.bob,
            deadline,
        )

    assert amount0 == quote0
    assert amount1 == quote1
    assert fx.pool.balanceOf(fx.accounts.bob) == shares - remove_shares


def test_lp_preview_matches_share_value(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    shares, amount0, amount1 = fx.pool.lpPreview(fx.accounts.alice)

    assert shares == fx.pool.balanceOf(fx.accounts.alice)
    assert amount0 > wad(999_000)
    assert amount1 > wad(999_000)
    assert abs(amount0 - amount1) <= UNIT
