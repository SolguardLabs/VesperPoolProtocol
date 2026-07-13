# @version 0.4.3

"""
Vesper Pool Protocol

Two-asset low-volatility pool with internal LP shares, fee accounting,
balanced redemptions and imbalanced redemptions. The invariant is intentionally
compact so auditors can reason about accounting without needing a full Curve
implementation.
"""

interface ERC20:
    def balanceOf(owner: address) -> uint256: view
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable


event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event FeeReceiverUpdated:
    previous_receiver: indexed(address)
    new_receiver: indexed(address)

event FeeParametersUpdated:
    swap_fee_bps: uint256
    protocol_fee_share_bps: uint256
    imbalance_penalty_bps: uint256

event AmplificationUpdated:
    previous_amp: uint256
    new_amp: uint256

event LiquidityAdded:
    provider: indexed(address)
    receiver: indexed(address)
    amount0: uint256
    amount1: uint256
    shares: uint256

event LiquidityRemoved:
    owner: indexed(address)
    receiver: indexed(address)
    shares: uint256
    amount0: uint256
    amount1: uint256

event ImbalancedLiquidityRemoved:
    owner: indexed(address)
    receiver: indexed(address)
    shares: uint256
    penalty_shares: uint256
    amount0: uint256
    amount1: uint256

event Swap:
    sender: indexed(address)
    receiver: indexed(address)
    token_in: indexed(address)
    amount_in: uint256
    amount_out: uint256
    fee: uint256

event ProtocolFeesClaimed:
    receiver: indexed(address)
    amount0: uint256
    amount1: uint256

event Paused:
    account: indexed(address)
    paused: bool

event ReservesSynced:
    reserve0: uint256
    reserve1: uint256


BPS: constant(uint256) = 10_000
AMP_PRECISION: constant(uint256) = 1_000
MINIMUM_LIQUIDITY: constant(uint256) = 1_000
MAX_SWAP_FEE_BPS: constant(uint256) = 100
MAX_PROTOCOL_SHARE_BPS: constant(uint256) = 5_000
MAX_IMBALANCE_PENALTY_BPS: constant(uint256) = 2_500
MAX_AMP: constant(uint256) = 25_000
MIN_AMP: constant(uint256) = 50

name: public(String[64])
symbol: public(String[16])
decimals: public(uint8)

token0: public(address)
token1: public(address)
owner: public(address)
feeReceiver: public(address)
paused: public(bool)

amp: public(uint256)
swapFeeBps: public(uint256)
protocolFeeShareBps: public(uint256)
imbalancePenaltyBps: public(uint256)

reserve0: public(uint256)
reserve1: public(uint256)
protocolFee0: public(uint256)
protocolFee1: public(uint256)
lastInvariant: public(uint256)

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

locked: bool


@deploy
def __init__(
    _token0: address,
    _token1: address,
    _name: String[64],
    _symbol: String[16],
    _amp: uint256,
    _swap_fee_bps: uint256,
    _protocol_fee_share_bps: uint256,
    _imbalance_penalty_bps: uint256,
    _fee_receiver: address
):
    assert _token0 != empty(address), "TOKEN0"
    assert _token1 != empty(address), "TOKEN1"
    assert _token0 != _token1, "TOKENS"
    assert _amp >= MIN_AMP and _amp <= MAX_AMP, "AMP"
    assert _swap_fee_bps <= MAX_SWAP_FEE_BPS, "SWAP_FEE"
    assert _protocol_fee_share_bps <= MAX_PROTOCOL_SHARE_BPS, "PROTOCOL_FEE"
    assert _imbalance_penalty_bps <= MAX_IMBALANCE_PENALTY_BPS, "PENALTY"

    self.token0 = _token0
    self.token1 = _token1
    self.name = _name
    self.symbol = _symbol
    self.decimals = 18
    self.owner = msg.sender
    if _fee_receiver == empty(address):
        self.feeReceiver = msg.sender
    else:
        self.feeReceiver = _fee_receiver
    self.amp = _amp
    self.swapFeeBps = _swap_fee_bps
    self.protocolFeeShareBps = _protocol_fee_share_bps
    self.imbalancePenaltyBps = _imbalance_penalty_bps

    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)
    log FeeReceiverUpdated(previous_receiver=empty(address), new_receiver=self.feeReceiver)
    log FeeParametersUpdated(
        swap_fee_bps=_swap_fee_bps,
        protocol_fee_share_bps=_protocol_fee_share_bps,
        imbalance_penalty_bps=_imbalance_penalty_bps
    )
    log AmplificationUpdated(previous_amp=0, new_amp=_amp)


