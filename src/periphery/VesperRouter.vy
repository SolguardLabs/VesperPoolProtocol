# @version 0.4.3

interface ERC20:
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable

interface Pool:
    def token0() -> address: view
    def token1() -> address: view
    def addLiquidity(amount0: uint256, amount1: uint256, min_shares: uint256, receiver: address) -> uint256: nonpayable
    def removeLiquidity(shares: uint256, min0: uint256, min1: uint256, receiver: address) -> (uint256, uint256): nonpayable
    def removeLiquidityImbalanced(amount0: uint256, amount1: uint256, max_shares: uint256, receiver: address) -> uint256: nonpayable
    def swap(token_in: address, amount_in: uint256, min_out: uint256, receiver: address) -> uint256: nonpayable
    def quoteSwap(token_in: address, amount_in: uint256) -> (uint256, uint256): view
    def quoteAddLiquidity(amount0: uint256, amount1: uint256) -> uint256: view
    def quoteRemoveLiquidity(shares: uint256) -> (uint256, uint256): view
    def quoteRemoveLiquidityImbalanced(amount0: uint256, amount1: uint256) -> (uint256, uint256): view


event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event PoolTrustUpdated:
    pool: indexed(address)
    trusted: bool

event RouterPaused:
    paused: bool

event RoutedLiquidityAdded:
    pool: indexed(address)
    sender: indexed(address)
    receiver: indexed(address)
    amount0: uint256
    amount1: uint256
    shares: uint256

event RoutedLiquidityRemoved:
    pool: indexed(address)
    sender: indexed(address)
    receiver: indexed(address)
    shares: uint256
    amount0: uint256
    amount1: uint256

event RoutedImbalancedRemoval:
    pool: indexed(address)
    sender: indexed(address)
    receiver: indexed(address)
    amount0: uint256
    amount1: uint256
    shares: uint256

event RoutedSwap:
    pool: indexed(address)
    sender: indexed(address)
    receiver: indexed(address)
    token_in: address
    amount_in: uint256
    amount_out: uint256


owner: public(address)
paused: public(bool)
trustedPools: public(HashMap[address, bool])
locked: bool


@deploy
def __init__():
    self.owner = msg.sender
    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)


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
@view
def _require_pool(_pool: address):
    assert _pool != empty(address), "POOL"
    assert self.trustedPools[_pool], "UNTRUSTED_POOL"


@internal
@view
def _check_deadline(_deadline: uint256):
    assert _deadline >= block.timestamp, "DEADLINE"


@internal
def _approve_exact(_token: address, _spender: address, _amount: uint256):
    ok_reset: bool = extcall ERC20(_token).approve(_spender, 0, default_return_value=True)
    assert ok_reset, "APPROVE_RESET"
    ok: bool = extcall ERC20(_token).approve(_spender, _amount, default_return_value=True)
    assert ok, "APPROVE"


@external
def setTrustedPool(_pool: address, _trusted: bool):
    self._require_owner()
    assert _pool != empty(address), "POOL"
    self.trustedPools[_pool] = _trusted
    log PoolTrustUpdated(pool=_pool, trusted=_trusted)


@external
def setPaused(_paused: bool):
    self._require_owner()
    self.paused = _paused
    log RouterPaused(paused=_paused)


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
def addLiquidity(
    _pool: address,
    _amount0: uint256,
    _amount1: uint256,
    _min_shares: uint256,
    _receiver: address,
    _deadline: uint256
) -> uint256:
    self._enter()
    self._require_live()
    self._require_pool(_pool)
    self._check_deadline(_deadline)
    assert _receiver != empty(address), "RECEIVER"

    token0: address = staticcall Pool(_pool).token0()
    token1: address = staticcall Pool(_pool).token1()
    ok0: bool = extcall ERC20(token0).transferFrom(msg.sender, self, _amount0, default_return_value=True)
    ok1: bool = extcall ERC20(token1).transferFrom(msg.sender, self, _amount1, default_return_value=True)
    assert ok0 and ok1, "TRANSFER_IN"
    self._approve_exact(token0, _pool, _amount0)
    self._approve_exact(token1, _pool, _amount1)

    shares: uint256 = extcall Pool(_pool).addLiquidity(_amount0, _amount1, _min_shares, _receiver)
    log RoutedLiquidityAdded(
        pool=_pool,
        sender=msg.sender,
        receiver=_receiver,
        amount0=_amount0,
        amount1=_amount1,
        shares=shares
    )
    self._exit()
    return shares


