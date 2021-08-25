import pytest
from brownie import ZERO_ADDRESS, accounts, options, chain
from brownie.test import given, strategy
import brownie
from decimal import *

def test_create_options(_options, bob):
    with brownie.reverts("This token is not supported"):
        _options.createOption(0, "GRV", 1_296_000, "buy", "American", {"from": bob})
    with brownie.reverts("That is not an accepted duration"):
        _options.createOption(0, "CRV", 1_000_00, "sell", "European", {"from": bob})
    with brownie.reverts("You aren't sending enough to cover the strike price * 100"):
        _options.createOption(0, "CRV", 2_592_000, "buy", "American", {"from": bob, "value": "3 ether"})
    with brownie.reverts("You aren't sending enough to cover the market price * 100"):
        _options.createOption(1, "CRV", 2_592_000, "sell", "American", {"from": bob, "value": "9 ether"})
    _options.createOption(0, "CRV", 2_592_000, "buy", "American", {"from": bob, "value": "4 ether"})
    assert _options.viewOption(0)["owner"] == bob


def test_buy_option(_options, bob, charles, dixie):
    _options.createOption(0, "CRV", 1_296_000, "buy", "European", {"from": bob, "value": "5 ether"})
    assert _options.viewOption(0)["riskTaker"] == ZERO_ADDRESS
    with brownie.reverts("Amount sent insufficient for purchase (market price * 100)"):
        _options.buyOption(0, {"from": charles, "value": "9 ether"})
    _options.buyOption(0, {"from": charles, "value": "10 ether"})
    assert _options.viewOption(0)["riskTaker"] == charles
    with brownie.reverts("Option has been purchased"):
        _options.buyOption(0, {"from": dixie, "value": "10 ether"})
    _options.createOption(1, "CRV", 1_296_000, "sell", "American", {"from": charles, "value": "10 ether"})
    assert _options.viewOption(1)["riskTaker"] == charles
    origianl_charles_balance = charles.balance()
    _options.buyOption(1, {"from": bob, "value": "2 ether"})
    assert charles.balance() == origianl_charles_balance + "2 ether"
    assert _options.viewOption(1)["purchased"] == True

def test_sell_purchased_option(_options_purchased, bob, dixie):
    with brownie.reverts("You are not the owner of this option"):
        _options_purchased.sellPurchasedOption(0, 4, {"from": dixie})
    _options_purchased.sellPurchasedOption(0, 3, {"from": bob})
    assert _options_purchased.viewOptionsForSale(0) == 3
    with brownie.reverts("This Option is already up for sale"):
        _options_purchased.sellPurchasedOption(0, 5, {"from": bob})
    
    _options_purchased.createOption(0, "UNI", 5_184_000, "buy", "American", {"from": dixie, "value": "12 ether"})
    with brownie.reverts("This option is still up for sale"):
        _options_purchased.sellPurchasedOption(1, 20, {"from": dixie})


@given(cost=strategy('uint256', max_value = 20))
def test_option_variable_cost_seller(cost):
    property_option = options.deploy(1, 2, 3, {"from": accounts[8]})
    property_option.createOption(0, "CRV", 1_296_000, "buy", "American", {"from": accounts[8], "value": "2 ether"})
    property_option.buyOption(0, {"from": accounts[9], "value": "10 ether"})
    property_option.sellPurchasedOption(0, cost, {"from": accounts[8]})
    assert property_option.viewOptionsForSale(0) == cost

@given(price=strategy('uint256', min_value = 1, max_value = 4))
def test_option_variable_cost_buyer(price):
    property_option = options.deploy(price, 2, 3, {"from": accounts[8]})
    market_price = price * 10 * 1_000_000_000_000_000_000
    property_option.createOption(1, "CRV", 1_296_000, "buy", "American", {"from": accounts[8], "value": market_price})
    strike_price = 0.2 * price
    # assert price == price
    assert property_option.viewOption(0)["strikePrice"] == Decimal(strike_price).quantize(Decimal('0.01'), rounding=ROUND_DOWN)

