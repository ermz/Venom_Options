import pytest
from brownie import options, accounts

@pytest.fixture()
def alice(accounts):
    return accounts[0]

@pytest.fixture()
def bob(accounts):
    return accounts[1]

@pytest.fixture()
def charles(accounts):
    return accounts[2]

@pytest.fixture()
def dixie(accounts):
    return accounts[3]

@pytest.fixture()
def eddy(accounts):
    return accounts[4]

@pytest.fixture()
def felix(accounts):
    return accounts[5]

@pytest.fixture()
def _options(alice):
    _options = options.deploy(1, 2, 3, {"from": alice})
    return _options

@pytest.fixture()
def _options_purchased(alice, bob, charles):
    _options_purchased = options.deploy(3, 2, 1, {"from": alice})
    _options_purchased.createOption(0, "COMP", 2_592_000, "buy", "European", {"from": bob, "value": "7 ether"})
    _options_purchased.buyOption(0, {"from": charles, "value": "10 ether"})
    return _options_purchased