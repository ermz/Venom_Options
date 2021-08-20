# @version ^0.2.0

"""
@title Venom Options
@license MIT
@author Edson Ramirez
@notice Create Options with tokens(CRV, UNI or COMP) at a fair price
@dev users can create options from "buyer" or "risk taker" standpoint. Can also rebalance and sell already purchased options
"""

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event OptionCreated:
    creator: indexed(address)
    ownerType: String[5]
    optionId: uint256
    strikePrice: decimal
    marketPrice: decimal
    duration: uint256

event OptionRebalanced:
    optionId: uint256
    strikePrice: decimal
    marketPrice: decimal

event OptionPurchased:
    optionId: uint256
    purchaser: indexed(address)

event OptionTransfer:
    optionId: uint256
    newOwner: indexed(address)

struct Option:
    optionId: uint256
    owner: address
    riskTaker: address
    underlyingTokenTicker: String[4]
    duration: uint256
    buySellType: String[4]
    optionType: String[8]
    strikePrice: decimal
    marketPrice: decimal
    startTime: uint256
    purchased: bool

# Each option is worth 10 tokens. Regardless of type of option (sell/buy)
SHARES_PER_OPTION: constant(decimal) = 10.0
WEI_CONVERSION_DEC: constant(decimal) = 1_000_000_000_000_000_000.0
WEI_CONVERSION: constant(uint256) = 1_000_000_000_000_000_000

# Duration variable
FIFTEEN_DAYS: constant(uint256) = 1_296_000
THIRTY_DAYS: constant(uint256) = 2_592_000
SIXTY_DAYS: constant(uint256) = 5_184_000

# All Options (Curve, Uniswap, Compound)
optionsLedger: HashMap[uint256, Option]
optionsCounter: uint256

tokenToPrice: HashMap[String[4], uint256]

durationMultiplier: HashMap[uint256, decimal]

sellerLedger: HashMap[String[4], HashMap[uint256, decimal]]

buyerLedger: HashMap[String[4], HashMap[uint256, decimal]]

creatorType: HashMap[uint256, String[5]]

# Optioin ID to option price for sale
optionsForSale: HashMap[uint256, uint256]

@external
def __init__(_crv_price: uint256, _uni_price: uint256, _comp_price: uint256):
    self.tokenToPrice["CRV"] = _crv_price
    self.tokenToPrice["UNI"] = _uni_price
    self.tokenToPrice["COMP"] = _comp_price

    self.durationMultiplier[1_296_000] = 0.1
    self.durationMultiplier[2_592_000] = 0.3
    self.durationMultiplier[5_184_000] = 0.5

    self.creatorType[0] = "buyer"
    self.creatorType[1] = "taker"


@external
def updateTokenPrice(_ticker: String[4], _price: uint256):
    assert self.tokenToPrice[_ticker] != 0, "This token is not supported"
    self.tokenToPrice[_ticker] = _price


@external
@view
def viewOption(_optionId: uint256) -> Option:
    """
    @notice Return option based on option ID provided
    """
    return self.optionsLedger[_optionId]


@internal
def strikePrice(currentAssetPrice: decimal, _duration: uint256, _buySellType: String[4], _optionType: String[8]) -> decimal:
    """
    @notice Will calculate current strike price based on asset price, duration, buy&sell type and option type
    @dev Calculation are done in decimal for calculation simplicity
    @return Returns current strike price (type decimal) based on given parameters
    """
    duration_multiplier: decimal = 0.0
    option_type_multiplier: decimal = 0.0

    duration_multiplier = self.durationMultiplier[_duration] * currentAssetPrice
    
    if _optionType == "American":
        option_type_multiplier = 0.1 * currentAssetPrice
    else:
        option_type_multiplier = 0.4 * currentAssetPrice

    total_multiplier: decimal = duration_multiplier + option_type_multiplier

    return  total_multiplier


