// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IChainlinkAggregatorLike } from "pwn/periphery/interfaces/IChainlinkAggregatorLike.sol";


/**
 * @title IChainlinkFeedRegistryLike
 * @notice Chainlink Feed Registry Interface.
 */
interface IChainlinkFeedRegistryLike {

    /**
     * @notice Get the Chainlink aggregator for a given base and quote asset.
     * @param base Base asset address.
     * @param quote Quote asset address.
     * @return aggregator Chainlink aggregator for the given base and quote asset.
     */
    function getFeed(address base, address quote) external view returns (IChainlinkAggregatorLike aggregator);

    /**
     * @notice Allows an owner to begin transferring ownership to a new address,
     * pending.
     */
    function transferOwnership(address to) external;

    /**
     * @notice Allows an ownership transfer to be completed by the recipient.
     */
    function acceptOwnership() external;

    /**
     * @notice Propose a new Chainlink aggregator for a given base and quote asset.
     * @param base Base asset address.
     * @param quote Quote asset address.
     * @param aggregator Chainlink aggregator address.
     */
    function proposeFeed(address base, address quote, address aggregator) external;

    /**
     * @notice Confirm a new Chainlink aggregator for a given base and quote asset.
     * @param base Base asset address.
     * @param quote Quote asset address.
     * @param aggregator Chainlink aggregator address.
     */
    function confirmFeed(address base, address quote, address aggregator) external;

}
