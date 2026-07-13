# @version 0.4.3

"""
Governance controlled parameter registry for Vesper pools.
Values are staged before activation so operators can review pool changes.
"""

BPS: constant(uint256) = 10_000
MAX_POOLS: constant(uint256) = 512
MAX_DELAY: constant(uint256) = 30 * 24 * 60 * 60

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event GovernorUpdated:
    governor: indexed(address)
    allowed: bool

event PoolTracked:
    pool: indexed(address)

event ParametersStaged:
    pool: indexed(address)
    swap_fee_bps: uint256
    protocol_fee_share_bps: uint256
    imbalance_penalty_bps: uint256
    amp: uint256
    activate_after: uint256

event ParametersActivated:
    pool: indexed(address)
    swap_fee_bps: uint256
    protocol_fee_share_bps: uint256
    imbalance_penalty_bps: uint256
    amp: uint256

event ParametersCancelled:
    pool: indexed(address)


owner: public(address)
governors: public(HashMap[address, bool])
pools: DynArray[address, MAX_POOLS]
tracked: public(HashMap[address, bool])

swapFeeBps: public(HashMap[address, uint256])
protocolFeeShareBps: public(HashMap[address, uint256])
imbalancePenaltyBps: public(HashMap[address, uint256])
amp: public(HashMap[address, uint256])

pendingSwapFeeBps: public(HashMap[address, uint256])
pendingProtocolFeeShareBps: public(HashMap[address, uint256])
pendingImbalancePenaltyBps: public(HashMap[address, uint256])
pendingAmp: public(HashMap[address, uint256])
pendingActivation: public(HashMap[address, uint256])


@deploy
def __init__():
    self.owner = msg.sender
    self.governors[msg.sender] = True
    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)
    log GovernorUpdated(governor=msg.sender, allowed=True)


@internal
@view
def _require_owner():
    assert msg.sender == self.owner, "OWNER"


@internal
@view
def _require_governor():
    assert self.governors[msg.sender], "GOVERNOR"


@internal
@pure
def _validate(_swap_fee_bps: uint256, _protocol_fee_share_bps: uint256, _imbalance_penalty_bps: uint256, _amp: uint256):
    assert _swap_fee_bps <= 100, "SWAP_FEE"
    assert _protocol_fee_share_bps <= 5_000, "PROTOCOL_FEE"
    assert _imbalance_penalty_bps <= 2_500, "PENALTY"
    assert _amp >= 50 and _amp <= 25_000, "AMP"


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
def setGovernor(_governor: address, _allowed: bool):
    self._require_owner()
    assert _governor != empty(address), "GOVERNOR"
    self.governors[_governor] = _allowed
    log GovernorUpdated(governor=_governor, allowed=_allowed)


@external
def trackPool(_pool: address, _swap_fee_bps: uint256, _protocol_fee_share_bps: uint256, _imbalance_penalty_bps: uint256, _amp: uint256):
    self._require_governor()
    assert _pool != empty(address), "POOL"
    self._validate(_swap_fee_bps, _protocol_fee_share_bps, _imbalance_penalty_bps, _amp)
    if not self.tracked[_pool]:
        assert len(self.pools) < MAX_POOLS, "CAPACITY"
        self.pools.append(_pool)
        self.tracked[_pool] = True
        log PoolTracked(pool=_pool)
    self.swapFeeBps[_pool] = _swap_fee_bps
    self.protocolFeeShareBps[_pool] = _protocol_fee_share_bps
    self.imbalancePenaltyBps[_pool] = _imbalance_penalty_bps
    self.amp[_pool] = _amp
    log ParametersActivated(
        pool=_pool,
        swap_fee_bps=_swap_fee_bps,
        protocol_fee_share_bps=_protocol_fee_share_bps,
        imbalance_penalty_bps=_imbalance_penalty_bps,
        amp=_amp
    )