@external
@payable
def createOption(ownerType: uint256, _ticker: String[4], _duration: uint256, _buySellType: String[4], _optionType: String[8]):
    """
    @notice Creates an option and will allow another user to buy into the option later on
    @dev Option created will either have an owner or riskTaker but not both. The purchaser or option will complete the missing Option attribute
    @param ownerType will either be 0 or 1. This will indicate whether caller is a owner or riskTaker. Owner pays 10 * strikprice and riskTaker pays 10 * marketPrice
    @param _ticker will be a String[4] that will either be CRV, UNI or COMP token ticker
    @param _duration will either be 15 days, 30 days or 60 days in seconds
    @param _buySellType will either be buy or sell
    @param _optionType refers to American or European. The type of option will affect strike price and calling options
    """
    assert self.tokenToPrice[_ticker] > 0, "This token is not supported"
    assert _duration == FIFTEEN_DAYS or _duration == THIRTY_DAYS or _duration == SIXTY_DAYS, "That is not an accepted duration"
    
    current_market_price: decimal = convert(self.tokenToPrice[_ticker], decimal)
    current_strike_price: decimal = self.strikePrice(current_market_price, _duration, _buySellType, _optionType)

    account_risk_taker: address = ZERO_ADDRESS
    account_buyer: address = ZERO_ADDRESS

    if self.creatorType[ownerType] == "buyer":
        assert convert(msg.value, decimal) >= (current_strike_price * SHARES_PER_OPTION * WEI_CONVERSION_DEC), "You aren't sending enough to cover the strike price * 100"
        account_buyer = msg.sender
    elif self.creatorType[ownerType] == "taker":
        assert convert(msg.value, decimal) >= (current_market_price * SHARES_PER_OPTION * WEI_CONVERSION_DEC), "You aren't sending enough to cover the market price * 100"
        account_risk_taker = msg.sender

    self.optionsLedger[self.optionsCounter] = Option({
        optionId: self.optionsCounter,
        owner: account_buyer,
        riskTaker: account_risk_taker,
        underlyingTokenTicker: _ticker,
        duration: _duration,
        buySellType: _buySellType,
        optionType: _optionType,
        strikePrice: current_strike_price,
        marketPrice: current_market_price,
        startTime: block.timestamp,
        purchased: False
    })
    self.sellerLedger[_ticker][self.optionsCounter] = (current_market_price * 10.0)
    self.buyerLedger[_ticker][self.optionsCounter] = (current_strike_price * 10.0)
    self.optionsCounter += 1
    log OptionCreated(msg.sender, self.creatorType[ownerType], (self.optionsCounter - 1), current_strike_price, current_market_price, _duration)
    log Transfer(msg.sender, self, msg.value)


@external
@payable
def buyOption(_optionId: uint256):
    """
    @notice Allows users to buy into an Option that was already created as either the owner or riskTaker
    @dev
        users have to complete the option by being the other user(owner/riskTaker) and pay 10 times strike/market price
        Once a purchase is confirmed. The contract will send the strike price * 10 to the riskTaker.
        The amount(market price * 10) that the riskTaker send to the contract stays with us until Option time is expired.
        If option is used than owner will use those funds to buy/sell funds at an agreed upon price.
        If option isn't called, option duration and call duration have elapsed riskTaker will be able to retrieve their ether back
    """
    current_option: Option = self.optionsLedger[_optionId]
    assert current_option.purchased == False, "Option has been purchased"

    if current_option.owner == ZERO_ADDRESS and current_option.riskTaker != ZERO_ADDRESS:
        assert convert(msg.value, decimal) >= (current_option.strikePrice * SHARES_PER_OPTION * WEI_CONVERSION_DEC), "Amount sent insufficient for purchase (strike price * 100)"
        send(current_option.riskTaker, convert((current_option.strikePrice * SHARES_PER_OPTION * WEI_CONVERSION_DEC), uint256))
        self.optionsLedger[_optionId].owner = msg.sender
        self.optionsLedger[_optionId].purchased = True
        log Transfer(msg.sender, self, msg.value)
        log Transfer(self, current_option.riskTaker, msg.value)
    elif current_option.riskTaker == ZERO_ADDRESS and current_option.owner != ZERO_ADDRESS:
        assert convert(msg.value, decimal) >= (current_option.marketPrice * SHARES_PER_OPTION * WEI_CONVERSION_DEC), "Amount sent insufficient for purchase (market price * 100)"
        self.optionsLedger[_optionId].riskTaker = msg.sender
        self.optionsLedger[_optionId].purchased = True
        send(msg.sender, convert(current_option.strikePrice * SHARES_PER_OPTION * WEI_CONVERSION_DEC, uint256))
        log Transfer(self, msg.sender, convert((current_option.strikePrice * SHARES_PER_OPTION), uint256))
    
    log OptionPurchased(_optionId, msg.sender)
   
