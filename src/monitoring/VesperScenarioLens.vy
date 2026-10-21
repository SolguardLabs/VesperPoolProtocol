# @version 0.4.3

"""
Read-only reserve and peg stress scenarios for two-asset pools.
Values use the oracle's 1e18 price scale and the token's smallest unit.
The result is an accounting sensitivity, not an execution authorization.
"""

interface Pool:
    def token0() -> address: view
    def token1() -> address: view
    def activeReserves() -> (uint256, uint256): view

interface Oracle:
    def latestPrice(asset: address) -> (uint256, uint256, uint256, bool): view


BPS: constant(uint256) = 10_000
PRICE_SCALE: constant(uint256) = 10 ** 18


@internal
@pure
def _abs_diff(a: uint256, b: uint256) -> uint256:
    if a >= b:
        return a - b
    return b - a


@external
@view
def scenario(
    _pool: address,
    _oracle: address,
    _withdraw0: uint256,
    _withdraw1: uint256,
    _shock0_bps: uint256,
    _shock1_bps: uint256
) -> (uint256, uint256, uint256, uint256, uint256, uint256, uint256):
    assert _pool != empty(address) and _oracle != empty(address), "ADDRESS"
    assert _shock0_bps <= BPS and _shock1_bps <= BPS, "SHOCK"

    reserve0: uint256 = 0
    reserve1: uint256 = 0
    reserve0, reserve1 = staticcall Pool(_pool).activeReserves()
    assert _withdraw0 <= reserve0 and _withdraw1 <= reserve1, "RESERVE"

    price0: uint256 = 0
    price1: uint256 = 0
    updated0: uint256 = 0
    updated1: uint256 = 0
    round0: uint256 = 0
    round1: uint256 = 0
    fresh0: bool = False
    fresh1: bool = False
    price0, updated0, round0, fresh0 = staticcall Oracle(_oracle).latestPrice(staticcall Pool(_pool).token0())
    price1, updated1, round1, fresh1 = staticcall Oracle(_oracle).latestPrice(staticcall Pool(_pool).token1())
    assert fresh0 and fresh1 and price0 > 0 and price1 > 0, "PRICE"
    assert round0 > 0 and round1 > 0, "ROUND"

    remaining0: uint256 = reserve0 - _withdraw0
    remaining1: uint256 = reserve1 - _withdraw1
    stressed0: uint256 = price0 * (BPS - _shock0_bps) // BPS
    stressed1: uint256 = price1 * (BPS - _shock1_bps) // BPS
    value_before: uint256 = reserve0 * price0 // PRICE_SCALE + reserve1 * price1 // PRICE_SCALE
    value0_after: uint256 = remaining0 * stressed0 // PRICE_SCALE
    value1_after: uint256 = remaining1 * stressed1 // PRICE_SCALE
    value_after: uint256 = value0_after + value1_after

    loss_bps: uint256 = 0
    if value_before > 0 and value_after < value_before:
        loss_bps = (value_before - value_after) * BPS // value_before

    concentration_bps: uint256 = 0
    if value_after > 0:
        concentration_bps = self._abs_diff(value0_after, value1_after) * BPS // value_after

    oldest_update: uint256 = updated0
    if updated1 < oldest_update:
        oldest_update = updated1
    return remaining0, remaining1, value_before, value_after, loss_bps, concentration_bps, oldest_update