@internal
def _enter():
    assert not self.locked, "LOCKED"
    self.locked = True


@internal
def _exit():
    self.locked = False


@internal
@view
def _require_owner():
    assert msg.sender == self.owner, "OWNER"


@internal
@view
def _require_live():
    assert not self.paused, "PAUSED"


@internal
@pure
def _min(a: uint256, b: uint256) -> uint256:
    if a < b:
        return a
    return b


@internal
@pure
def _max(a: uint256, b: uint256) -> uint256:
    if a > b:
        return a
    return b


@internal
@pure
def _abs_diff(a: uint256, b: uint256) -> uint256:
    if a > b:
        return a - b
    return b - a


@internal
@pure
def _ceil_div(a: uint256, b: uint256) -> uint256:
    assert b > 0, "DIV"
    if a == 0:
        return 0
    return (a - 1) // b + 1


@internal
@view
def _active0() -> uint256:
    assert self.reserve0 >= self.protocolFee0, "FEE0"
    return self.reserve0 - self.protocolFee0


@internal
@view
def _active1() -> uint256:
    assert self.reserve1 >= self.protocolFee1, "FEE1"
    return self.reserve1 - self.protocolFee1


@internal
@pure
def _compute_invariant(x: uint256, y: uint256, amplification: uint256) -> uint256:
    if x == 0 and y == 0:
        return 0

    s: uint256 = x + y
    if x == 0 or y == 0:
        return s

    harmonic: uint256 = 2 * x * y // s
    bonus: uint256 = harmonic * amplification // AMP_PRECISION
    spread: uint256 = 0
    diff: uint256 = 0

    if x > y:
        diff = x - y
    else:
        diff = y - x

    if s > 0:
        spread = diff * diff // s

    if bonus > spread:
        return s + bonus - spread
    return s


@internal
@view
def _current_invariant() -> uint256:
    return self._compute_invariant(self._active0(), self._active1(), self.amp)


@internal
@view
def _solve_y(x: uint256, target_d: uint256) -> uint256:
    low: uint256 = 0
    high: uint256 = target_d + x + 1
    mid: uint256 = 0
    value: uint256 = 0

    for _: uint256 in range(96):
        mid = (low + high) // 2
        value = self._compute_invariant(x, mid, self.amp)
        if value >= target_d:
            high = mid
        else:
            low = mid + 1

    return high


@internal
@view
def _quote_swap(_token_in: address, _amount_in: uint256) -> (uint256, uint256):
    assert _amount_in > 0, "AMOUNT"

    fee: uint256 = _amount_in * self.swapFeeBps // BPS
    amount_after_fee: uint256 = _amount_in - fee
    active0: uint256 = self._active0()
    active1: uint256 = self._active1()
    d0: uint256 = self._compute_invariant(active0, active1, self.amp)
    y: uint256 = 0
    out: uint256 = 0

    if _token_in == self.token0:
        y = self._solve_y(active0 + amount_after_fee, d0)
        assert active1 > y, "LIQUIDITY"
        out = active1 - y
    elif _token_in == self.token1:
        y = self._solve_y(active1 + amount_after_fee, d0)
        assert active0 > y, "LIQUIDITY"
        out = active0 - y
    else:
        raise "TOKEN_IN"

    assert out > 0, "OUTPUT"
    return out, fee


@internal
@view
def _quote_add_liquidity(_amount0: uint256, _amount1: uint256) -> uint256:
    assert _amount0 > 0 and _amount1 > 0, "AMOUNTS"

    supply: uint256 = self.totalSupply
    if supply == 0:
        d: uint256 = self._compute_invariant(_amount0, _amount1, self.amp)
        assert d > MINIMUM_LIQUIDITY, "INITIAL"
        return d - MINIMUM_LIQUIDITY

    active0: uint256 = self._active0()
    active1: uint256 = self._active1()
    assert active0 > 0 and active1 > 0, "RESERVES"

    shares0: uint256 = _amount0 * supply // active0
    shares1: uint256 = _amount1 * supply // active1
    return self._min(shares0, shares1)


