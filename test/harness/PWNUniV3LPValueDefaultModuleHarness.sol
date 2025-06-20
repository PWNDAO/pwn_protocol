// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNUniV3LPValueDefaultModule,
    PWNHub, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike, INonfungiblePositionManager
} from "pwn/periphery/loan/module/default/PWNUniV3LPValueDefaultModule.sol";


contract PWNUniV3LPValueDefaultModuleHarness is PWNUniV3LPValueDefaultModule {

    constructor(
        PWNHub _hub,
        INonfungiblePositionManager uniswapV3PositionManager,
        address uniswapV3Factory,
        IChainlinkAggregatorLike chainlinkL2SequencerUptimeFeed,
        IChainlinkFeedRegistryLike chainlinkFeedRegistry,
        address weth
    ) PWNUniV3LPValueDefaultModule(
        _hub,
        uniswapV3PositionManager,
        uniswapV3Factory,
        chainlinkL2SequencerUptimeFeed,
        chainlinkFeedRegistry,
        weth
    ) {}


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
