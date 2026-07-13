from __future__ import annotations

import boa

from tests.conftest import PROTOCOL_FEE_SHARE_BPS, SWAP_FEE_BPS, seed_balanced_pool, wad


def test_swap_uses_quote_and_updates_active_reserves(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    quote_out, quoted_fee = fx.pool.quoteSwap(fx.token0.address, wad(10_000))
    before0 = fx.token0.balanceOf(fx.accounts.bob)
    before1 = fx.token1.balanceOf(fx.accounts.bob)

    with boa.env.prank(fx.accounts.bob):
        amount_out = fx.pool.swap(fx.token0.address, wad(10_000), quote_out, fx.accounts.bob)

    assert amount_out == quote_out
    assert quoted_fee == wad(10_000) * SWAP_FEE_BPS // 10_000
    assert fx.token0.balanceOf(fx.accounts.bob) == before0 - wad(10_000)
    assert fx.token1.balanceOf(fx.accounts.bob) == before1 + amount_out
    active0, active1 = fx.pool.activeReserves()
    assert active0 > wad(1_009_000)
    assert active1 < wad(1_000_000)


def test_protocol_fee_accounting_and_claim(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    amount_in = wad(25_000)
    _, fee = fx.pool.quoteSwap(fx.token1.address, amount_in)
    expected_protocol_cut = fee * PROTOCOL_FEE_SHARE_BPS // 10_000

    with boa.env.prank(fx.accounts.bob):
        fx.pool.swap(fx.token1.address, amount_in, 0, fx.accounts.bob)

    fee0, fee1 = fx.pool.protocolFees()
    assert fee0 == 0
    assert fee1 == expected_protocol_cut

    receiver_before = fx.token1.balanceOf(fx.accounts.fee_receiver)
    claimed0, claimed1 = fx.pool.claimProtocolFees(fx.accounts.fee_receiver)

    assert claimed0 == 0
    assert claimed1 == expected_protocol_cut
    assert fx.token1.balanceOf(fx.accounts.fee_receiver) == receiver_before + expected_protocol_cut
    assert fx.pool.protocolFees() == (0, 0)


def test_router_swap_exact_in(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    deadline = boa.env.timestamp + 600
    quote_out, _ = fx.router.quoteSwap(fx.pool.address, fx.token0.address, wad(5_000))
    before = fx.token1.balanceOf(fx.accounts.carol)

    with boa.env.prank(fx.accounts.carol):
        amount_out = fx.router.swapExactIn(
            fx.pool.address,
            fx.token0.address,
            wad(5_000),
            quote_out,
            fx.accounts.carol,
            deadline,
        )

    assert amount_out == quote_out
    assert fx.token1.balanceOf(fx.accounts.carol) == before + amount_out


def test_lens_reports_fee_and_invariant_state(deployed):
    fx = deployed
    seed_balanced_pool(fx)
    with boa.env.prank(fx.accounts.bob):
        fx.pool.swap(fx.token0.address, wad(3_000), 0, fx.accounts.bob)

    swap_fee, protocol_share, penalty_bps, receiver = fx.lens.feeState(fx.pool.address)
    current, last_value, amp, imbalance = fx.lens.invariantState(fx.pool.address)

    assert swap_fee == SWAP_FEE_BPS
    assert protocol_share == PROTOCOL_FEE_SHARE_BPS
    assert penalty_bps > 0
    assert receiver == fx.accounts.fee_receiver
    assert current == last_value
    assert amp > 0
    assert imbalance > 0
