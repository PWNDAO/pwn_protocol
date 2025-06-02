// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { IChainlinkAggregatorLike } from "pwn/periphery/interfaces/IChainlinkAggregatorLike.sol";
import { IChainlinkFeedRegistryLike } from "pwn/periphery/interfaces/IChainlinkFeedRegistryLike.sol";
import { safeFetchDecimals } from "pwn/periphery/utils/safeFetchDecimals.sol";


library Chainlink {
    using Math for uint256;

    /** @notice Maximum Chainlink feed price age.*/
    uint256 public constant MAX_CHAINLINK_FEED_PRICE_AGE = 1 days;
    /** @notice Grace period time for L2 Sequencer uptime feed.*/
    uint256 public constant L2_GRACE_PERIOD = 10 minutes;
    /** @notice Chainlink address of ETH asset.*/
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /** @notice Throw when Chainlink feed returns negative price.*/
    error ChainlinkFeedReturnedNegativePrice(address feed, int256 price, uint256 updatedAt);
    /** @notice Throw when Chainlink feed price is too old.*/
    error ChainlinkFeedPriceTooOld(address feed, uint256 updatedAt);
    /** @notice Throw when feed invert array is not exactly one item longer than intermediary feed array.*/
    error ChainlinkInvalidInputLenghts();
    /** @notice Throw when L2 Sequencer uptime feed returns that the sequencer is down.*/
    error L2SequencerDown();
    /** @notice Throw when L2 Sequencer uptime feed grace period is not over.*/
    error GracePeriodNotOver(uint256 timeSinceUp, uint256 gracePeriod);
    /** @notice Thrown when intermediary denominations are out of bounds.*/
    error IntermediaryDenominationsOutOfBounds(uint256 current, uint256 limit);


    struct Config {
        IChainlinkAggregatorLike l2SequencerUptimeFeed;
        IChainlinkFeedRegistryLike feedRegistry;
        uint256 maxIntermediaryDenominations;
        address weth;
    }

    /**
     * @notice Converts the amount with the old denomination to the new denomination.
     * @param amount The amount to convert.
     * @param oldDenomination The address of the old denomination.
     * @param newDenomination The address of the new denomination.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the quote asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param config The Chainlink configuration.
     * @return The amount in the new denomination.
     */
    function convertDenomination(
        Config memory config,
        uint256 amount,
        address oldDenomination,
        address newDenomination,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) internal view returns (uint256) {
        // check L2 sequencer uptime if necessary
        checkSequencerUptime(config.l2SequencerUptimeFeed);

        // don't allow more than max intermediary denominations
        if (feedIntermediaryDenominations.length > config.maxIntermediaryDenominations) {
            revert IntermediaryDenominationsOutOfBounds({
                current: feedIntermediaryDenominations.length,
                limit: config.maxIntermediaryDenominations
            });
        }

        // calculate price of base asset with quote asset as denomination
        // Note: use ETH price feed for WETH asset due to absence of WETH price feed
        (uint256 price, uint8 priceDecimals) = calculatePrice({
            feedRegistry: config.feedRegistry,
            baseAsset: oldDenomination == config.weth ? Chainlink.ETH : oldDenomination,
            quoteAsset: newDenomination == config.weth ? Chainlink.ETH : newDenomination,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        });

        // fetch denomination decimals
        uint256 oldDenominationDecimals = safeFetchDecimals(oldDenomination);
        uint256 newDenominationDecimals = safeFetchDecimals(newDenomination);
        uint256 maxDecimals = Math.max(oldDenominationDecimals, newDenominationDecimals);

        // calculate amount in new denomination
        uint256 amount_ = amount; // yes, I know, it's just to avoid stack too deep error
        return (amount_ * 10 ** (maxDecimals - oldDenominationDecimals))
            .mulDiv(price, 10 ** priceDecimals)
            / 10 ** (maxDecimals - newDenominationDecimals);
    }

    /**
     * @notice Checks the uptime status of the L2 sequencer.
     * @dev This function reverts if the sequencer is down or if the grace period is not over.
     * @param l2SequencerUptimeFeed The Chainlink feed that provides the sequencer uptime status.
     */
    function checkSequencerUptime(IChainlinkAggregatorLike l2SequencerUptimeFeed) internal view {
        if (address(l2SequencerUptimeFeed) != address(0)) {
            (, int256 answer, uint256 startedAt,,) = l2SequencerUptimeFeed.latestRoundData();
            if (answer == 1) {
                // sequencer is down
                revert L2SequencerDown();
            }

            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= L2_GRACE_PERIOD) {
                // grace period is not over
                revert GracePeriodNotOver({ timeSinceUp: timeSinceUp, gracePeriod: L2_GRACE_PERIOD });
            }
        }
    }

    /**
     * @notice Fetches the prices of the base asset with quote asset as denomination.
     * @dev `feedInvertFlags` array must be exactly one item longer than `feedIntermediaryDenominations`.
     * @param feedRegistry The Chainlink feed registry contract that provides the price feeds.
     * @param baseAsset The address of the base asset.
     * @param quoteAsset The address of the quote asset.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the quote asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @return The price of the base asset denominated in quote asset.
     * @return The price decimals.
     */
    function calculatePrice(
        IChainlinkFeedRegistryLike feedRegistry,
        address baseAsset,
        address quoteAsset,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) internal view returns (uint256, uint8) {
        if (feedInvertFlags.length != feedIntermediaryDenominations.length + 1) {
            revert ChainlinkInvalidInputLenghts();
        }

        // initial state
        uint256 price = 1;
        uint8 priceDecimals = 0;

        // iterate until quote asset is the denominator
        for (uint256 i; i < feedInvertFlags.length; ++i) {
            (price, priceDecimals) = convertPriceDenomination({
                feedRegistry: feedRegistry,
                currentPrice: price,
                currentDecimals: priceDecimals,
                currentDenomination: i == 0 ? baseAsset : feedIntermediaryDenominations[i - 1],
                nextDenomination: i == feedIntermediaryDenominations.length ? quoteAsset : feedIntermediaryDenominations[i],
                nextInvert: feedInvertFlags[i]
            });
        }

        return (price, priceDecimals);
    }

    /**
     * @notice Convert price denomination.
     * @param feedRegistry The Chainlink feed registry contract that provides the price feeds.
     * @param currentPrice Price of an asset denominated in `currentDenomination`.
     * @param currentDecimals Decimals of the current price.
     * @param currentDenomination Address of the current denomination.
     * @param nextDenomination Address of the denomination to convert the current price to.
     * @param nextInvert Flag, if intermediary price feed exists only with inverted base and quote assets.
     * @return nextPrice Price of an asset denomination in `nextDenomination`.
     * @return nextDecimals Decimals of the next price.
     */
    function convertPriceDenomination(
        IChainlinkFeedRegistryLike feedRegistry,
        uint256 currentPrice,
        uint8 currentDecimals,
        address currentDenomination,
        address nextDenomination,
        bool nextInvert
    ) internal view returns (uint256 nextPrice, uint8 nextDecimals) {
        // fetch convert price
        (uint256 intermediaryPrice, uint8 intermediaryDecimals) = fetchPrice({
            feedRegistry: feedRegistry,
            asset: nextInvert ? nextDenomination : currentDenomination,
            denomination: nextInvert ? currentDenomination : nextDenomination
        });

        // sync decimals
        (currentPrice, intermediaryPrice, nextDecimals)
            = syncDecimalsUp(currentPrice, currentDecimals, intermediaryPrice, intermediaryDecimals);

        // compute price with new denomination
        if (nextInvert) {
            nextPrice = Math.mulDiv(currentPrice, 10 ** nextDecimals, intermediaryPrice);
        } else {
            nextPrice = Math.mulDiv(currentPrice, intermediaryPrice, 10 ** nextDecimals);
        }

        return (nextPrice, nextDecimals);
    }

    /**
     * @notice Fetch price from Chainlink feed.
     * @param feedRegistry The Chainlink feed registry contract that provides the price feeds.
     * @param asset Address of an asset.
     * @param denomination Address of a denomination asset.
     * @return price Price of an asset.
     * @return decimals Decimals of a price.
     */
    function fetchPrice(IChainlinkFeedRegistryLike feedRegistry, address asset, address denomination)
        internal
        view
        returns (uint256, uint8)
    {
        IChainlinkAggregatorLike feed = feedRegistry.getFeed(asset, denomination);

        // Note: registry reverts with "Feed not found" for no registered feed

        (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        if (price < 0) {
            revert ChainlinkFeedReturnedNegativePrice({ feed: address(feed), price: price, updatedAt: updatedAt });
        }
        if (block.timestamp - updatedAt > MAX_CHAINLINK_FEED_PRICE_AGE) {
            revert ChainlinkFeedPriceTooOld({ feed: address(feed), updatedAt: updatedAt });
        }

        return (uint256(price), feed.decimals());
    }

    /**
     * @notice Sync price decimals to the higher one.
     * @param price1 Price one to be scaled.
     * @param decimals1 Decimals of the price one.
     * @param price2 Price two to be scaled.
     * @param decimals2 Decimals of the price two.
     * @return Synced price one.
     * @return Synced price two.
     * @return Synced price decimals.
     */
    function syncDecimalsUp(uint256 price1, uint8 decimals1, uint256 price2, uint8 decimals2)
        internal
        pure
        returns (uint256, uint256, uint8)
    {
        uint8 syncedDecimals = uint8(Math.max(decimals1, decimals2));
        return (
            price1 * 10 ** (syncedDecimals - decimals1),
            price2 * 10 ** (syncedDecimals - decimals2),
            syncedDecimals
        );
    }

}