@given(price=strategy('uint256', min_value = 1, max_value = 4))
def test_price_variable_seller(price):
    property_option = options.deploy(price, 2, 3, {"from": accounts[9]})
    strike_price = int(Decimal(price * 0.2).quantize(Decimal('0.01'), rounding=ROUND_DOWN) * Decimal("1_000_000_000_000_000_000.0")) * 10
    property_option.createOption(0, "CRV", 1_296_000, "buy", "American", {"from": accounts[9], "value": strike_price})
    assert property_option.viewOption(0)["marketPrice"] == price


def test_buy_purchased_option(_options_purchased, bob, dixie):
    with brownie.reverts("Not for sale"):
        _options_purchased.buyPurchasedOption(0, {"from": dixie})
    _options_purchased.sellPurchasedOption(0, 5, {"from": bob})
    with brownie.reverts("Insufficient funds for purchase"):
        _options_purchased.buyPurchasedOption(0, {"from": dixie, "value": "4 ether"})
    _options_purchased.buyPurchasedOption(0, {"from": dixie, "value": "5 ether"})
    assert _options_purchased.viewOption(0)["owner"] == dixie

def test_cashout(_options_purchased, charles, dixie):
    with brownie.reverts("There is nothing to collect"):
        _options_purchased.cashOut("UNI", 2)
    with brownie.reverts("You are not the riskTaker of this option"):
        _options_purchased.cashOut("COMP", 0, {"from": dixie})
    with brownie.reverts("Buyer still has time to call option"):
        _options_purchased.cashOut("COMP", 0, {"from": charles})
    chain.sleep(2_678_401)
    original_charles_balance = charles.balance()
    _options_purchased.cashOut("COMP", 0, {"from": charles})
    assert charles.balance() == original_charles_balance + "10 ether"

def test_call_option_fail(_options_purchased, bob, dixie):
    with brownie.reverts("You are not the buyer of this option"):
        _options_purchased.callOption("COMP", 0, {"from": dixie})
    with brownie.reverts("It's too early to call this European option"):
        _options_purchased.callOption("COMP", 0, {"from": bob})
    chain.sleep(2_678_401)
    with brownie.reverts("It's too late to call this option"):
        _options_purchased.callOption("COMP", 0, {"from": bob})
    _options_purchased.createOption(0, "UNI", 2_592_000, "buy", "American", {"from": bob, "value": "8 ether"})
    with brownie.reverts("This option hasn't been purchased"):
        _options_purchased.callOption("UNI", 1, {"from": bob})

def test_call_option_success(_options_purchased, bob):
    chain.sleep(2_592_001)
    original_bob_balance = bob.balance()
    _options_purchased.callOption("COMP", 0, {"from": bob})
    with brownie.reverts("Option has been called already"):
        _options_purchased.callOption("COMP", 0, {"from": bob})
    assert bob.balance() == original_bob_balance + "10 ether"

def test_rebalance_option_fail(_options_purchased, bob):
    with brownie.reverts("This option does not exist"):
        _options_purchased.rebalanceOption("UNI", 2, {"from": bob})
    with brownie.reverts("This option has been purchased already"):
        _options_purchased.rebalanceOption("COMP", 0, {"from": bob})

def test_rebalance_option_buyer_lower_strike_price(_options, bob, charles):
    _options.createOption(0, "COMP", 1_296_000, "buy", "European", {"from": bob, "value": "15 ether"})
    with brownie.reverts("You are not the owner of this option"):
        _options.rebalanceOption("COMP", 0, {"from": charles})
    _options.updateTokenPrice("COMP", 1)
    original_bob_balance = bob.balance()
    _options.rebalanceOption("COMP", 0, {"from": bob})
    assert bob.balance() > original_bob_balance

