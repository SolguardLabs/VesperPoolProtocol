# @version 0.4.3

interface IVesperPool:
    def token0() -> address: view
    def token1() -> address: view
    def reserves() -> (uint256, uint256): view
    def activeReserves() -> (uint256, uint256): view
    def protocolFees() -> (uint256, uint256): view
    def totalSupply() -> uint256: view
    def balanceOf(owner: address) -> uint256: view
    def allowance(owner: address, spender: address) -> uint256: view
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def quoteSwap(token_in: address, amount_in: uint256) -> (uint256, uint256): view
    def quoteAddLiquidity(amount0: uint256, amount1: uint256) -> uint256: view
    def quoteRemoveLiquidity(shares: uint256) -> (uint256, uint256): view
    def quoteRemoveLiquidityImbalanced(amount0: uint256, amount1: uint256) -> (uint256, uint256): view
    def addLiquidity(amount0: uint256, amount1: uint256, min_shares: uint256, receiver: address) -> uint256: nonpayable
    def removeLiquidity(shares: uint256, min0: uint256, min1: uint256, receiver: address) -> (uint256, uint256): nonpayable
    def removeLiquidityImbalanced(amount0: uint256, amount1: uint256, max_shares: uint256, receiver: address) -> uint256: nonpayable
    def swap(token_in: address, amount_in: uint256, min_out: uint256, receiver: address) -> uint256: nonpayable
