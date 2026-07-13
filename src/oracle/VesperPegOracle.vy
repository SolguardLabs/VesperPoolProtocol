# @version 0.4.3

"""
Peg oracle for low-volatility Vesper pools. Prices are stored with 18 decimals
and can be used by off-chain keepers, routers and monitoring tools.
"""

BPS: constant(uint256) = 10_000
PRICE_SCALE: constant(uint256) = 10 ** 18
MAX_ASSETS: constant(uint256) = 256

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event ReporterUpdated:
    reporter: indexed(address)
    allowed: bool

event AssetConfigured:
    asset: indexed(address)
    heartbeat: uint256
    max_deviation_bps: uint256
    label: String[32]

event PriceRecorded:
    asset: indexed(address)
    price: uint256
    timestamp: uint256
    round_id: uint256


owner: public(address)
reporters: public(HashMap[address, bool])
assets: DynArray[address, MAX_ASSETS]
configured: public(HashMap[address, bool])
heartbeat: public(HashMap[address, uint256])
maxDeviationBps: public(HashMap[address, uint256])
assetLabel: public(HashMap[address, String[32]])
price: public(HashMap[address, uint256])
lastUpdated: public(HashMap[address, uint256])
roundId: public(HashMap[address, uint256])


@deploy
def __init__():
    self.owner = msg.sender
    self.reporters[msg.sender] = True
    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)
    log ReporterUpdated(reporter=msg.sender, allowed=True)


@internal
@view
def _require_owner():
    assert msg.sender == self.owner, "OWNER"


@internal
@view
def _require_reporter():
    assert self.reporters[msg.sender], "REPORTER"


@internal
@pure
def _abs_diff(a: uint256, b: uint256) -> uint256:
    if a > b:
        return a - b
    return b - a


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
def setReporter(_reporter: address, _allowed: bool):
    self._require_owner()
    assert _reporter != empty(address), "REPORTER"
    self.reporters[_reporter] = _allowed
    log ReporterUpdated(reporter=_reporter, allowed=_allowed)


@external
def configureAsset(_asset: address, _heartbeat: uint256, _max_deviation_bps: uint256, _label: String[32]):
    self._require_owner()
    assert _asset != empty(address), "ASSET"
    assert _heartbeat > 0, "HEARTBEAT"
    assert _max_deviation_bps <= BPS, "DEVIATION"
    if not self.configured[_asset]:
        assert len(self.assets) < MAX_ASSETS, "CAPACITY"
        self.assets.append(_asset)
    self.configured[_asset] = True
    self.heartbeat[_asset] = _heartbeat
    self.maxDeviationBps[_asset] = _max_deviation_bps
    self.assetLabel[_asset] = _label
    log AssetConfigured(asset=_asset, heartbeat=_heartbeat, max_deviation_bps=_max_deviation_bps, label=_label)


@external
def recordPrice(_asset: address, _price: uint256):
    self._require_reporter()
    assert self.configured[_asset], "ASSET"
    assert _price > 0, "PRICE"
    previous: uint256 = self.price[_asset]
    if previous > 0:
        deviation: uint256 = self._abs_diff(_price, previous) * BPS // previous
        assert deviation <= self.maxDeviationBps[_asset], "DEVIATION"
    self.price[_asset] = _price
    self.lastUpdated[_asset] = block.timestamp
    self.roundId[_asset] += 1
    log PriceRecorded(asset=_asset, price=_price, timestamp=block.timestamp, round_id=self.roundId[_asset])


