// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceConsumerV3 {

    AggregatorV3Interface internal uniPriceFeed;
    AggregatorV3Interface internal mkrPriceFeed;
    AggregatorV3Interface internal aavePriceFeed;

    /**
     * Network: Kovan
     * Aggregator: ETH/USD
     * Address: 0x9326BFA02ADD2366b30bacB125260Af641031331
     */
    constructor() {
        uniPriceFeed = AggregatorV3Interface(0x17756515f112429471F86f98D5052aCB6C47f6ee);
        mkrPriceFeed = AggregatorV3Interface(0xECF93D14d25E02bA2C13698eeDca9aA98348EFb6);
        aavePriceFeed = AggregatorV3Interface(0xd04647B7CB523bb9f26730E9B6dE1174db7591Ad);
    }

    /**
     * Returns the latest price
     */
    function getLatestUniPrice() public view returns (uint256) {
        (,int price,,,) = uniPriceFeed.latestRoundData();
        return uint256(price * 1000000000000000000);
    }
    
    function getLatestMkrPrice() public view returns (uint256) {
        (,int price,,,) = mkrPriceFeed.latestRoundData();
        return uint256(price * 1000000000000000000);
    }
    
    function getLatestAavePrice() public view returns (uint256) {
        (,int price,,,) = aavePriceFeed.latestRoundData();
        return uint256(price * 1000000000000000000);
    }
    
    function getConversionPrice(uint256 amount, string memory asset) public view returns (uint256) {
        if (keccak256(abi.encodePacked(asset)) == keccak256(abi.encodePacked("UNI"))) {
            return (getLatestUniPrice() * amount) / 1000000000000000000;
        } else if (keccak256(abi.encodePacked(asset)) == keccak256(abi.encodePacked("MKR"))) {
            return (getLatestMkrPrice() * amount) / 1000000000000000000;
        } else if (keccak256(abi.encodePacked(asset)) == keccak256(abi.encodePacked("AAVE"))) {
            return (getLatestAavePrice() * amount) / 1000000000000000000;
        }
    }
}