@external
@view
def viewOptionsForSale(_optionId: uint256) -> uint256:
    return self.optionsForSale[_optionId]

@external
def sellPurchasedOption(_optionId: uint256, _price: uint256):
    """
    @notice If you have an option that has been purchased, you can sell ownership to someone else(another address)
    @dev The option needs to have been purchased already, and only the owner of Option can sell it
    @param _price is the price you wish to sell your Option
    """
    assert self.optionsForSale[_optionId] == 0, "This Option is already up for sale"

    assert self.optionsLedger[_optionId].owner == msg.sender, "You are not the owner of this option"
    assert self.optionsLedger[_optionId].purchased == True, "This option is still up for sale"
    self.optionsForSale[_optionId] = _price


@external
@payable
def buyPurchasedOption(_optionId: uint256):
    """
    @notice Purchase a option that is up for sale
    @dev function will check if option is up for sale and whether enough is sent to purchase option
    @param _optionId refers to id of option that user wishes to buy
    """
    assert self.optionsForSale[_optionId] != 0, "Not for sale"
    assert msg.value >= (self.optionsForSale[_optionId] * WEI_CONVERSION), "Insufficient funds for purchase"
    send(self.optionsLedger[_optionId].owner, msg.value)
    self.optionsLedger[_optionId].owner = msg.sender
    self.optionsForSale[_optionId] = 0

    log Transfer(msg.sender, self, msg.value)
    log Transfer(self, msg.sender, msg.value)
    log OptionTransfer(_optionId, msg.sender)

@external
def cashOut(_ticker: String[4], _optionId: uint256):
    """
    @notice users who are riskTaker can retrieve their funds once option time has elapsed and owner hasn't called option
    @dev 
        It also checks that riskTaker hasn't called function already and amount originally sent by riskTaker is returned
        Makes sure that it's been one day since option duration has elapsed. Owner has one day after option has ended to call option
    """

    assert self.sellerLedger[_ticker][_optionId] != 0.0, "There is nothing to collect"
    current_option: Option = self.optionsLedger[_optionId]

    assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this option"
    assert (current_option.startTime + current_option.duration + 86400) <= block.timestamp, "Buyer still has time to call option"
    send(msg.sender, convert(self.sellerLedger[_ticker][_optionId] * WEI_CONVERSION_DEC, uint256))

    log Transfer(self, msg.sender, convert(self.sellerLedger[_ticker][_optionId] * WEI_CONVERSION_DEC, uint256))
    self.sellerLedger[_ticker][_optionId] = 0.0


@external
def callOption(_ticker: String[4], _optionId: uint256):
    """
    @notice Users can call option to buy tokens or sell tokens at agreed strike price
    @dev
        Will check that it hasn't been past one day of option duration ending
        Will only allow European to be called once duration time has ended. American option can be called whenever
        User(owner) will receive funds stored in contract that reflect the agreed market price of token
        Will eventually check that owner transfers tokens that were agreed upon (maybe)
    """
    assert self.sellerLedger[_ticker][_optionId] != 0.0, "Option has been called already"
    current_option: Option = self.optionsLedger[_optionId]
    
    assert current_option.owner == msg.sender, "You are not the buyer of this option"
    assert current_option.purchased == True, "This option hasn't been purchased"
    assert (current_option.startTime + current_option.duration + 86400) > block.timestamp, "It's too late to call this option"

    if current_option.optionType == "European":
        assert (current_option.startTime + current_option.duration) < block.timestamp, "It's too early to call this European option"

    send(msg.sender, convert(self.sellerLedger[_ticker][_optionId] * WEI_CONVERSION_DEC, uint256))
    log Transfer(self, msg.sender, convert(self.sellerLedger[_ticker][_optionId] * WEI_CONVERSION_DEC, uint256))
    self.sellerLedger[_ticker][_optionId] = 0.0
    
    