@internal
@pure
def _withdrawal_penalty_from(
    old0: uint256,
    old1: uint256,
    new0: uint256,
    new1: uint256,
    old_d: uint256,
    new_d: uint256,
    supply: uint256,
    penalty_bps: uint256
) -> uint256:
    if old_d == 0 or supply == 0 or penalty_bps == 0:
        return 0

    ideal0: uint256 = old0 * new_d // old_d
    ideal1: uint256 = old1 * new_d // old_d
    diff0: uint256 = 0
    diff1: uint256 = 0

    if new0 > ideal0:
        diff0 = new0 - ideal0
    else:
        diff0 = ideal0 - new0

    if new1 > ideal1:
        diff1 = new1 - ideal1
    else:
        diff1 = ideal1 - new1

    penalty_value: uint256 = (diff0 + diff1) * penalty_bps // BPS
    return penalty_value * supply // old_d


@internal
@view
def _quote_remove_imbalanced(_amount0: uint256, _amount1: uint256) -> (uint256, uint256):
    assert _amount0 > 0 or _amount1 > 0, "AMOUNTS"

    active0: uint256 = self._active0()
    active1: uint256 = self._active1()
    assert _amount0 < active0 and _amount1 < active1, "LIQUIDITY"

    old_d: uint256 = self._compute_invariant(active0, active1, self.amp)
    new0: uint256 = active0 - _amount0
    new1: uint256 = active1 - _amount1
    new_d: uint256 = self._compute_invariant(new0, new1, self.amp)
    assert old_d > new_d, "INVARIANT"

    base_shares: uint256 = self._ceil_div((old_d - new_d) * self.totalSupply, old_d)
    penalty_shares: uint256 = self._withdrawal_penalty_from(
        active0,
        active1,
        new0,
        new1,
        old_d,
        new_d,
        self.totalSupply,
        self.imbalancePenaltyBps
    )
    return base_shares + penalty_shares, penalty_shares


@internal
def _mint(_to: address, _amount: uint256):
    self.totalSupply += _amount
    self.balanceOf[_to] += _amount
    log Transfer(sender=empty(address), receiver=_to, value=_amount)


@internal
def _burn(_from: address, _amount: uint256):
    assert self.balanceOf[_from] >= _amount, "LP_BALANCE"
    self.balanceOf[_from] -= _amount
    self.totalSupply -= _amount
    log Transfer(sender=_from, receiver=empty(address), value=_amount)


@internal
def _spend_allowance(_owner: address, _spender: address, _amount: uint256):
    if _owner != _spender:
        allowed: uint256 = self.allowance[_owner][_spender]
        assert allowed >= _amount, "LP_ALLOWANCE"
        if allowed != max_value(uint256):
            self.allowance[_owner][_spender] = allowed - _amount
            log Approval(owner=_owner, spender=_spender, value=allowed - _amount)


@internal
def _transfer_shares(_from: address, _to: address, _amount: uint256):
    assert _to != empty(address), "RECEIVER"
    assert self.balanceOf[_from] >= _amount, "LP_BALANCE"
    self.balanceOf[_from] -= _amount
    self.balanceOf[_to] += _amount
    log Transfer(sender=_from, receiver=_to, value=_amount)


@external
def approve(_spender: address, _amount: uint256) -> bool:
    assert _spender != empty(address), "SPENDER"
    self.allowance[msg.sender][_spender] = _amount
    log Approval(owner=msg.sender, spender=_spender, value=_amount)
    return True


@external
def transfer(_to: address, _amount: uint256) -> bool:
    self._transfer_shares(msg.sender, _to, _amount)
    return True


@external
def transferFrom(_from: address, _to: address, _amount: uint256) -> bool:
    self._spend_allowance(_from, msg.sender, _amount)
    self._transfer_shares(_from, _to, _amount)
    return True


@external
def addLiquidity(_amount0: uint256, _amount1: uint256, _min_shares: uint256, _receiver: address) -> uint256:
    self._enter()
    self._require_live()
    assert _receiver != empty(address), "RECEIVER"

    shares: uint256 = self._quote_add_liquidity(_amount0, _amount1)
    assert shares >= _min_shares, "SLIPPAGE"

    ok0: bool = extcall ERC20(self.token0).transferFrom(msg.sender, self, _amount0, default_return_value=True)
    ok1: bool = extcall ERC20(self.token1).transferFrom(msg.sender, self, _amount1, default_return_value=True)
    assert ok0 and ok1, "TRANSFER_IN"

    self.reserve0 += _amount0
    self.reserve1 += _amount1

    if self.totalSupply == 0:
        self._mint(empty(address), MINIMUM_LIQUIDITY)

    self._mint(_receiver, shares)
    self.lastInvariant = self._current_invariant()
    log LiquidityAdded(
        provider=msg.sender,
        receiver=_receiver,
        amount0=_amount0,
        amount1=_amount1,
        shares=shares
    )
    self._exit()
    return shares


