# @version 0.4.3

"""
Local ERC-20 used by the Vesper test environment and deployment scripts.
The implementation keeps the behavior intentionally standard: fixed decimals,
allowance based spending, explicit mint authority, and no transfer hooks.
"""

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event MinterUpdated:
    account: indexed(address)
    allowed: bool

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

name: public(String[64])
symbol: public(String[16])
decimals: public(uint8)
totalSupply: public(uint256)
owner: public(address)

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
minters: public(HashMap[address, bool])


@deploy
def __init__(_name: String[64], _symbol: String[16], _decimals: uint8):
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals
    self.owner = msg.sender
    self.minters[msg.sender] = True
    log OwnershipTransferred(previous_owner=empty(address), new_owner=msg.sender)
    log MinterUpdated(account=msg.sender, allowed=True)


@internal
def _require_owner():
    assert msg.sender == self.owner, "OWNER"


@internal
def _require_minter():
    assert self.minters[msg.sender], "MINTER"


@internal
def _transfer(_from: address, _to: address, _amount: uint256):
    assert _to != empty(address), "RECEIVER"
    assert self.balanceOf[_from] >= _amount, "BALANCE"
    self.balanceOf[_from] -= _amount
    self.balanceOf[_to] += _amount
    log Transfer(sender=_from, receiver=_to, value=_amount)


@external
def transfer(_to: address, _amount: uint256) -> bool:
    self._transfer(msg.sender, _to, _amount)
    return True


@external
def approve(_spender: address, _amount: uint256) -> bool:
    assert _spender != empty(address), "SPENDER"
    self.allowance[msg.sender][_spender] = _amount
    log Approval(owner=msg.sender, spender=_spender, value=_amount)
    return True


@external
def transferFrom(_from: address, _to: address, _amount: uint256) -> bool:
    allowed: uint256 = self.allowance[_from][msg.sender]
    assert allowed >= _amount, "ALLOWANCE"
    if allowed != max_value(uint256):
        self.allowance[_from][msg.sender] = allowed - _amount
        log Approval(owner=_from, spender=msg.sender, value=allowed - _amount)
    self._transfer(_from, _to, _amount)
    return True


@external
def increaseAllowance(_spender: address, _added: uint256) -> bool:
    assert _spender != empty(address), "SPENDER"
    new_allowance: uint256 = self.allowance[msg.sender][_spender] + _added
    self.allowance[msg.sender][_spender] = new_allowance
    log Approval(owner=msg.sender, spender=_spender, value=new_allowance)
    return True


@external
def decreaseAllowance(_spender: address, _subtracted: uint256) -> bool:
    current: uint256 = self.allowance[msg.sender][_spender]
    assert current >= _subtracted, "ALLOWANCE"
    new_allowance: uint256 = current - _subtracted
    self.allowance[msg.sender][_spender] = new_allowance
    log Approval(owner=msg.sender, spender=_spender, value=new_allowance)
    return True


@external
def mint(_to: address, _amount: uint256):
    self._require_minter()
    assert _to != empty(address), "RECEIVER"
    self.totalSupply += _amount
    self.balanceOf[_to] += _amount
    log Transfer(sender=empty(address), receiver=_to, value=_amount)


@external
def burn(_amount: uint256):
    assert self.balanceOf[msg.sender] >= _amount, "BALANCE"
    self.balanceOf[msg.sender] -= _amount
    self.totalSupply -= _amount
    log Transfer(sender=msg.sender, receiver=empty(address), value=_amount)


@external
def burnFrom(_from: address, _amount: uint256):
    allowed: uint256 = self.allowance[_from][msg.sender]
    assert allowed >= _amount, "ALLOWANCE"
    if allowed != max_value(uint256):
        self.allowance[_from][msg.sender] = allowed - _amount
        log Approval(owner=_from, spender=msg.sender, value=allowed - _amount)
    assert self.balanceOf[_from] >= _amount, "BALANCE"
    self.balanceOf[_from] -= _amount
    self.totalSupply -= _amount
    log Transfer(sender=_from, receiver=empty(address), value=_amount)


@external
def setMinter(_account: address, _allowed: bool):
    self._require_owner()
    assert _account != empty(address), "ACCOUNT"
    self.minters[_account] = _allowed
    log MinterUpdated(account=_account, allowed=_allowed)


@external
def transferOwnership(_new_owner: address):
    self._require_owner()
    assert _new_owner != empty(address), "OWNER"
    previous: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(previous_owner=previous, new_owner=_new_owner)


@external
@view
def circulatingSupply() -> uint256:
    return self.totalSupply


@external
@view
def availableAllowance(_owner: address, _spender: address) -> uint256:
    return self.allowance[_owner][_spender]


@external
@view
def balanceSnapshot(_account: address) -> (uint256, uint256):
    return self.balanceOf[_account], self.totalSupply


@external
@view
def metadata() -> (String[64], String[16], uint8):
    return self.name, self.symbol, self.decimals
