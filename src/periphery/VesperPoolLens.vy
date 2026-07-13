# @version 0.4.3

interface Pool:
    def token0() -> address: view
    def token1() -> address: view
    def reserves() -> (uint256, uint256): view
    def activeReserves() -> (uint256, uint256): view
    def protocolFees() -> (uint256, uint256): view
    def totalSupply() -> uint256: view
    def balanceOf(owner: address) -> uint256: view
    def allowance(owner: address, spender: address) -> uint256: view
    def invariant() -> uint256: view
    def lastInvariant() -> uint256: view
    def amp() -> uint256: view
    def spotImbalance() -> uint256: view
    def feeState() -> (uint256, uint256, uint256, address): view
    def poolState() -> (uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool): view
    def lpPreview(owner: address) -> (uint256, uint256, uint256): view
    def quoteSwap(token_in: address, amount_in: uint256) -> (uint256, uint256): view
    def quoteAddLiquidity(amount0: uint256, amount1: uint256) -> uint256: view
    def quoteRemoveLiquidity(shares: uint256) -> (uint256, uint256): view
    def quoteRemoveLiquidityImbalanced(amount0: uint256, amount1: uint256) -> (uint256, uint256): view

interface ERC20:
    def balanceOf(owner: address) -> uint256: view
    def totalSupply() -> uint256: view
    def decimals() -> uint8: view
    def symbol() -> String[16]: view


BPS: constant(uint256) = 10_000


@external
@view
def tokens(_pool: address) -> (address, address):
    return staticcall Pool(_pool).token0(), staticcall Pool(_pool).token1()


@external
@view
def reserves(_pool: address) -> (uint256, uint256, uint256, uint256):
    reserve0: uint256 = 0
    reserve1: uint256 = 0
    active0: uint256 = 0
    active1: uint256 = 0
    reserve0, reserve1 = staticcall Pool(_pool).reserves()
    active0, active1 = staticcall Pool(_pool).activeReserves()
    return reserve0, reserve1, active0, active1


@external
@view
def accounting(_pool: address) -> (uint256, uint256, uint256, uint256, uint256):
    reserve0: uint256 = 0
    reserve1: uint256 = 0
    fee0: uint256 = 0
    fee1: uint256 = 0
    supply: uint256 = staticcall Pool(_pool).totalSupply()
    reserve0, reserve1 = staticcall Pool(_pool).reserves()
    fee0, fee1 = staticcall Pool(_pool).protocolFees()
    return reserve0, reserve1, fee0, fee1, supply


@external
@view
def feeState(_pool: address) -> (uint256, uint256, uint256, address):
    return staticcall Pool(_pool).feeState()


@external
@view
def invariantState(_pool: address) -> (uint256, uint256, uint256, uint256):
    current: uint256 = staticcall Pool(_pool).invariant()
    last_value: uint256 = staticcall Pool(_pool).lastInvariant()
    amp_value: uint256 = staticcall Pool(_pool).amp()
    imbalance: uint256 = staticcall Pool(_pool).spotImbalance()
    return current, last_value, amp_value, imbalance


@external
@view
def accountPosition(_pool: address, _owner: address) -> (uint256, uint256, uint256, uint256):
    shares: uint256 = 0
    amount0: uint256 = 0
    amount1: uint256 = 0
    shares, amount0, amount1 = staticcall Pool(_pool).lpPreview(_owner)
    supply: uint256 = staticcall Pool(_pool).totalSupply()
    ownership_bps: uint256 = 0
    if supply > 0:
        ownership_bps = shares * BPS // supply
    return shares, amount0, amount1, ownership_bps


@external
@view
def allowanceView(_pool: address, _owner: address, _spender: address) -> uint256:
    return staticcall Pool(_pool).allowance(_owner, _spender)


@external
@view
def quoteSwap(_pool: address, _token_in: address, _amount_in: uint256) -> (uint256, uint256):
    return staticcall Pool(_pool).quoteSwap(_token_in, _amount_in)


@external
@view
def quoteAddLiquidity(_pool: address, _amount0: uint256, _amount1: uint256) -> uint256:
    return staticcall Pool(_pool).quoteAddLiquidity(_amount0, _amount1)


@external
@view
def quoteRemoveLiquidity(_pool: address, _shares: uint256) -> (uint256, uint256):
    return staticcall Pool(_pool).quoteRemoveLiquidity(_shares)


@external
@view
def quoteRemoveLiquidityImbalanced(_pool: address, _amount0: uint256, _amount1: uint256) -> (uint256, uint256):
    return staticcall Pool(_pool).quoteRemoveLiquidityImbalanced(_amount0, _amount1)


@external
@view
def tokenBalances(_pool: address) -> (uint256, uint256, uint256, uint256):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    pool0: uint256 = staticcall ERC20(token0).balanceOf(_pool)
    pool1: uint256 = staticcall ERC20(token1).balanceOf(_pool)
    total0: uint256 = staticcall ERC20(token0).totalSupply()
    total1: uint256 = staticcall ERC20(token1).totalSupply()
    return pool0, pool1, total0, total1


@external
@view
def reserveDrift(_pool: address) -> (int256, int256):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    physical0: uint256 = staticcall ERC20(token0).balanceOf(_pool)
    physical1: uint256 = staticcall ERC20(token1).balanceOf(_pool)
    reserve0: uint256 = 0
    reserve1: uint256 = 0
    reserve0, reserve1 = staticcall Pool(_pool).reserves()
    drift0: int256 = 0
    drift1: int256 = 0
    if physical0 >= reserve0:
        drift0 = convert(physical0 - reserve0, int256)
    else:
        drift0 = -convert(reserve0 - physical0, int256)
    if physical1 >= reserve1:
        drift1 = convert(physical1 - reserve1, int256)
    else:
        drift1 = -convert(reserve1 - physical1, int256)
    return drift0, drift1


@external
@view
def poolHealth(_pool: address) -> (bool, bool, bool, uint256):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    physical0: uint256 = staticcall ERC20(token0).balanceOf(_pool)
    physical1: uint256 = staticcall ERC20(token1).balanceOf(_pool)
    reserve0: uint256 = 0
    reserve1: uint256 = 0
    fee0: uint256 = 0
    fee1: uint256 = 0
    reserve0, reserve1 = staticcall Pool(_pool).reserves()
    fee0, fee1 = staticcall Pool(_pool).protocolFees()
    balanced: bool = staticcall Pool(_pool).spotImbalance() <= 2_000
    backed: bool = physical0 >= reserve0 and physical1 >= reserve1
    fees_backed: bool = reserve0 >= fee0 and reserve1 >= fee1
    return backed, fees_backed, balanced, staticcall Pool(_pool).invariant()


@external
@view
def poolSummary(_pool: address, _account: address) -> (
    address,
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256
):
    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    active0: uint256 = 0
    active1: uint256 = 0
    fee0: uint256 = 0
    fee1: uint256 = 0
    active0, active1 = staticcall Pool(_pool).activeReserves()
    fee0, fee1 = staticcall Pool(_pool).protocolFees()
    shares: uint256 = staticcall Pool(_pool).balanceOf(_account)
    return (
        token0,
        token1,
        active0,
        active1,
        fee0,
        fee1,
        staticcall Pool(_pool).totalSupply(),
        shares,
        staticcall Pool(_pool).invariant(),
        staticcall Pool(_pool).spotImbalance()
    )
