# @version 0.4.3

interface IERC20:
    def name() -> String[64]: view
    def symbol() -> String[16]: view
    def decimals() -> uint8: view
    def totalSupply() -> uint256: view
    def balanceOf(owner: address) -> uint256: view
    def allowance(owner: address, spender: address) -> uint256: view
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
