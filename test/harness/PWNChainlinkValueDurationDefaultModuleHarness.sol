// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNChainlinkValueDurationDefaultModule,
    PWNHub, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike
} from "pwn/periphery/loan/module/default/PWNChainlinkValueDurationDefaultModule.sol";


contract PWNChainlinkValueDurationDefaultModuleHarness is PWNChainlinkValueDurationDefaultModule {

    constructor(
        PWNHub _hub,
        IChainlinkAggregatorLike chainlinkL2SequencerUptimeFeed,
        IChainlinkFeedRegistryLike chainlinkFeedRegistry,
        address weth
    ) PWNChainlinkValueDurationDefaultModule(_hub, chainlinkL2SequencerUptimeFeed, chainlinkFeedRegistry, weth) {}


    function exposed_encodePriceFeedData(
        bool[] memory feedInvertFlags,
        address[] memory feedIntermediaryDenominations
    ) external pure returns (bytes memory) {
        return _encodePriceFeedData(feedInvertFlags, feedIntermediaryDenominations);
    }

    function exposed_decodePriceFeedData(bytes memory data) external pure returns (bool[] memory, address[] memory) {
        return _decodePriceFeedData(data);
    }

}