@external
def stageParameters(
    _pool: address,
    _swap_fee_bps: uint256,
    _protocol_fee_share_bps: uint256,
    _imbalance_penalty_bps: uint256,
    _amp: uint256,
    _delay: uint256
):
    self._require_governor()
    assert self.tracked[_pool], "POOL"
    assert _delay <= MAX_DELAY, "DELAY"
    self._validate(_swap_fee_bps, _protocol_fee_share_bps, _imbalance_penalty_bps, _amp)
    self.pendingSwapFeeBps[_pool] = _swap_fee_bps
    self.pendingProtocolFeeShareBps[_pool] = _protocol_fee_share_bps
    self.pendingImbalancePenaltyBps[_pool] = _imbalance_penalty_bps
    self.pendingAmp[_pool] = _amp
    self.pendingActivation[_pool] = block.timestamp + _delay
    log ParametersStaged(
        pool=_pool,
        swap_fee_bps=_swap_fee_bps,
        protocol_fee_share_bps=_protocol_fee_share_bps,
        imbalance_penalty_bps=_imbalance_penalty_bps,
        amp=_amp,
        activate_after=self.pendingActivation[_pool]
    )


@external
def cancelParameters(_pool: address):
    self._require_governor()
    assert self.pendingActivation[_pool] > 0, "PENDING"
    self.pendingActivation[_pool] = 0
    self.pendingSwapFeeBps[_pool] = 0
    self.pendingProtocolFeeShareBps[_pool] = 0
    self.pendingImbalancePenaltyBps[_pool] = 0
    self.pendingAmp[_pool] = 0
    log ParametersCancelled(pool=_pool)


@external
def activateParameters(_pool: address):
    self._require_governor()
    assert self.pendingActivation[_pool] > 0, "PENDING"
    assert block.timestamp >= self.pendingActivation[_pool], "EARLY"
    self.swapFeeBps[_pool] = self.pendingSwapFeeBps[_pool]
    self.protocolFeeShareBps[_pool] = self.pendingProtocolFeeShareBps[_pool]
    self.imbalancePenaltyBps[_pool] = self.pendingImbalancePenaltyBps[_pool]
    self.amp[_pool] = self.pendingAmp[_pool]
    self.pendingActivation[_pool] = 0
    log ParametersActivated(
        pool=_pool,
        swap_fee_bps=self.swapFeeBps[_pool],
        protocol_fee_share_bps=self.protocolFeeShareBps[_pool],
        imbalance_penalty_bps=self.imbalancePenaltyBps[_pool],
        amp=self.amp[_pool]
    )


@external
@view
def poolCount() -> uint256:
    return len(self.pools)


@external
@view
def poolAt(_index: uint256) -> address:
    assert _index < len(self.pools), "INDEX"
    return self.pools[_index]


@external
@view
def currentParameters(_pool: address) -> (uint256, uint256, uint256, uint256):
    assert self.tracked[_pool], "POOL"
    return self.swapFeeBps[_pool], self.protocolFeeShareBps[_pool], self.imbalancePenaltyBps[_pool], self.amp[_pool]


@external
@view
def pendingParameters(_pool: address) -> (uint256, uint256, uint256, uint256, uint256):
    return (
        self.pendingSwapFeeBps[_pool],
        self.pendingProtocolFeeShareBps[_pool],
        self.pendingImbalancePenaltyBps[_pool],
        self.pendingAmp[_pool],
        self.pendingActivation[_pool]
    )


@external
@view
def canActivate(_pool: address) -> bool:
    return self.pendingActivation[_pool] > 0 and block.timestamp >= self.pendingActivation[_pool]


@external
@view
def listPools(_offset: uint256, _limit: uint256) -> DynArray[address, MAX_POOLS]:
    out: DynArray[address, MAX_POOLS] = []
    count: uint256 = len(self.pools)
    if _offset >= count:
        return out
    end: uint256 = _offset + _limit
    if end > count:
        end = count
    for i: uint256 in range(MAX_POOLS):
        idx: uint256 = _offset + i
        if idx >= end:
            break
        out.append(self.pools[idx])
    return out