@external
def removeLiquidity(_shares: uint256, _min0: uint256, _min1: uint256, _receiver: address) -> (uint256, uint256):
    self._enter()
    self._require_live()
    assert _receiver != empty(address), "RECEIVER"
    assert _shares > 0, "SHARES"

    supply: uint256 = self.totalSupply
    active0: uint256 = self._active0()
    active1: uint256 = self._active1()
    amount0: uint256 = _shares * active0 // supply
    amount1: uint256 = _shares * active1 // supply
    assert amount0 >= _min0 and amount1 >= _min1, "SLIPPAGE"
    assert amount0 < self.reserve0 and amount1 < self.reserve1, "RESERVE"

    self._burn(msg.sender, _shares)
    self.reserve0 -= amount0
    self.reserve1 -= amount1

    ok0: bool = extcall ERC20(self.token0).transfer(_receiver, amount0, default_return_value=True)
    ok1: bool = extcall ERC20(self.token1).transfer(_receiver, amount1, default_return_value=True)
    assert ok0 and ok1, "TRANSFER_OUT"

    self.lastInvariant = self._current_invariant()
    log LiquidityRemoved(owner=msg.sender, receiver=_receiver, shares=_shares, amount0=amount0, amount1=amount1)
    self._exit()
    return amount0, amount1


@external
def removeLiquidityFor(
    _owner: address,
    _shares: uint256,
    _min0: uint256,
    _min1: uint256,
    _receiver: address
) -> (uint256, uint256):
    self._enter()
    self._require_live()
    assert _receiver != empty(address), "RECEIVER"
    assert _shares > 0, "SHARES"

    self._spend_allowance(_owner, msg.sender, _shares)
    supply: uint256 = self.totalSupply
    active0: uint256 = self._active0()
    active1: uint256 = self._active1()
    amount0: uint256 = _shares * active0 // supply
    amount1: uint256 = _shares * active1 // supply
    assert amount0 >= _min0 and amount1 >= _min1, "SLIPPAGE"
    assert amount0 < self.reserve0 and amount1 < self.reserve1, "RESERVE"

    self._burn(_owner, _shares)
    self.reserve0 -= amount0
    self.reserve1 -= amount1

    ok0: bool = extcall ERC20(self.token0).transfer(_receiver, amount0, default_return_value=True)
    ok1: bool = extcall ERC20(self.token1).transfer(_receiver, amount1, default_return_value=True)
    assert ok0 and ok1, "TRANSFER_OUT"

    self.lastInvariant = self._current_invariant()
    log LiquidityRemoved(owner=_owner, receiver=_receiver, shares=_shares, amount0=amount0, amount1=amount1)
    self._exit()
    return amount0, amount1


@external
def removeLiquidityImbalanced(
    _amount0: uint256,
    _amount1: uint256,
    _max_shares: uint256,
    _receiver: address
) -> uint256:
    self._enter()
    self._require_live()
    assert _receiver != empty(address), "RECEIVER"
    assert _amount0 > 0 or _amount1 > 0, "AMOUNTS"

    active0: uint256 = self._active0()
    active1: uint256 = self._active1()
    assert _amount0 < active0 and _amount1 < active1, "LIQUIDITY"

    old_d: uint256 = self._compute_invariant(active0, active1, self.amp)
    new0: uint256 = active0 - _amount0
    new1: uint256 = active1 - _amount1
    new_d: uint256 = self._compute_invariant(new0, new1, self.amp)
    assert old_d > new_d, "INVARIANT"

    base_shares: uint256 = self._ceil_div((old_d - new_d) * self.totalSupply, old_d)

    if _amount0 > 0:
        self.reserve0 -= _amount0
    if _amount1 > 0:
        self.reserve1 -= _amount1

    observed0: uint256 = self._active0()
    observed1: uint256 = self._active1()
    observed_d: uint256 = self._compute_invariant(observed0, observed1, self.amp)
    penalty_shares: uint256 = self._withdrawal_penalty_from(
        observed0,
        observed1,
        observed0,
        observed1,
        observed_d,
        observed_d,
        self.totalSupply,
        self.imbalancePenaltyBps
    )

    shares_to_burn: uint256 = base_shares + penalty_shares
    assert shares_to_burn <= _max_shares, "SLIPPAGE"
    self._burn(msg.sender, shares_to_burn)

    if _amount0 > 0:
        ok0: bool = extcall ERC20(self.token0).transfer(_receiver, _amount0, default_return_value=True)
        assert ok0, "TRANSFER0"
    if _amount1 > 0:
        ok1: bool = extcall ERC20(self.token1).transfer(_receiver, _amount1, default_return_value=True)
        assert ok1, "TRANSFER1"

    self.lastInvariant = self._current_invariant()
    log ImbalancedLiquidityRemoved(
        owner=msg.sender,
        receiver=_receiver,
        shares=shares_to_burn,
        penalty_shares=penalty_shares,
        amount0=_amount0,
        amount1=_amount1
    )
    self._exit()
    return shares_to_burn


