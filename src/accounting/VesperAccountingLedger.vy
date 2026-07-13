# @version 0.4.3

"""
Snapshot ledger for Vesper pool accounting. Operators can record reserve,
fee and supply checkpoints for downstream reconciliation and monitoring.
"""

interface Pool:
    def reserves() -> (uint256, uint256): view
    def activeReserves() -> (uint256, uint256): view
    def protocolFees() -> (uint256, uint256): view
    def totalSupply() -> uint256: view
    def invariant() -> uint256: view
    def spotImbalance() -> uint256: view

MAX_POOLS: constant(uint256) = 512
MAX_EPOCHS: constant(uint256) = 1_000_000

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event KeeperUpdated:
    keeper: indexed(address)
    allowed: bool

event PoolTracked:
    pool: indexed(address)

event SnapshotRecorded:
    pool: indexed(address)
    epoch: indexed(uint256)
    reserve0: uint256
    reserve1: uint256
    supply: uint256
    invariant_value: uint256

event SnapshotAnnotated:
    pool: indexed(address)
    epoch: indexed(uint256)
    note_hash: bytes32


owner: public(address)
keepers: public(HashMap[address, bool])
pools: DynArray[address, MAX_POOLS]
tracked: public(HashMap[address, bool])
currentEpoch: public(HashMap[address, uint256])

snapshotReserve0: public(HashMap[address, HashMap[uint256, uint256]])
snapshotReserve1: public(HashMap[address, HashMap[uint256, uint256]])
snapshotActive0: public(HashMap[address, HashMap[uint256, uint256]])
snapshotActive1: public(HashMap[address, HashMap[uint256, uint256]])
snapshotFee0: public(HashMap[address, HashMap[uint256, uint256]])
snapshotFee1: public(HashMap[address, HashMap[uint256, uint256]])
snapshotSupply: public(HashMap[address, HashMap[uint256, uint256]])
snapshotInvariant: public(HashMap[address, HashMap[uint256, uint256]])
snapshotImbalance: public(HashMap[address, HashMap[uint256, uint256]])
snapshotTimestamp: public(HashMap[address, HashMap[uint256, uint256]])
snapshotNoteHash: public(HashMap[address, HashMap[uint256, bytes32]])


@deploy
def __init__():
    self.owner = msg.sender
    self.keepers[msg.sender] = True
    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)
    log KeeperUpdated(keeper=msg.sender, allowed=True)


@internal
@view
def _require_owner():
    assert msg.sender == self.owner, "OWNER"


@internal
@view
def _require_keeper():
    assert self.keepers[msg.sender], "KEEPER"


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
def setKeeper(_keeper: address, _allowed: bool):
    self._require_owner()
    assert _keeper != empty(address), "KEEPER"
    self.keepers[_keeper] = _allowed
    log KeeperUpdated(keeper=_keeper, allowed=_allowed)


@external
def trackPool(_pool: address):
    self._require_keeper()
    assert _pool != empty(address), "POOL"
    if not self.tracked[_pool]:
        assert len(self.pools) < MAX_POOLS, "CAPACITY"
        self.tracked[_pool] = True
        self.pools.append(_pool)
        log PoolTracked(pool=_pool)


