import pytest
from brownie import ZERO_ADDRESS, accounts, options, chain
import brownie

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

def test_sell_purchase_option(_options_purchased, bob, dixie):
    with brownie.reverts("You are not the owner of this option"):
        _options_purchased.sellPurchasedOption(0, 4, {"from": dixie})
    _options_purchased.sellPurchasedOption(0, 3, {"from": bob})
    assert _options_purchased.viewOptionsForSale(0) == 3
    with brownie.reverts("This Option is already up for sale"):
        _options_purchased.sellPurchasedOption(0, 5, {"from": bob})
    
    _options_purchased.createOption(0, "UNI", 5_184_000, "buy", "American", {"from": dixie, "value": "12 ether"})
    with brownie.reverts("This option is still up for sale"):
        _options_purchased.sellPurchasedOption(1, 20, {"from": dixie})

def test_buy_purchase_option(_options_purchased, bob, dixie):
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

def test_rebalance_option_buyer(_options, bob, charles):
    _options.createOption(0, "COMP", 1_296_000, "buy", "European", {"from": bob, "value": "15 ether"})
    with brownie.reverts("You are not the owner of this option"):
        _options.rebalanceOption("COMP", 0, {"from": charles})
    