@external
def swap(_token_in: address, _amount_in: uint256, _min_out: uint256, _receiver: address) -> uint256:
    self._enter()
    self._require_live()
    assert _receiver != empty(address), "RECEIVER"

    amount_out: uint256 = 0
    fee: uint256 = 0
    amount_out, fee = self._quote_swap(_token_in, _amount_in)
    assert amount_out >= _min_out, "SLIPPAGE"
    protocol_cut: uint256 = fee * self.protocolFeeShareBps // BPS

    if _token_in == self.token0:
        ok_in0: bool = extcall ERC20(self.token0).transferFrom(msg.sender, self, _amount_in, default_return_value=True)
        assert ok_in0, "TRANSFER_IN"
        self.reserve0 += _amount_in
        self.reserve1 -= amount_out
        self.protocolFee0 += protocol_cut
        ok_out1: bool = extcall ERC20(self.token1).transfer(_receiver, amount_out, default_return_value=True)
        assert ok_out1, "TRANSFER_OUT"
    elif _token_in == self.token1:
        ok_in1: bool = extcall ERC20(self.token1).transferFrom(msg.sender, self, _amount_in, default_return_value=True)
        assert ok_in1, "TRANSFER_IN"
        self.reserve1 += _amount_in
        self.reserve0 -= amount_out
        self.protocolFee1 += protocol_cut
        ok_out0: bool = extcall ERC20(self.token0).transfer(_receiver, amount_out, default_return_value=True)
        assert ok_out0, "TRANSFER_OUT"
    else:
        raise "TOKEN_IN"

    self.lastInvariant = self._current_invariant()
    log Swap(
        sender=msg.sender,
        receiver=_receiver,
        token_in=_token_in,
        amount_in=_amount_in,
        amount_out=amount_out,
        fee=fee
    )
    self._exit()
    return amount_out


@external
def claimProtocolFees(_receiver: address) -> (uint256, uint256):
    self._enter()
    self._require_owner()
    receiver: address = _receiver
    if receiver == empty(address):
        receiver = self.feeReceiver
    assert receiver != empty(address), "RECEIVER"

    amount0: uint256 = self.protocolFee0
    amount1: uint256 = self.protocolFee1
    self.protocolFee0 = 0
    self.protocolFee1 = 0

    if amount0 > 0:
        self.reserve0 -= amount0
        ok0: bool = extcall ERC20(self.token0).transfer(receiver, amount0, default_return_value=True)
        assert ok0, "TRANSFER0"
    if amount1 > 0:
        self.reserve1 -= amount1
        ok1: bool = extcall ERC20(self.token1).transfer(receiver, amount1, default_return_value=True)
        assert ok1, "TRANSFER1"

    self.lastInvariant = self._current_invariant()
    log ProtocolFeesClaimed(receiver=receiver, amount0=amount0, amount1=amount1)
    self._exit()
    return amount0, amount1


@external
def sync():
    self._enter()
    balance0: uint256 = staticcall ERC20(self.token0).balanceOf(self)
    balance1: uint256 = staticcall ERC20(self.token1).balanceOf(self)
    assert balance0 >= self.protocolFee0 and balance1 >= self.protocolFee1, "BALANCE"
    self.reserve0 = balance0
    self.reserve1 = balance1
    self.lastInvariant = self._current_invariant()
    log ReservesSynced(reserve0=balance0, reserve1=balance1)
    self._exit()


