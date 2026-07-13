from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import boa
import pytest

ROOT = Path(__file__).resolve().parents[1]
TOKEN_SOURCE = ROOT / "src" / "tokens" / "VesperMockERC20.vy"
POOL_SOURCE = ROOT / "src" / "core" / "VesperPool.vy"
LENS_SOURCE = ROOT / "src" / "periphery" / "VesperPoolLens.vy"
ROUTER_SOURCE = ROOT / "src" / "periphery" / "VesperRouter.vy"
ORACLE_SOURCE = ROOT / "src" / "oracle" / "VesperPegOracle.vy"

UNIT = 10**18
POOL_AMP = 800
SWAP_FEE_BPS = 4
PROTOCOL_FEE_SHARE_BPS = 500
IMBALANCE_PENALTY_BPS = 1_500


@dataclass(frozen=True)
class Accounts:
    owner: str
    alice: str
    bob: str
    carol: str
    keeper: str
    fee_receiver: str


@dataclass
class PoolFixture:
    accounts: Accounts
    token0: object
    token1: object
    pool: object
    lens: object
    router: object
    oracle: object


def wad(amount: int | float) -> int:
    return int(amount * UNIT)


@pytest.fixture()
def accounts() -> Accounts:
    return Accounts(
        owner=boa.env.eoa,
        alice=boa.env.generate_address("alice"),
        bob=boa.env.generate_address("bob"),
        carol=boa.env.generate_address("carol"),
        keeper=boa.env.generate_address("keeper"),
        fee_receiver=boa.env.generate_address("fee_receiver"),
    )


@pytest.fixture()
def deployed(accounts: Accounts) -> PoolFixture:
    token0 = boa.load(str(TOKEN_SOURCE), "Vesper Dollar", "vUSD", 18)
    token1 = boa.load(str(TOKEN_SOURCE), "Vesper Euro", "vEUR", 18)
    pool = boa.load(
        str(POOL_SOURCE),
        token0.address,
        token1.address,
        "Vesper Stable Pool",
        "vsp-LP",
        POOL_AMP,
        SWAP_FEE_BPS,
        PROTOCOL_FEE_SHARE_BPS,
        IMBALANCE_PENALTY_BPS,
        accounts.fee_receiver,
    )
    lens = boa.load(str(LENS_SOURCE))
    router = boa.load(str(ROUTER_SOURCE))
    oracle = boa.load(str(ORACLE_SOURCE))

    router.setTrustedPool(pool.address, True)
    oracle.configureAsset(token0.address, 86_400, 1_000, "vUSD")
    oracle.configureAsset(token1.address, 86_400, 1_000, "vEUR")
    oracle.recordPrices(token0.address, UNIT, token1.address, UNIT)

    for account in (accounts.alice, accounts.bob, accounts.carol):
        token0.mint(account, wad(5_000_000))
        token1.mint(account, wad(5_000_000))
        with boa.env.prank(account):
            token0.approve(pool.address, 2**256 - 1)
            token1.approve(pool.address, 2**256 - 1)
            token0.approve(router.address, 2**256 - 1)
            token1.approve(router.address, 2**256 - 1)
            pool.approve(router.address, 2**256 - 1)

    return PoolFixture(accounts, token0, token1, pool, lens, router, oracle)


def seed_balanced_pool(fx: PoolFixture, amount: int = wad(1_000_000)) -> int:
    with boa.env.prank(fx.accounts.alice):
        return fx.pool.addLiquidity(amount, amount, 0, fx.accounts.alice)


def token_balances(fx: PoolFixture, account: str) -> tuple[int, int]:
    return fx.token0.balanceOf(account), fx.token1.balanceOf(account)
