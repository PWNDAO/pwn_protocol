// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    flipFeeds as _flipFeeds,
    encodeChainlinkPriceFeedData as _encodeChainlinkPriceFeedData,
    decodeChainlinkPriceFeedData as _decodeChainlinkPriceFeedData,
    Chainlink
} from "pwn/periphery/utils/chainlinkUtils.sol";


contract ChainlinkUtilsHarness {

    function flipFeeds(
        bool[] memory feedInvertFlags,
        address[] memory feedIntermediaryDenominations
    ) external pure returns (bool[] memory flippedFeedInvertFlags, address[] memory flippedFeedIntermediaryDenominations) {
        return _flipFeeds(feedInvertFlags, feedIntermediaryDenominations);
    }

    function encodeChainlinkPriceFeedData(
        bool[] memory feedInvertFlags,
        address[] memory feedIntermediaryDenominations,
        uint256 maxChainlinkIntermediaryDenominations
    ) external pure returns (bytes memory data) {
        return _encodeChainlinkPriceFeedData(
            feedInvertFlags, feedIntermediaryDenominations, maxChainlinkIntermediaryDenominations
        );
    }

    function decodeChainlinkPriceFeedData(
        bytes memory data
    ) external pure returns (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations) {
        return _decodeChainlinkPriceFeedData(data);
    }

}
