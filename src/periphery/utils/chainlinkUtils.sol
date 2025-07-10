// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Chainlink } from "pwn/periphery/lib/Chainlink.sol";

/**
 * @notice Flips the order of price feed intermediary denominations and invert flags.
 * @dev This function is used to reverse the order of intermediary denominations and invert flags for Chainlink feeds.
 * @param feedInvertFlags Array of boolean flags indicating if the feed should be inverted at each step.
 * @param feedIntermediaryDenominations Array of intermediary denomination addresses for Chainlink feed conversion.
 * @return flippedFeedInvertFlags Flipped array of boolean flags.
 * @return flippedFeedIntermediaryDenominations Flipped array of intermediary denomination addresses.
 */
function flipFeeds(
    bool[] memory feedInvertFlags,
    address[] memory feedIntermediaryDenominations
) pure returns (bool[] memory flippedFeedInvertFlags, address[] memory flippedFeedIntermediaryDenominations) {
    uint256 length = feedInvertFlags.length;
    flippedFeedInvertFlags = new bool[](length);
    for (uint256 i; i < length; ++i)
        flippedFeedInvertFlags[i] = !feedInvertFlags[length - i - 1];

    length = feedIntermediaryDenominations.length;
    flippedFeedIntermediaryDenominations = new address[](length);
    for (uint256 i; i < length; ++i)
        flippedFeedIntermediaryDenominations[i] = feedIntermediaryDenominations[length - i - 1];
}

/**
 * @notice Encodes price feed intermediary denominations and invert flags into a bytes array.
 * @dev Reverts if input array lengths are invalid or if the number of intermediary denominations exceeds the maximum allowed.
 * @param feedInvertFlags Array of boolean flags indicating if the feed should be inverted at each step. Must be one longer than denominations.
 * @param feedIntermediaryDenominations Array of intermediary denomination addresses for Chainlink feed conversion.
 * @return data Custom encoded data containing Chainlink price feed configuration. Always encoded as 1 byte of inverted flag and 20 bytes of intermediary denomination address per step.
 */
function encodeChainlinkPriceFeedData(
    bool[] memory feedInvertFlags,
    address[] memory feedIntermediaryDenominations,
    uint256 maxChainlinkIntermediaryDenominations
) pure returns (bytes memory data) {
    if (feedIntermediaryDenominations.length + 1 != feedInvertFlags.length) {
        revert Chainlink.ChainlinkInvalidInputLenghts();
    }
    uint256 intermediaryDenominationsLength = feedIntermediaryDenominations.length;
    if (intermediaryDenominationsLength > maxChainlinkIntermediaryDenominations) {
        revert Chainlink.IntermediaryDenominationsOutOfBounds(
            intermediaryDenominationsLength,
            maxChainlinkIntermediaryDenominations
        );
    }

    for (uint256 i; i < intermediaryDenominationsLength; ++i) {
        data = abi.encodePacked(data, feedInvertFlags[i], feedIntermediaryDenominations[i]);
    }
    data = abi.encodePacked(data, feedInvertFlags[intermediaryDenominationsLength]);
}

/**
 * @notice Decodes a bytes array into price feed intermediary denominations and invert flags.
 * @dev The input data must be encoded as per _encodePriceFeedData.
 * @param data Custom encoded data containing Chainlink price feed configuration. Always encoded as 1 byte of inverted flag and 20 bytes of intermediary denomination address per step.
 * @return feedInvertFlags Array of boolean flags indicating if the feed should be inverted at each step.
 * @return feedIntermediaryDenominations Array of intermediary denomination addresses for Chainlink feed conversion.
 */
function decodeChainlinkPriceFeedData(
    bytes memory data
) pure returns (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations) {
    uint256 intermediaryDenominationsLength = (data.length - 1) / 21;

    feedInvertFlags = new bool[](intermediaryDenominationsLength + 1);
    feedIntermediaryDenominations = new address[](intermediaryDenominationsLength);

    for (uint256 i; i < intermediaryDenominationsLength; ++i) {
        feedInvertFlags[i] = data[i * 21] == bytes1(0x01);
        address addr;
        assembly {
            addr := shr(96, mload(add(add(data, 0x20), add(mul(i, 21), 1))))
        }
        feedIntermediaryDenominations[i] = addr;
    }
    feedInvertFlags[intermediaryDenominationsLength] = data[data.length - 1] == bytes1(0x01);
}
