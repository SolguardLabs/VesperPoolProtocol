# @version 0.4.3

interface Pool:
    def token0() -> address: view
    def token1() -> address: view
    def activeReserves() -> (uint256, uint256): view
    def reserves() -> (uint256, uint256): view
    def protocolFees() -> (uint256, uint256): view
    def totalSupply() -> uint256: view
    def invariant() -> uint256: view
    def spotImbalance() -> uint256: view
    def quoteSwap(token_in: address, amount_in: uint256) -> (uint256, uint256): view
    def quoteRemoveLiquidity(shares: uint256) -> (uint256, uint256): view
    def quoteRemoveLiquidityImbalanced(amount0: uint256, amount1: uint256) -> (uint256, uint256): view

interface Oracle:
    def latestPrice(asset: address) -> (uint256, uint256, uint256, bool): view
    def pegStatus(asset0: address, asset1: address) -> (bool, uint256, uint256, uint256): view
    def quote(base: address, quote: address, amount: uint256) -> uint256: view


BPS: constant(uint256) = 10_000
PRICE_SCALE: constant(uint256) = 10 ** 18


@internal
@pure
def _abs_diff(a: uint256, b: uint256) -> uint256:
    if a > b:
        return a - b
    return b - a


@internal
@pure
def _min(a: uint256, b: uint256) -> uint256:
    if a < b:
        return a
    return b


@external
@view
def reserveWeights(_pool: address) -> (uint256, uint256):
    active0: uint256 = 0
    active1: uint256 = 0
    active0, active1 = staticcall Pool(_pool).activeReserves()
    total: uint256 = active0 + active1
    if total == 0:
        return 0, 0
    return active0 * BPS // total, active1 * BPS // total


@external
@view
def feeCoverage(_pool: address) -> (uint256, uint256):
    reserve0: uint256 = 0
    reserve1: uint256 = 0
    fee0: uint256 = 0
    fee1: uint256 = 0
    reserve0, reserve1 = staticcall Pool(_pool).reserves()
    fee0, fee1 = staticcall Pool(_pool).protocolFees()
    coverage0: uint256 = 0
    coverage1: uint256 = 0
    if reserve0 > 0:
        coverage0 = fee0 * BPS // reserve0
    if reserve1 > 0:
        coverage1 = fee1 * BPS // reserve1
    return coverage0, coverage1


@external
@view
def lpExitValue(_pool: address, _shares: uint256, _oracle: address) -> (uint256, uint256, uint256):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    amount0: uint256 = 0
    amount1: uint256 = 0
    amount0, amount1 = staticcall Pool(_pool).quoteRemoveLiquidity(_shares)
    value1: uint256 = staticcall Oracle(_oracle).quote(token0, token1, amount0) + amount1
    return amount0, amount1, value1


@external
@view
def swapImpact(_pool: address, _token_in: address, _amount_in: uint256, _oracle: address) -> (uint256, uint256, uint256):
    amount_out: uint256 = 0
    fee: uint256 = 0
    amount_out, fee = staticcall Pool(_pool).quoteSwap(_token_in, _amount_in)
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    fair_out: uint256 = 0
    if _token_in == token0:
        fair_out = staticcall Oracle(_oracle).quote(token0, token1, _amount_in)
    else:
        fair_out = staticcall Oracle(_oracle).quote(token1, token0, _amount_in)
    impact_bps: uint256 = 0
    if fair_out > amount_out:
        impact_bps = (fair_out - amount_out) * BPS // fair_out
    return amount_out, fee, impact_bps


@external
@view
def imbalancedExitCost(_pool: address, _amount0: uint256, _amount1: uint256, _oracle: address) -> (uint256, uint256, uint256):
    shares: uint256 = 0
    penalty: uint256 = 0
    shares, penalty = staticcall Pool(_pool).quoteRemoveLiquidityImbalanced(_amount0, _amount1)
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    output_value1: uint256 = staticcall Oracle(_oracle).quote(token0, token1, _amount0) + _amount1
    return shares, penalty, output_value1


@external
@view
def pegAwareHealth(_pool: address, _oracle: address) -> (bool, bool, uint256, uint256):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    peg_ok: bool = False
    deviation: uint256 = 0
    price0: uint256 = 0
    price1: uint256 = 0
    peg_ok, deviation, price0, price1 = staticcall Oracle(_oracle).pegStatus(token0, token1)
    imbalance: uint256 = staticcall Pool(_pool).spotImbalance()
    reserve_ok: bool = imbalance <= 2_500
    return peg_ok, reserve_ok, deviation, imbalance


@external
@view
def scarcitySide(_pool: address) -> (address, uint256):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    active0: uint256 = 0
    active1: uint256 = 0
    active0, active1 = staticcall Pool(_pool).activeReserves()
    if active0 <= active1:
        return token0, active0
    return token1, active1


@external
@view
def liquidityBand(_pool: address) -> (uint256, uint256, uint256):
    active0: uint256 = 0
    active1: uint256 = 0
    active0, active1 = staticcall Pool(_pool).activeReserves()
    low: uint256 = self._min(active0, active1)
    high: uint256 = active0
    if active1 > high:
        high = active1
    width_bps: uint256 = 0
    if high > 0:
        width_bps = (high - low) * BPS // high
    return low, high, width_bps


@external
@view
def rebalanceHint(_pool: address) -> (address, uint256, uint256):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    active0: uint256 = 0
    active1: uint256 = 0
    active0, active1 = staticcall Pool(_pool).activeReserves()
    if active0 == active1:
        return empty(address), 0, 0
    diff: uint256 = self._abs_diff(active0, active1)
    if active0 > active1:
        return token1, diff // 2, staticcall Pool(_pool).spotImbalance()
    return token0, diff // 2, staticcall Pool(_pool).spotImbalance()


@external
@view
def withdrawalHeadroom(_pool: address, _shares: uint256) -> (uint256, uint256, uint256):
    amount0: uint256 = 0
    amount1: uint256 = 0
    amount0, amount1 = staticcall Pool(_pool).quoteRemoveLiquidity(_shares)
    active0: uint256 = 0
    active1: uint256 = 0
    active0, active1 = staticcall Pool(_pool).activeReserves()
    headroom_bps: uint256 = BPS
    if active0 > 0 and active1 > 0:
        h0: uint256 = (active0 - amount0) * BPS // active0
        h1: uint256 = (active1 - amount1) * BPS // active1
        headroom_bps = self._min(h0, h1)
    return amount0, amount1, headroom_bps


@external
@view
def dashboard(_pool: address, _oracle: address) -> (
    address,
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    bool,
    uint256,
    uint256,
    uint256
):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    active0: uint256 = 0
    active1: uint256 = 0
    active0, active1 = staticcall Pool(_pool).activeReserves()
    peg_ok: bool = False
    deviation: uint256 = 0
    price0: uint256 = 0
    price1: uint256 = 0
    peg_ok, deviation, price0, price1 = staticcall Oracle(_oracle).pegStatus(token0, token1)
    return (
        token0,
        token1,
        active0,
        active1,
        staticcall Pool(_pool).totalSupply(),
        staticcall Pool(_pool).invariant(),
        peg_ok,
        deviation,
        staticcall Pool(_pool).spotImbalance(),
        self._abs_diff(price0, price1)
    )