@external
def recordSnapshot(_pool: address, _note_hash: bytes32) -> uint256:
    self._require_keeper()
    assert self.tracked[_pool], "POOL"
    epoch: uint256 = self.currentEpoch[_pool] + 1
    assert epoch < MAX_EPOCHS, "EPOCH"

    reserve0: uint256 = 0
    reserve1: uint256 = 0
    active0: uint256 = 0
    active1: uint256 = 0
    fee0: uint256 = 0
    fee1: uint256 = 0
    reserve0, reserve1 = staticcall Pool(_pool).reserves()
    active0, active1 = staticcall Pool(_pool).activeReserves()
    fee0, fee1 = staticcall Pool(_pool).protocolFees()

    self.currentEpoch[_pool] = epoch
    self.snapshotReserve0[_pool][epoch] = reserve0
    self.snapshotReserve1[_pool][epoch] = reserve1
    self.snapshotActive0[_pool][epoch] = active0
    self.snapshotActive1[_pool][epoch] = active1
    self.snapshotFee0[_pool][epoch] = fee0
    self.snapshotFee1[_pool][epoch] = fee1
    self.snapshotSupply[_pool][epoch] = staticcall Pool(_pool).totalSupply()
    self.snapshotInvariant[_pool][epoch] = staticcall Pool(_pool).invariant()
    self.snapshotImbalance[_pool][epoch] = staticcall Pool(_pool).spotImbalance()
    self.snapshotTimestamp[_pool][epoch] = block.timestamp
    self.snapshotNoteHash[_pool][epoch] = _note_hash

    log SnapshotRecorded(
        pool=_pool,
        epoch=epoch,
        reserve0=reserve0,
        reserve1=reserve1,
        supply=self.snapshotSupply[_pool][epoch],
        invariant_value=self.snapshotInvariant[_pool][epoch]
    )
    if _note_hash != empty(bytes32):
        log SnapshotAnnotated(pool=_pool, epoch=epoch, note_hash=_note_hash)
    return epoch


@external
def annotateSnapshot(_pool: address, _epoch: uint256, _note_hash: bytes32):
    self._require_keeper()
    assert self.tracked[_pool], "POOL"
    assert _epoch > 0 and _epoch <= self.currentEpoch[_pool], "EPOCH"
    self.snapshotNoteHash[_pool][_epoch] = _note_hash
    log SnapshotAnnotated(pool=_pool, epoch=_epoch, note_hash=_note_hash)


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
def latestSnapshot(_pool: address) -> (
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256
):
    epoch: uint256 = self.currentEpoch[_pool]
    assert epoch > 0, "SNAPSHOT"
    return (
        epoch,
        self.snapshotReserve0[_pool][epoch],
        self.snapshotReserve1[_pool][epoch],
        self.snapshotSupply[_pool][epoch],
        self.snapshotInvariant[_pool][epoch],
        self.snapshotImbalance[_pool][epoch],
        self.snapshotTimestamp[_pool][epoch],
        self.snapshotFee0[_pool][epoch] + self.snapshotFee1[_pool][epoch]
    )


@external
@view
def snapshotReserves(_pool: address, _epoch: uint256) -> (uint256, uint256, uint256, uint256):
    assert _epoch > 0 and _epoch <= self.currentEpoch[_pool], "EPOCH"
    return (
        self.snapshotReserve0[_pool][_epoch],
        self.snapshotReserve1[_pool][_epoch],
        self.snapshotActive0[_pool][_epoch],
        self.snapshotActive1[_pool][_epoch]
    )


@external
@view
def snapshotFees(_pool: address, _epoch: uint256) -> (uint256, uint256):
    assert _epoch > 0 and _epoch <= self.currentEpoch[_pool], "EPOCH"
    return self.snapshotFee0[_pool][_epoch], self.snapshotFee1[_pool][_epoch]


@external
@view
def snapshotMeta(_pool: address, _epoch: uint256) -> (uint256, uint256, uint256, bytes32):
    assert _epoch > 0 and _epoch <= self.currentEpoch[_pool], "EPOCH"
    return (
        self.snapshotSupply[_pool][_epoch],
        self.snapshotInvariant[_pool][_epoch],
        self.snapshotTimestamp[_pool][_epoch],
        self.snapshotNoteHash[_pool][_epoch]
    )


@external
@view
def invariantDelta(_pool: address, _from_epoch: uint256, _to_epoch: uint256) -> int256:
    assert _from_epoch > 0 and _to_epoch > 0, "EPOCH"
    assert _from_epoch <= self.currentEpoch[_pool] and _to_epoch <= self.currentEpoch[_pool], "RANGE"
    from_value: uint256 = self.snapshotInvariant[_pool][_from_epoch]
    to_value: uint256 = self.snapshotInvariant[_pool][_to_epoch]
    if to_value >= from_value:
        return convert(to_value - from_value, int256)
    return -convert(from_value - to_value, int256)


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
