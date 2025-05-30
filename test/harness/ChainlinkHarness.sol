// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/loan/lib/Chainlink.sol";


contract ChainlinkHarness {

    function checkSequencerUptime(IChainlinkAggregatorLike l2SequencerUptimeFeed) external view {
        return Chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

    function fetchCreditPriceWithCollateralDenomination(
        IChainlinkFeedRegistryLike feedRegistry,
        address creditAsset,
        address collateralAsset,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) external view returns (uint256, uint8) {
        return Chainlink.fetchCreditPriceWithCollateralDenomination(
            feedRegistry, creditAsset, collateralAsset, feedIntermediaryDenominations, feedInvertFlags
        );
    }

    function convertPriceDenomination(
        IChainlinkFeedRegistryLike feedRegistry,
        uint256 currentPrice,
        uint8 currentDecimals,
        address currentDenomination,
        address nextDenomination,
        bool nextInvert
    ) external view returns (uint256, uint8) {
        return Chainlink.convertPriceDenomination(
            feedRegistry, currentPrice, currentDecimals, currentDenomination, nextDenomination, nextInvert
        );
    }

    function fetchPrice(IChainlinkFeedRegistryLike feedRegistry, address asset, address denomination)
        external
        view
        returns (uint256, uint8)
    {
        return Chainlink.fetchPrice(feedRegistry, asset, denomination);
    }

    function syncDecimalsUp(uint256 price1, uint8 decimals1, uint256 price2, uint8 decimals2)
        external
        pure
        returns (uint256, uint256, uint8)
    {
        return Chainlink.syncDecimalsUp(price1, decimals1, price2, decimals2);
    }

}