@external
def recordPrices(_asset0: address, _price0: uint256, _asset1: address, _price1: uint256):
    self._require_reporter()
    assert self.configured[_asset0] and self.configured[_asset1], "ASSET"
    assert _price0 > 0 and _price1 > 0, "PRICE"

    previous0: uint256 = self.price[_asset0]
    previous1: uint256 = self.price[_asset1]
    if previous0 > 0:
        deviation0: uint256 = self._abs_diff(_price0, previous0) * BPS // previous0
        assert deviation0 <= self.maxDeviationBps[_asset0], "DEVIATION0"
    if previous1 > 0:
        deviation1: uint256 = self._abs_diff(_price1, previous1) * BPS // previous1
        assert deviation1 <= self.maxDeviationBps[_asset1], "DEVIATION1"

    self.price[_asset0] = _price0
    self.price[_asset1] = _price1
    self.lastUpdated[_asset0] = block.timestamp
    self.lastUpdated[_asset1] = block.timestamp
    self.roundId[_asset0] += 1
    self.roundId[_asset1] += 1
    log PriceRecorded(asset=_asset0, price=_price0, timestamp=block.timestamp, round_id=self.roundId[_asset0])
    log PriceRecorded(asset=_asset1, price=_price1, timestamp=block.timestamp, round_id=self.roundId[_asset1])


@external
@view
def assetCount() -> uint256:
    return len(self.assets)


@external
@view
def assetAt(_index: uint256) -> address:
    assert _index < len(self.assets), "INDEX"
    return self.assets[_index]


@external
@view
def isFresh(_asset: address) -> bool:
    if not self.configured[_asset]:
        return False
    updated: uint256 = self.lastUpdated[_asset]
    if updated == 0:
        return False
    return block.timestamp <= updated + self.heartbeat[_asset]


@external
@view
def latestPrice(_asset: address) -> (uint256, uint256, uint256, bool):
    assert self.configured[_asset], "ASSET"
    fresh: bool = False
    if self.lastUpdated[_asset] > 0:
        fresh = block.timestamp <= self.lastUpdated[_asset] + self.heartbeat[_asset]
    return self.price[_asset], self.lastUpdated[_asset], self.roundId[_asset], fresh


@external
@view
def quote(_base: address, _quote: address, _amount: uint256) -> uint256:
    assert self.configured[_base] and self.configured[_quote], "ASSET"
    assert self.price[_base] > 0 and self.price[_quote] > 0, "PRICE"
    return _amount * self.price[_base] // self.price[_quote]


@external
@view
def pairDeviationBps(_asset0: address, _asset1: address) -> uint256:
    assert self.configured[_asset0] and self.configured[_asset1], "ASSET"
    price0: uint256 = self.price[_asset0]
    price1: uint256 = self.price[_asset1]
    assert price0 > 0 and price1 > 0, "PRICE"
    return self._abs_diff(price0, price1) * BPS // price1


@external
@view
def pegStatus(_asset0: address, _asset1: address) -> (bool, uint256, uint256, uint256):
    assert self.configured[_asset0] and self.configured[_asset1], "ASSET"
    price0: uint256 = self.price[_asset0]
    price1: uint256 = self.price[_asset1]
    assert price0 > 0 and price1 > 0, "PRICE"
    deviation: uint256 = self._abs_diff(price0, price1) * BPS // price1
    allowed: uint256 = self.maxDeviationBps[_asset0]
    if self.maxDeviationBps[_asset1] < allowed:
        allowed = self.maxDeviationBps[_asset1]
    fresh: bool = False
    if self.lastUpdated[_asset0] > 0 and self.lastUpdated[_asset1] > 0:
        fresh = block.timestamp <= self.lastUpdated[_asset0] + self.heartbeat[_asset0]
        fresh = fresh and block.timestamp <= self.lastUpdated[_asset1] + self.heartbeat[_asset1]
    return fresh and deviation <= allowed, deviation, price0, price1


@external
@view
def listAssets(_offset: uint256, _limit: uint256) -> DynArray[address, MAX_ASSETS]:
    out: DynArray[address, MAX_ASSETS] = []
    count: uint256 = len(self.assets)
    if _offset >= count:
        return out
    end: uint256 = _offset + _limit
    if end > count:
        end = count
    for i: uint256 in range(MAX_ASSETS):
        idx: uint256 = _offset + i
        if idx >= end:
            break
        out.append(self.assets[idx])
    return out