@external
def removeLiquidity(
    _pool: address,
    _shares: uint256,
    _min0: uint256,
    _min1: uint256,
    _receiver: address,
    _deadline: uint256
) -> (uint256, uint256):
    self._enter()
    self._require_live()
    self._require_pool(_pool)
    self._check_deadline(_deadline)
    assert _receiver != empty(address), "RECEIVER"

    ok_in: bool = extcall ERC20(_pool).transferFrom(msg.sender, self, _shares, default_return_value=True)
    assert ok_in, "SHARE_IN"
    self._approve_exact(_pool, _pool, _shares)
    amount0: uint256 = 0
    amount1: uint256 = 0
    amount0, amount1 = extcall Pool(_pool).removeLiquidity(_shares, _min0, _min1, _receiver)
    log RoutedLiquidityRemoved(
        pool=_pool,
        sender=msg.sender,
        receiver=_receiver,
        shares=_shares,
        amount0=amount0,
        amount1=amount1
    )
    self._exit()
    return amount0, amount1


@external
def removeLiquidityImbalanced(
    _pool: address,
    _amount0: uint256,
    _amount1: uint256,
    _max_shares: uint256,
    _receiver: address,
    _deadline: uint256
) -> uint256:
    self._enter()
    self._require_live()
    self._require_pool(_pool)
    self._check_deadline(_deadline)
    assert _receiver != empty(address), "RECEIVER"

    ok_in: bool = extcall ERC20(_pool).transferFrom(msg.sender, self, _max_shares, default_return_value=True)
    assert ok_in, "SHARE_IN"
    self._approve_exact(_pool, _pool, _max_shares)
    shares_used: uint256 = extcall Pool(_pool).removeLiquidityImbalanced(_amount0, _amount1, _max_shares, _receiver)

    if _max_shares > shares_used:
        refund: uint256 = _max_shares - shares_used
        ok_refund: bool = extcall ERC20(_pool).transfer(msg.sender, refund, default_return_value=True)
        assert ok_refund, "SHARE_REFUND"

    log RoutedImbalancedRemoval(
        pool=_pool,
        sender=msg.sender,
        receiver=_receiver,
        amount0=_amount0,
        amount1=_amount1,
        shares=shares_used
    )
    self._exit()
    return shares_used


@external
def swapExactIn(
    _pool: address,
    _token_in: address,
    _amount_in: uint256,
    _min_out: uint256,
    _receiver: address,
    _deadline: uint256
) -> uint256:
    self._enter()
    self._require_live()
    self._require_pool(_pool)
    self._check_deadline(_deadline)
    assert _receiver != empty(address), "RECEIVER"

    ok_in: bool = extcall ERC20(_token_in).transferFrom(msg.sender, self, _amount_in, default_return_value=True)
    assert ok_in, "TRANSFER_IN"
    self._approve_exact(_token_in, _pool, _amount_in)
    amount_out: uint256 = extcall Pool(_pool).swap(_token_in, _amount_in, _min_out, _receiver)
    log RoutedSwap(
        pool=_pool,
        sender=msg.sender,
        receiver=_receiver,
        token_in=_token_in,
        amount_in=_amount_in,
        amount_out=amount_out
    )
    self._exit()
    return amount_out


@external
@view
def quoteAddLiquidity(_pool: address, _amount0: uint256, _amount1: uint256) -> uint256:
    self._require_pool(_pool)
    return staticcall Pool(_pool).quoteAddLiquidity(_amount0, _amount1)


@external
@view
def quoteRemoveLiquidity(_pool: address, _shares: uint256) -> (uint256, uint256):
    self._require_pool(_pool)
    return staticcall Pool(_pool).quoteRemoveLiquidity(_shares)


@external
@view
def quoteRemoveLiquidityImbalanced(_pool: address, _amount0: uint256, _amount1: uint256) -> (uint256, uint256):
    self._require_pool(_pool)
    return staticcall Pool(_pool).quoteRemoveLiquidityImbalanced(_amount0, _amount1)


@external
@view
def quoteSwap(_pool: address, _token_in: address, _amount_in: uint256) -> (uint256, uint256):
    self._require_pool(_pool)
    return staticcall Pool(_pool).quoteSwap(_token_in, _amount_in)


@external
@view
def pairFor(_pool: address) -> (address, address):
    self._require_pool(_pool)
    return staticcall Pool(_pool).token0(), staticcall Pool(_pool).token1()
