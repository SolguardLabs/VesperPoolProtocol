# @version 0.4.3

"""
Governance registry for Vesper pools. It tracks canonical pools by token pair,
operational status, deployment metadata and conservative parameter envelopes.
"""

MAX_POOLS: constant(uint256) = 512
BPS: constant(uint256) = 10_000

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event PoolRegistered:
    pool: indexed(address)
    token0: indexed(address)
    token1: indexed(address)
    amp: uint256
    swap_fee_bps: uint256
    label: String[64]

event PoolStatusUpdated:
    pool: indexed(address)
    active: bool
    deprecated: bool

event PoolMetadataUpdated:
    pool: indexed(address)
    label: String[64]
    risk_tier: uint256
    notes_hash: bytes32

event RegistryParameterUpdated:
    max_fee_bps: uint256
    max_amp: uint256
    max_risk_tier: uint256


owner: public(address)
maxFeeBps: public(uint256)
maxAmp: public(uint256)
maxRiskTier: public(uint256)

pools: DynArray[address, MAX_POOLS]
registered: public(HashMap[address, bool])
active: public(HashMap[address, bool])
deprecated: public(HashMap[address, bool])

poolToken0: public(HashMap[address, address])
poolToken1: public(HashMap[address, address])
poolAmp: public(HashMap[address, uint256])
poolSwapFeeBps: public(HashMap[address, uint256])
poolRiskTier: public(HashMap[address, uint256])
poolLabel: public(HashMap[address, String[64]])
poolNotesHash: public(HashMap[address, bytes32])
poolByPair: public(HashMap[address, HashMap[address, address]])


@deploy
def __init__():
    self.owner = msg.sender
    self.maxFeeBps = 100
    self.maxAmp = 25_000
    self.maxRiskTier = 5
    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)
    log RegistryParameterUpdated(max_fee_bps=self.maxFeeBps, max_amp=self.maxAmp, max_risk_tier=self.maxRiskTier)


@internal
@view
def _require_owner():
    assert msg.sender == self.owner, "OWNER"


@internal
@pure
def _nonzero_pair(_token0: address, _token1: address):
    assert _token0 != empty(address), "TOKEN0"
    assert _token1 != empty(address), "TOKEN1"
    assert _token0 != _token1, "TOKENS"


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
def setRegistryParameters(_max_fee_bps: uint256, _max_amp: uint256, _max_risk_tier: uint256):
    self._require_owner()
    assert _max_fee_bps <= BPS, "FEE"
    assert _max_amp > 0, "AMP"
    assert _max_risk_tier > 0, "RISK"
    self.maxFeeBps = _max_fee_bps
    self.maxAmp = _max_amp
    self.maxRiskTier = _max_risk_tier
    log RegistryParameterUpdated(max_fee_bps=_max_fee_bps, max_amp=_max_amp, max_risk_tier=_max_risk_tier)


@external
def registerPool(
    _pool: address,
    _token0: address,
    _token1: address,
    _amp: uint256,
    _swap_fee_bps: uint256,
    _risk_tier: uint256,
    _label: String[64],
    _notes_hash: bytes32
):
    self._require_owner()
    assert _pool != empty(address), "POOL"
    self._nonzero_pair(_token0, _token1)
    assert not self.registered[_pool], "REGISTERED"
    assert self.poolByPair[_token0][_token1] == empty(address), "PAIR"
    assert _amp <= self.maxAmp, "AMP"
    assert _swap_fee_bps <= self.maxFeeBps, "FEE"
    assert _risk_tier <= self.maxRiskTier, "RISK"
    assert len(self.pools) < MAX_POOLS, "CAPACITY"

    self.pools.append(_pool)
    self.registered[_pool] = True
    self.active[_pool] = True
    self.poolToken0[_pool] = _token0
    self.poolToken1[_pool] = _token1
    self.poolAmp[_pool] = _amp
    self.poolSwapFeeBps[_pool] = _swap_fee_bps
    self.poolRiskTier[_pool] = _risk_tier
    self.poolLabel[_pool] = _label
    self.poolNotesHash[_pool] = _notes_hash
    self.poolByPair[_token0][_token1] = _pool
    self.poolByPair[_token1][_token0] = _pool
    log PoolRegistered(
        pool=_pool,
        token0=_token0,
        token1=_token1,
        amp=_amp,
        swap_fee_bps=_swap_fee_bps,
        label=_label
    )
    log PoolMetadataUpdated(pool=_pool, label=_label, risk_tier=_risk_tier, notes_hash=_notes_hash)


@external
def setPoolStatus(_pool: address, _active: bool, _deprecated: bool):
    self._require_owner()
    assert self.registered[_pool], "POOL"
    self.active[_pool] = _active
    self.deprecated[_pool] = _deprecated
    log PoolStatusUpdated(pool=_pool, active=_active, deprecated=_deprecated)


@external
def updatePoolMetadata(_pool: address, _label: String[64], _risk_tier: uint256, _notes_hash: bytes32):
    self._require_owner()
    assert self.registered[_pool], "POOL"
    assert _risk_tier <= self.maxRiskTier, "RISK"
    self.poolLabel[_pool] = _label
    self.poolRiskTier[_pool] = _risk_tier
    self.poolNotesHash[_pool] = _notes_hash
    log PoolMetadataUpdated(pool=_pool, label=_label, risk_tier=_risk_tier, notes_hash=_notes_hash)


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
def findPool(_token_a: address, _token_b: address) -> address:
    self._nonzero_pair(_token_a, _token_b)
    return self.poolByPair[_token_a][_token_b]


@external
@view
def isListed(_pool: address) -> bool:
    return self.registered[_pool] and self.active[_pool] and not self.deprecated[_pool]


@external
@view
def poolTokens(_pool: address) -> (address, address):
    assert self.registered[_pool], "POOL"
    return self.poolToken0[_pool], self.poolToken1[_pool]


@external
@view
def poolParameters(_pool: address) -> (uint256, uint256, uint256, bool, bool):
    assert self.registered[_pool], "POOL"
    return (
        self.poolAmp[_pool],
        self.poolSwapFeeBps[_pool],
        self.poolRiskTier[_pool],
        self.active[_pool],
        self.deprecated[_pool]
    )


@external
@view
def poolMetadata(_pool: address) -> (String[64], bytes32):
    assert self.registered[_pool], "POOL"
    return self.poolLabel[_pool], self.poolNotesHash[_pool]


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


@external
@view
def activePools(_offset: uint256, _limit: uint256) -> DynArray[address, MAX_POOLS]:
    out: DynArray[address, MAX_POOLS] = []
    seen: uint256 = 0
    emitted: uint256 = 0
    for i: uint256 in range(MAX_POOLS):
        if i >= len(self.pools):
            break
        pool: address = self.pools[i]
        if self.active[pool] and not self.deprecated[pool]:
            if seen >= _offset and emitted < _limit:
                out.append(pool)
                emitted += 1
            seen += 1
    return out
