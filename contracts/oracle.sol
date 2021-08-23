// // SPDX-Licenses-Identifier: MIT
// pragma solidity ^0.6.7;

// import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";

// contract APIConsumer is ChainlinkClient {
//     using Chainlink for Chainlink.Request;

//     uint256 public volume;

//     address private oracle;
//     bytes32 private jobId;
//     uint256 private fee;

//     /** 
//     * Network: Kovan
//     * Fee: 0.1 LINK
//     */

//     constructor() public {
//         setPublicChainlinkToken();
//         oracle = 0xc57B33452b4F7BB189bB5AfaE9cc4aBa1f7a4FD8;
//         jobId = "d5270d1c311941d0b08bead21fea7747";
//         fee = 0.1 * 10 ** 18;
//     }

//     function requestsVolumeData() public returns (bytes32 requestId)
//     {
//         Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

//         request.add("get", "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD");

//         request.add("path", "RAW.ETH.USD.VOLUME24HOUR");

//         int timesAmount = 10**18;
//         request.addInt("times", timesAmount);

//         return sendChainlinkRequestTo(oracle, request, fee);
//     }
// }