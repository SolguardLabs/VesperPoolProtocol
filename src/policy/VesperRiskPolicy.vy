# @version 0.4.3

"""
Parameter policy helper for Vesper low-volatility pools.
The contract is intentionally stateless apart from governance owned defaults
so frontends and keepers can share the same admission math.
"""

BPS: constant(uint256) = 10_000
AMP_PRECISION: constant(uint256) = 1_000

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event DefaultPolicyUpdated:
    target_imbalance_bps: uint256
    critical_imbalance_bps: uint256
    max_swap_bps: uint256
    max_withdrawal_bps: uint256


owner: public(address)
targetImbalanceBps: public(uint256)
criticalImbalanceBps: public(uint256)
maxSwapBps: public(uint256)
maxWithdrawalBps: public(uint256)


@deploy
def __init__():
    self.owner = msg.sender
    self.targetImbalanceBps = 500
    self.criticalImbalanceBps = 3_500
    self.maxSwapBps = 2_500
    self.maxWithdrawalBps = 4_000
    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)
    log DefaultPolicyUpdated(
        target_imbalance_bps=self.targetImbalanceBps,
        critical_imbalance_bps=self.criticalImbalanceBps,
        max_swap_bps=self.maxSwapBps,
        max_withdrawal_bps=self.maxWithdrawalBps
    )


@internal
@view
def _require_owner():
    assert msg.sender == self.owner, "OWNER"


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
def setDefaults(
    _target_imbalance_bps: uint256,
    _critical_imbalance_bps: uint256,
    _max_swap_bps: uint256,
    _max_withdrawal_bps: uint256
):
    self._require_owner()
    assert _target_imbalance_bps <= BPS, "TARGET"
    assert _critical_imbalance_bps <= BPS, "CRITICAL"
    assert _target_imbalance_bps <= _critical_imbalance_bps, "ORDER"
    assert _max_swap_bps <= BPS, "SWAP"
    assert _max_withdrawal_bps <= BPS, "WITHDRAW"
    self.targetImbalanceBps = _target_imbalance_bps
    self.criticalImbalanceBps = _critical_imbalance_bps
    self.maxSwapBps = _max_swap_bps
    self.maxWithdrawalBps = _max_withdrawal_bps
    log DefaultPolicyUpdated(
        target_imbalance_bps=_target_imbalance_bps,
        critical_imbalance_bps=_critical_imbalance_bps,
        max_swap_bps=_max_swap_bps,
        max_withdrawal_bps=_max_withdrawal_bps
    )


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
@view
def imbalanceBps(_reserve0: uint256, _reserve1: uint256) -> uint256:
    total: uint256 = _reserve0 + _reserve1
    if total == 0:
        return 0
    return self._abs_diff(_reserve0, _reserve1) * BPS // total


@external
@view
def isWithinTarget(_reserve0: uint256, _reserve1: uint256) -> bool:
    total: uint256 = _reserve0 + _reserve1
    if total == 0:
        return True
    return self._abs_diff(_reserve0, _reserve1) * BPS // total <= self.targetImbalanceBps


@external
@view
def isCritical(_reserve0: uint256, _reserve1: uint256) -> bool:
    total: uint256 = _reserve0 + _reserve1
    if total == 0:
        return False
    return self._abs_diff(_reserve0, _reserve1) * BPS // total >= self.criticalImbalanceBps


@external
@view
def maxSwapAmount(_reserve_in: uint256, _reserve_out: uint256) -> uint256:
    base: uint256 = self._min(_reserve_in, _reserve_out)
    return base * self.maxSwapBps // BPS


@external
@view
def maxWithdrawalAmount(_reserve: uint256) -> uint256:
    return _reserve * self.maxWithdrawalBps // BPS


@external
@pure
def invariantPreview(_reserve0: uint256, _reserve1: uint256, _amp: uint256) -> uint256:
    if _reserve0 == 0 and _reserve1 == 0:
        return 0
    s: uint256 = _reserve0 + _reserve1
    if _reserve0 == 0 or _reserve1 == 0:
        return s
    harmonic: uint256 = 2 * _reserve0 * _reserve1 // s
    bonus: uint256 = harmonic * _amp // AMP_PRECISION
    diff: uint256 = 0
    if _reserve0 > _reserve1:
        diff = _reserve0 - _reserve1
    else:
        diff = _reserve1 - _reserve0
    spread: uint256 = diff * diff // s
    if bonus > spread:
        return s + bonus - spread
    return s


@external
@view
def withdrawalWindow(_reserve0: uint256, _reserve1: uint256) -> (uint256, uint256, bool):
    max0: uint256 = _reserve0 * self.maxWithdrawalBps // BPS
    max1: uint256 = _reserve1 * self.maxWithdrawalBps // BPS
    critical: bool = False
    total: uint256 = _reserve0 + _reserve1
    if total > 0:
        critical = self._abs_diff(_reserve0, _reserve1) * BPS // total >= self.criticalImbalanceBps
    return max0, max1, critical


@external
@view
def recommendedSwapFee(_reserve0: uint256, _reserve1: uint256, _base_fee_bps: uint256) -> uint256:
    assert _base_fee_bps <= 100, "FEE"
    total: uint256 = _reserve0 + _reserve1
    if total == 0:
        return _base_fee_bps
    imbalance: uint256 = self._abs_diff(_reserve0, _reserve1) * BPS // total
    if imbalance <= self.targetImbalanceBps:
        return _base_fee_bps
    if imbalance >= self.criticalImbalanceBps:
        return _base_fee_bps + 50
    slope: uint256 = (imbalance - self.targetImbalanceBps) * 50 // (self.criticalImbalanceBps - self.targetImbalanceBps)
    return _base_fee_bps + slope