@internal
def rebalanceStrikePrice(currentAssetPrice: decimal, start_time: uint256, duration: uint256, _optionType: String[8]) -> decimal:
    """
    @notice Rebalances strike price to a competitive price
    @buyer
        Given that original duration times were 60days, 30days and 15 days. The new strike price will be mostly affected
        new current market price(assuming it's changed) and time left for Option purchase. Can't call function if time has
        hit zero. As time decreases so does the price of the option
    @param currentAssetPrice will be the current market price(assuming it's changed since las time strike price was calculated)
    """
    time_left: uint256 = (start_time + duration) - block.timestamp
    time_difference: decimal = 0.0
    new_time_percentage: decimal = 0.0
    new_time_multiplier: decimal = 0.0

    assert time_left > 0, "There's no time left for rebalancing, buy time has ended"

    if time_left >= THIRTY_DAYS:
        time_difference = convert(time_left, decimal) - 2_592_000.0
        new_time_percentage = ((time_difference / 2_592_000.0) * 20.0) / 100.0 + 0.3
        new_time_multiplier = new_time_percentage * currentAssetPrice
    elif time_left >= FIFTEEN_DAYS:
        time_difference = convert(time_left, decimal) - 1_296_000.0
        new_time_percentage = ((time_difference / 1_296_000.0) * 20.0) / 100.0 + 0.1
        new_time_multiplier = new_time_percentage * currentAssetPrice
    else:
        new_time_percentage = ((convert(time_left, decimal) / 1_296_000.0) * 10.0) / 100.0
        new_time_multiplier = new_time_percentage * currentAssetPrice

    option_type_multiplier: decimal = 0.0

    if _optionType == "American":
        option_type_multiplier = 0.1 * currentAssetPrice
    else:
        option_type_multiplier = 0.4 * currentAssetPrice

    total_multiplier: decimal = new_time_multiplier + option_type_multiplier

    return total_multiplier
    

@external
@payable
def rebalanceOption(_ticker:String[4], _optionId:uint256):
    """
    @notice Will rebalance strike/market price and return/accept difference
    @dev
        This option will return the difference to user if strike/market price has gone down
        If the price has gone up than a Rebalance Order struct will be created
        User will have to call a separate function(rebalanceIncrease) to complete rebalance
        Function can't be called if Optiod duration has elapsed
    @param _optionId refers to the id of Option. User will have to be either owner or riskTaker to call function
    """
    assert self.sellerLedger[_ticker][_optionId] != 0.0, "This option does not exist"
    current_option: Option = self.optionsLedger[_optionId]
    current_token_price: decimal = convert(self.tokenToPrice[_ticker], decimal)
    new_strike_price: decimal = self.rebalanceStrikePrice(current_token_price,
                                                          current_option.startTime,
                                                          current_option.duration,
                                                          current_option.optionType
                                                          )
    assert current_option.purchased == False, "This option has been purchased already"

    if current_option.owner == ZERO_ADDRESS:
        assert current_option.riskTaker == msg.sender, "You are not the riskTaker of thsi option"
        balance_on_hold: decimal = self.sellerLedger[_ticker][_optionId]

        if current_token_price > current_option.marketPrice:
            # assert convert(msg.value, decimal) >= ((current_token_price * SHARES_PER_OPTION) - balance_on_hold) * WEI_CONVERSION_DEC, "You aren't sending enough to cover the cost"
            self.idToRebalance[_optionId] = RebalanceOrder({
                rebalancer: msg.sender,
                rebalancerType: "taker",
                newStrikePrice: new_strike_price,
                newMarketPrice: current_token_price,
                expirationTime: block.timestamp + 300
            })
        elif current_token_price < current_option.marketPrice:
            send(msg.sender, convert((balance_on_hold - (current_token_price * SHARES_PER_OPTION)) * WEI_CONVERSION_DEC, uint256))
            self.sellerLedger[_ticker][_optionId] = current_token_price * SHARES_PER_OPTION
            self.optionsLedger[_optionId].strikePrice = new_strike_price
            self.optionsLedger[_optionId].marketPrice = current_token_price

            log Transfer(msg.sender, self, convert((balance_on_hold - (current_token_price * SHARES_PER_OPTION)) * WEI_CONVERSION_DEC, uint256))
            log OptionRebalanced(_optionId, new_strike_price, current_token_price)
    elif current_option.riskTaker == ZERO_ADDRESS:
        assert current_option.owner == msg.sender, "You are not the owner of this option"
        balance_on_hold: decimal = self.buyerLedger[_ticker][_optionId]

        if new_strike_price > current_option.strikePrice:
            # assert convert(msg.value, decimal) >= ((new_strike_price * SHARES_PER_OPTION) - balance_on_hold) * WEI_CONVERSION_DEC, "You aren't sending enough to cover for the price increase of token"
            self.idToRebalance[_optionId] = RebalanceOrder({
                rebalancer: msg.sender,
                rebalancerType: "buyer",
                newStrikePrice: new_strike_price,
                newMarketPrice: current_token_price,
                expirationTime: block.timestamp + 300
            })
        elif new_strike_price < current_option.strikePrice:
            send(msg.sender, convert((balance_on_hold - (new_strike_price * SHARES_PER_OPTION)) * WEI_CONVERSION_DEC, uint256))

            self.buyerLedger[_ticker][_optionId] = new_strike_price * SHARES_PER_OPTION
            self.optionsLedger[_optionId].strikePrice = new_strike_price
            self.optionsLedger[_optionId].marketPrice = current_token_price

            log Transfer(self, msg.sender, convert((balance_on_hold - (new_strike_price * SHARES_PER_OPTION)) * WEI_CONVERSION_DEC, uint256))
            log OptionRebalanced(_optionId, new_strike_price, current_token_price)