@external
def setPaused(_paused: bool):
    self._require_owner()
    self.paused = _paused
    log Paused(account=msg.sender, paused=_paused)


@external
def setFeeReceiver(_receiver: address):
    self._require_owner()
    assert _receiver != empty(address), "RECEIVER"
    previous: address = self.feeReceiver
    self.feeReceiver = _receiver
    log FeeReceiverUpdated(previous_receiver=previous, new_receiver=_receiver)


@external
def setFeeParameters(_swap_fee_bps: uint256, _protocol_fee_share_bps: uint256, _imbalance_penalty_bps: uint256):
    self._require_owner()
    assert _swap_fee_bps <= MAX_SWAP_FEE_BPS, "SWAP_FEE"
    assert _protocol_fee_share_bps <= MAX_PROTOCOL_SHARE_BPS, "PROTOCOL_FEE"
    assert _imbalance_penalty_bps <= MAX_IMBALANCE_PENALTY_BPS, "PENALTY"
    self.swapFeeBps = _swap_fee_bps
    self.protocolFeeShareBps = _protocol_fee_share_bps
    self.imbalancePenaltyBps = _imbalance_penalty_bps
    log FeeParametersUpdated(
        swap_fee_bps=_swap_fee_bps,
        protocol_fee_share_bps=_protocol_fee_share_bps,
        imbalance_penalty_bps=_imbalance_penalty_bps
    )


@external
def setAmplification(_amp: uint256):
    self._require_owner()
    assert _amp >= MIN_AMP and _amp <= MAX_AMP, "AMP"
    previous: uint256 = self.amp
    self.amp = _amp
    self.lastInvariant = self._current_invariant()
    log AmplificationUpdated(previous_amp=previous, new_amp=_amp)


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
@view
def reserves() -> (uint256, uint256):
    return self.reserve0, self.reserve1


@external
@view
def activeReserves() -> (uint256, uint256):
    return self._active0(), self._active1()


@external
@view
def protocolFees() -> (uint256, uint256):
    return self.protocolFee0, self.protocolFee1


@external
@view
def quoteSwap(_token_in: address, _amount_in: uint256) -> (uint256, uint256):
    return self._quote_swap(_token_in, _amount_in)


@external
@view
def quoteAddLiquidity(_amount0: uint256, _amount1: uint256) -> uint256:
    return self._quote_add_liquidity(_amount0, _amount1)


@external
@view
def quoteRemoveLiquidity(_shares: uint256) -> (uint256, uint256):
    assert _shares > 0 and _shares <= self.totalSupply, "SHARES"
    return _shares * self._active0() // self.totalSupply, _shares * self._active1() // self.totalSupply


@external
@view
def quoteRemoveLiquidityImbalanced(_amount0: uint256, _amount1: uint256) -> (uint256, uint256):
    return self._quote_remove_imbalanced(_amount0, _amount1)


@external
@view
def invariant() -> uint256:
    return self._current_invariant()


@external
@view
def spotImbalance() -> uint256:
    active0: uint256 = self._active0()
    active1: uint256 = self._active1()
    total: uint256 = active0 + active1
    if total == 0:
        return 0
    return self._abs_diff(active0, active1) * BPS // total


@external
@view
def utilizationOf(_token: address) -> uint256:
    if _token == self.token0:
        if self.reserve0 == 0:
            return 0
        return self.protocolFee0 * BPS // self.reserve0
    if _token == self.token1:
        if self.reserve1 == 0:
            return 0
        return self.protocolFee1 * BPS // self.reserve1
    raise "TOKEN"


@external
@view
def lpPreview(_owner: address) -> (uint256, uint256, uint256):
    shares: uint256 = self.balanceOf[_owner]
    if self.totalSupply == 0:
        return shares, 0, 0
    return shares, shares * self._active0() // self.totalSupply, shares * self._active1() // self.totalSupply


@external
@view
def poolState() -> (
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    bool
):
    return (
        self.reserve0,
        self.reserve1,
        self.protocolFee0,
        self.protocolFee1,
        self.totalSupply,
        self.amp,
        self.lastInvariant,
        self.paused
    )


@external
@view
def feeState() -> (uint256, uint256, uint256, address):
    return self.swapFeeBps, self.protocolFeeShareBps, self.imbalancePenaltyBps, self.feeReceiver


@external
@view
def tokenPair() -> (address, address):
    return self.token0, self.token1
