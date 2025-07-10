// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    flipFeeds,
    encodeChainlinkPriceFeedData,
    decodeChainlinkPriceFeedData,
    Chainlink
} from "pwn/periphery/utils/chainlinkUtils.sol";


contract FlipFeeds_Test is Test {

    function test_shouldFlipFeeds() external {
        bool[] memory feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = true;
        feedInvertFlags[1] = false;
        feedInvertFlags[2] = false;

        address[] memory feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = makeAddr("intermediary1");
        feedIntermediaryDenominations[1] = makeAddr("intermediary2");

        (bool[] memory flippedFeedInvertFlags, address[] memory flippedFeedIntermediaryDenominations) =
            flipFeeds(feedInvertFlags, feedIntermediaryDenominations);

        assertEq(flippedFeedInvertFlags.length, 3);
        assertEq(flippedFeedIntermediaryDenominations.length, 2);

        assertTrue(flippedFeedInvertFlags[0]);
        assertTrue(flippedFeedInvertFlags[1]);
        assertFalse(flippedFeedInvertFlags[2]);

        assertEq(flippedFeedIntermediaryDenominations[0], feedIntermediaryDenominations[1]);
        assertEq(flippedFeedIntermediaryDenominations[1], feedIntermediaryDenominations[0]);
    }

}


contract EncodeDecodeChainlinkPriceFeedData_Test is Test {

    uint256 maxDenominations = 4;

    function testFuzz_shouldFail_whenFeedInvertFlagsAndFeedIntermediaryDenominationsLengthMismatch(
        uint256 invertFlagsLength,
        uint256 intermediaryDenominationsLength
    ) external {
        invertFlagsLength = bound(invertFlagsLength, 1, 5);
        intermediaryDenominationsLength = bound(intermediaryDenominationsLength, 1, 4);
        vm.assume(invertFlagsLength != intermediaryDenominationsLength + 1);

        bool[] memory feedInvertFlags = new bool[](invertFlagsLength);
        address[] memory feedIntermediaryDenominations = new address[](intermediaryDenominationsLength);

        vm.expectRevert(Chainlink.ChainlinkInvalidInputLenghts.selector);
        encodeChainlinkPriceFeedData(feedInvertFlags, feedIntermediaryDenominations, maxDenominations);
    }

    function test_shouldEncodeZeroLengthFeedInvertFlagsAndInermediaryDenominations() external {
        bytes memory encodedData = encodeChainlinkPriceFeedData(new bool[](0), new address[](0), maxDenominations);

        assertEq(encodedData.length, 0);
    }

    function test_shouldFail_whenFeedItermediaryDenominationsOverMax() external {
        bool[] memory feedInvertFlags = new bool[](6);
        address[] memory feedIntermediaryDenominations = new address[](5);

        vm.expectRevert(abi.encodeWithSelector(Chainlink.IntermediaryDenominationsOutOfBounds.selector, 5, 4));
        encodeChainlinkPriceFeedData(feedInvertFlags, feedIntermediaryDenominations, maxDenominations);
    }

    function test_shouldEncodePriceFeedData() external {
        bool[] memory feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = true;
        feedInvertFlags[1] = false;
        feedInvertFlags[2] = true;

        address[] memory feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = makeAddr("intermediary1");
        feedIntermediaryDenominations[1] = makeAddr("intermediary2");

        bytes memory encodedData = encodeChainlinkPriceFeedData(
            feedInvertFlags, feedIntermediaryDenominations, maxDenominations
        );

        assertEq(
            keccak256(encodedData),
            keccak256(abi.encodePacked(feedInvertFlags[0], feedIntermediaryDenominations[0], feedInvertFlags[1], feedIntermediaryDenominations[1], feedInvertFlags[2]))
        );

        (bool[] memory decodedFeedInvertFlags, address[] memory decodedFeedIntermediaryDenominations) =
            decodeChainlinkPriceFeedData(encodedData);

        assertEq(decodedFeedInvertFlags.length, 3);
        assertEq(decodedFeedIntermediaryDenominations.length, 2);
        for (uint256 i; i < 3; ++i) assertEq(decodedFeedInvertFlags[i], feedInvertFlags[i]);
        for (uint256 i; i < 2; ++i) assertEq(decodedFeedIntermediaryDenominations[i], feedIntermediaryDenominations[i]);
    }

    function test_shouldDecodeEmptyPriceFeedData() external {
        (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations) =
            decodeChainlinkPriceFeedData("");

        assertEq(feedInvertFlags.length, 0);
        assertEq(feedIntermediaryDenominations.length, 0);
    }

}