struct RebalanceOrder:
    rebalancer: address
    rebalancerType: String[5]
    newStrikePrice: decimal
    newMarketPrice: decimal
    expirationTime: uint256

idToRebalance: HashMap[uint256, RebalanceOrder]

@external
@view
def viewRebalanceOrder(_optionId: uint256) -> RebalanceOrder:
    return self.idToRebalance[_optionId]

@external
@payable
def rebalanceIncrease(_ticker: String[4], _optionId: uint256):
    """
    @notice User will pay for rebalancing and Option will be updated
    @dev
        To call this function rebalanceOption function must have been called already
        User has to pay depending on new strike/market price
        Function will check that they pay within 5 minutes of initially calling rebalanceOption
        This is done to avoid someone getting a favorable price by waiting to call this function after the new strike/market price has been set
    """
    rebalancing_order: RebalanceOrder = self.idToRebalance[_optionId]
    assert rebalancing_order.rebalancer == msg.sender, "This balance order does not belong to you"
    assert block.timestamp <= rebalancing_order.expirationTime, "Out of time. Please create another rebalance order"

    if rebalancing_order.rebalancerType == "buyer":
        strike_price_difference: decimal = rebalancing_order.newStrikePrice - self.optionsLedger[_optionId].strikePrice
        assert convert(msg.value, decimal) >= (strike_price_difference * SHARES_PER_OPTION * WEI_CONVERSION_DEC), "Insufficient funds to complete rebalaning increase"
        self.buyerLedger[_ticker][_optionId] = (rebalancing_order.newStrikePrice * SHARES_PER_OPTION)
        self.optionsLedger[_optionId].strikePrice = rebalancing_order.newStrikePrice
        self.optionsLedger[_optionId].marketPrice = rebalancing_order.newMarketPrice

        log Transfer(msg.sender, self, msg.value)
        log OptionRebalanced(_optionId, rebalancing_order.newStrikePrice, rebalancing_order.newMarketPrice)
    elif rebalancing_order.rebalancerType == "taker":
        market_price_difference: decimal = rebalancing_order.newMarketPrice - self.optionsLedger[_optionId].marketPrice
        assert convert(msg.value, decimal) >= (market_price_difference * SHARES_PER_OPTION * WEI_CONVERSION_DEC)
        self.sellerLedger[_ticker][_optionId] = (rebalancing_order.newMarketPrice * SHARES_PER_OPTION)
        self.optionsLedger[_optionId].strikePrice = rebalancing_order.newStrikePrice
        self.optionsLedger[_optionId].marketPrice = rebalancing_order.newMarketPrice

        log Transfer(msg.sender, self, msg.value)
        log OptionRebalanced(_optionId, rebalancing_order.newStrikePrice, rebalancing_order.newMarketPrice)

    self.idToRebalance[_optionId] = empty(RebalanceOrder)
   