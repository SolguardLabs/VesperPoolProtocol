from __future__ import annotations

import boa

from tests.conftest import seed_balanced_pool, token_balances, wad


def test_imbalanced_remove_accepts_quoted_bound_and_transfers_requested_assets(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    with boa.env.prank(fx.accounts.bob):
        fx.pool.swap(fx.token0.address, wad(40_000), 0, fx.accounts.bob)

    amount0 = wad(5_000)
    amount1 = wad(15_000)
    max_shares, quoted_penalty = fx.pool.quoteRemoveLiquidityImbalanced(amount0, amount1)
    before0, before1 = token_balances(fx, fx.accounts.alice)
    before_shares = fx.pool.balanceOf(fx.accounts.alice)

    with boa.env.prank(fx.accounts.alice):
        shares_used = fx.pool.removeLiquidityImbalanced(amount0, amount1, max_shares, fx.accounts.alice)

    after0, after1 = token_balances(fx, fx.accounts.alice)
    assert quoted_penalty > 0
    assert shares_used <= max_shares
    assert fx.pool.balanceOf(fx.accounts.alice) == before_shares - shares_used
    assert after0 == before0 + amount0
    assert after1 == before1 + amount1


def test_imbalanced_remove_rejects_more_than_active_reserve(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    active0, _ = fx.pool.activeReserves()

    with boa.reverts("LIQUIDITY"):
        with boa.env.prank(fx.accounts.alice):
            fx.pool.removeLiquidityImbalanced(active0, 0, fx.pool.balanceOf(fx.accounts.alice), fx.accounts.alice)


def test_imbalanced_remove_through_router_refunds_unused_shares(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    deadline = boa.env.timestamp + 600
    amount0 = wad(7_500)
    amount1 = wad(2_500)
    max_shares, _ = fx.router.quoteRemoveLiquidityImbalanced(fx.pool.address, amount0, amount1)
    before_shares = fx.pool.balanceOf(fx.accounts.alice)

    with boa.env.prank(fx.accounts.alice):
        shares_used = fx.router.removeLiquidityImbalanced(
            fx.pool.address,
            amount0,
            amount1,
            max_shares,
            fx.accounts.alice,
            deadline,
        )

    assert shares_used <= max_shares
    assert fx.pool.balanceOf(fx.accounts.alice) == before_shares - shares_used


def test_balanced_and_imbalanced_paths_keep_protocol_fees_separate(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    with boa.env.prank(fx.accounts.bob):
        fx.pool.swap(fx.token1.address, wad(12_000), 0, fx.accounts.bob)

    fee_before = fx.pool.protocolFees()
    shares = fx.pool.balanceOf(fx.accounts.alice) // 10
    with boa.env.prank(fx.accounts.alice):
        fx.pool.removeLiquidity(shares, 0, 0, fx.accounts.alice)
    with boa.env.prank(fx.accounts.alice):
        fx.pool.removeLiquidityImbalanced(
            wad(1_000),
            wad(3_000),
            fx.pool.balanceOf(fx.accounts.alice),
            fx.accounts.alice,
        )

    assert fx.pool.protocolFees() == fee_before
