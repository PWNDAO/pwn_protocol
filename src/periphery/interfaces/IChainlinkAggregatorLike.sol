// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


/**
 * @title IChainlinkAggregatorLike
 * @notice Chainlink Aggregator Interface.
 */
interface IChainlinkAggregatorLike {

    /**
     * @notice Get the number of decimals for the aggregator answers.
     * @return Number of decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get the description of the aggregator.
     * @return Description of the aggregator.
     */
    function description() external view returns (string memory);

    /**
     * @notice Get the latest round data for the aggregator.
     * @return roundId The round ID from the aggregator for which the data was retrieved combined with a phase to ensure that round IDs get larger as time moves forward.
     * @return answer The answer for the latest round.
     * @return startedAt The timestamp when the round was started. (Only some AggregatorV3Interface implementations return meaningful values).
     * @return updatedAt The timestamp when the round last was updated (i.e. answer was last computed).
     * @return answeredInRound The round ID of the round in which the answer was computed. (Only some AggregatorV3Interface implementations return meaningful values).
     */
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

}