def test_rebalance_option_buyer_higher_strike_price(_options, bob, charles):
    _options.createOption(0, "UNI", 1_296_000, "buy", "European", {"from": bob, "value": "10 ether"})
    _options.updateTokenPrice("UNI", 3)
    _options.rebalanceOption("UNI", 0, {"from": bob})
    assert _options.viewRebalanceOrder(0)["rebalancer"] == bob
    with brownie.reverts("This balance order does not belong to you"):
        _options.rebalanceIncrease("UNI", 0, {"from": charles})
    new_strike_price = _options.viewRebalanceOrder(0)["newStrikePrice"]
    with brownie.reverts("Insufficient funds to complete rebalaning increase"):
        _options.rebalanceIncrease("UNI", 0, {"from": bob, "value": "4 ether"})
    assert _options.viewOption(0)["strikePrice"] == 1
    _options.rebalanceIncrease("UNI", 0, {"from": bob, "value": "5 ether"})
    assert _options.viewOption(0)["strikePrice"] == new_strike_price

def test_rebalance_option_seller_lower_market_price(_options, bob):
    _options.createOption(1, "UNI", 1_296_000, "sell", "American", {"from": bob, "value": "20 ether"})
    _options.updateTokenPrice("UNI", 1)
    original_bob_balance = bob.balance()
    _options.rebalanceOption("UNI", 0, {"from": bob})
    assert original_bob_balance < bob.balance()
    assert _options.viewOption(0)["marketPrice"] == 1

def test_rebalance_option_seller_lower_market_price(_options, charles):
    _options.createOption(1, "UNI", 1_296_000, "sell", "American", {"from": charles, "value": "20 ether"})
    _options.updateTokenPrice("UNI", 3)
    _options.rebalanceOption("UNI", 0, {"from": charles})
    assert _options.viewOption(0)["marketPrice"] == 2
    _options.rebalanceIncrease("UNI", 0, {"from": charles, "value": "10 ether"})
    assert _options.viewOption(0)["marketPrice"] == 3
    
def test_events_buyer_create(_options, dixie, eddy):
    tx1 = _options.createOption(0, "CRV", 2_592_000, "buy", "American", {"from": dixie, "value": "4 ether"})
    assert len(tx1.events) == 2
    assert tx1.events[0]["creator"] == dixie
    assert tx1.events[1]["value"] == "4 ether"

    tx2 = _options.buyOption(0, {"from": eddy, "value": "10 ether"})
    assert len(tx2.events) == 2
    assert tx2.events[0]["sender"] == _options
    assert tx2.events[1]["optionId"] == 0

    _options.sellPurchasedOption(0, 3, {"from": dixie})
    tx3 = _options.buyPurchasedOption(0, {"from": eddy, "value": "3 ether"})
    assert len(tx3.events) == 3
    assert tx3.events[0]["sender"] == eddy
    assert tx3.events[1]["sender"] == _options
    assert tx3.events[2]["optionId"] == 0

    tx4 = _options.callOption("CRV", 0, {"from": eddy})
    assert len(tx4.events) == 1
    assert tx4.events[0]["sender"] == _options

def test_events_seller_create(_options, felix, eddy):
    tx1 = _options.createOption(1, "CRV", 2_592_000, "sell", "European", {"from": felix, "value": "10 ether"})
    assert len(tx1.events) == 2
    assert tx1.events[0]["duration"] == 2_592_000
    assert tx1.events[1]["receiver"] == _options

    _options.updateTokenPrice("CRV", 2)

    tx2 = _options.rebalanceOption("CRV", 0, {"from": felix})
    assert not tx2.events

    tx3 = _options.rebalanceIncrease("CRV", 0, {"from": felix, "value": "10 ether"})
    assert len(tx3.events) == 2
    assert tx3.events[0]["value"] == "10 ether"
    assert tx3.events[1]["optionId"] == 0

    _options.updateTokenPrice("CRV", 1)

    tx4 = _options.rebalanceOption("CRV", 0, {"from": felix})
    assert len(tx4.events) == 2
    assert tx4.events[0]["value"] == "10 ether"
    assert tx4.events[1]["marketPrice"] == 1

    chain.sleep(2_678_401)

    tx5 = _options.cashOut("CRV", 0, {"from": felix})
    assert len(tx5.events) == 1
    assert tx5.events[0]["value"] == "10 ether"

