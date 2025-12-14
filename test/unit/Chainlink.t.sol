// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike,
    Math
} from "pwn/periphery/lib/Chainlink.sol";

import { ChainlinkHarness } from "test/harness/ChainlinkHarness.sol";
import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";


abstract contract ChainlinkTest is Test {

    ChainlinkHarness chainlink;

    IChainlinkFeedRegistryLike feedRegistry = IChainlinkFeedRegistryLike(makeAddr("feedRegistry"));
    address aggregator = makeAddr("aggregator");
    IChainlinkAggregatorLike l2SequencerUptimeFeed = IChainlinkAggregatorLike(makeAddr("l2SequencerUptimeFeed"));
    address asset = makeAddr("asset");

    function setUp() public virtual {
        chainlink = new ChainlinkHarness();

        _mockFeed(aggregator);
        _mockLastRoundData(aggregator, 1e18, 1);
        _mockFeedDecimals(aggregator, 18);
        _mockSequencerUptimeFeed(true, block.timestamp - 1);
    }


    function _mockFeed(address _aggregator) internal {
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector),
            abi.encode(_aggregator)
        );
    }

    function _mockFeed(address _aggregator, address base, address quote) internal {
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, base, quote),
            abi.encode(_aggregator)
        );
    }

    function _mockLastRoundData(address _aggregator, int256 answer, uint256 updatedAt) internal {
        vm.mockCall(
            _aggregator,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, answer, 0, updatedAt, 0)
        );
    }

    function _mockFeedDecimals(address _aggregator, uint8 decimals) internal {
        vm.mockCall(
            _aggregator,
            abi.encodeWithSelector(IChainlinkAggregatorLike.decimals.selector),
            abi.encode(decimals)
        );
    }

    function _mockSequencerUptimeFeed(bool isUp, uint256 startedAt) internal {
        vm.mockCall(
            address(l2SequencerUptimeFeed),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, isUp ? 0 : 1, startedAt, 0, 0)
        );
    }

    function _mockAssetDecimals(address _asset, uint8 _decimals) internal {
        vm.mockCall(_asset, abi.encodeWithSignature("decimals()"), abi.encode(_decimals));
    }

}


/*----------------------------------------------------------*|
|*  # CONVERT DENOMINATION                                  *|
|*----------------------------------------------------------*/

contract Chainlink_ConvertDenomination_Test is ChainlinkTest {

    Chainlink.Config config;
    address[] feedIntermediaryDenominations;
    bool[] feedInvertFlags;
    uint256 baseAmount = 1e18;
    address baseAddr = makeAddr("baseAddr");
    address quoteAddr = makeAddr("quoteAddr");

    function setUp() public override virtual {
        super.setUp();

        config = Chainlink.Config({
            l2SequencerUptimeFeed: l2SequencerUptimeFeed,
            feedRegistry: feedRegistry,
            maxIntermediaryDenominations: 2,
            weth: makeAddr("weth")
        });

        feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = makeAddr("inter1");
        feedIntermediaryDenominations[1] = makeAddr("inter2");

        feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = false;
        feedInvertFlags[1] = false;
        feedInvertFlags[2] = false;

        vm.warp(block.timestamp + Chainlink.L2_GRACE_PERIOD + 1);
    }


    function test_shouldFetchSequencerUptimeFeed_whenFeedSet() external {
        vm.expectCall(
            address(l2SequencerUptimeFeed),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector)
        );

        chainlink.convertDenomination(config, baseAmount, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFail_whenL2SequencerDown_whenFeedSet() external {
        _mockSequencerUptimeFeed(false, block.timestamp - Chainlink.L2_GRACE_PERIOD - 1);

        vm.expectRevert(abi.encodeWithSelector(Chainlink.L2SequencerDown.selector));
        chainlink.convertDenomination(config, baseAmount, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

    function testFuzz_shouldFail_whenL2SequencerUp_whenInGracePeriod_whenFeedSet(uint256 startedAt) external {
        startedAt = bound(startedAt, block.timestamp - Chainlink.L2_GRACE_PERIOD, block.timestamp);

        _mockSequencerUptimeFeed(true, startedAt);

        vm.expectRevert(
            abi.encodeWithSelector(Chainlink.GracePeriodNotOver.selector, block.timestamp - startedAt, Chainlink.L2_GRACE_PERIOD)
        );
        chainlink.convertDenomination(config, baseAmount, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldNotFetchSequencerUptimeFeed_whenFeedNotSet() external {
        config.l2SequencerUptimeFeed = IChainlinkAggregatorLike(address(0));

        vm.expectCall(
            address(l2SequencerUptimeFeed),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            0
        );

        chainlink.convertDenomination(config, baseAmount, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFail_whenIntermediaryDenominationsOutOfBounds() external {
        feedIntermediaryDenominations = new address[](3);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.IntermediaryDenominationsOutOfBounds.selector,
                3, config.maxIntermediaryDenominations
            )
        );
        chainlink.convertDenomination(config, baseAmount, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFetchPrices() external {
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, baseAddr, feedIntermediaryDenominations[0])
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[0], feedIntermediaryDenominations[1])
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[1], quoteAddr)
        );

        chainlink.convertDenomination(config, baseAmount, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFetchETHPrice_whenWETH() external {
        _mockAssetDecimals(config.weth, 18);
        feedIntermediaryDenominations = new address[](0);
        feedInvertFlags = new bool[](1);
        feedInvertFlags[0] = false;

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, quoteAddr)
        );
        chainlink.convertDenomination(config, baseAmount, config.weth, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, baseAddr, ChainlinkDenominations.ETH)
        );
        chainlink.convertDenomination(config, baseAmount, baseAddr, config.weth, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldReturnCorrectDecimals() external {
        _mockAssetDecimals(quoteAddr, 18);
        _mockAssetDecimals(baseAddr, 6);
        assertEq(
            chainlink.convertDenomination(config, 8e6, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags),
            8e18
        );

        _mockAssetDecimals(quoteAddr, 6);
        _mockAssetDecimals(baseAddr, 18);
        assertEq(
            chainlink.convertDenomination(config, 8e18, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags),
            8e6
        );

        _mockAssetDecimals(config.weth, 0);
        _mockAssetDecimals(baseAddr, 18);
        assertEq(
            chainlink.convertDenomination(config, 8e18, baseAddr, config.weth, feedIntermediaryDenominations, feedInvertFlags),
            8
        );
    }

    function test_shouldReturnNewAmount() external {
        _mockFeedDecimals(aggregator, 8);
        feedIntermediaryDenominations = new address[](0);
        feedInvertFlags = new bool[](1);
        feedInvertFlags[0] = false;

        _mockLastRoundData(aggregator, 300e8, 1);
        assertEq(
            chainlink.convertDenomination(config, 8e18, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags),
            2400e18
        );

        _mockLastRoundData(aggregator, 1e8, 1);
        assertEq(
            chainlink.convertDenomination(config, 0, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags),
            0
        );

        _mockLastRoundData(aggregator, 0.5e8, 1);
        assertEq(
            chainlink.convertDenomination(config, 20e18, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags),
            10e18
        );

        _mockLastRoundData(aggregator, 4e8, 1);
        assertEq(
            chainlink.convertDenomination(config, 20e18, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags),
            80e18
        );
    }

}


/*----------------------------------------------------------*|
|*  # CHECK SEQUENCER UPTIME                                *|
|*----------------------------------------------------------*/

contract Chainlink_CheckSequencerUptime_Test is ChainlinkTest {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(Chainlink.L2_GRACE_PERIOD + 100);
    }


    function test_shouldSkip_whenFeedIsZero() external {
        vm.expectCall(
            address(0),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            0
        );

        chainlink.checkSequencerUptime(IChainlinkAggregatorLike(address(0)));
    }

    function test_shouldFetchLatestRoundData() external {
        _mockSequencerUptimeFeed(true, 0);

        vm.expectCall(
            address(l2SequencerUptimeFeed),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector)
        );

        chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

    function test_shouldFail_whenSequencerDown() external {
        _mockSequencerUptimeFeed(false, 0);

        vm.expectRevert(abi.encodeWithSelector(Chainlink.L2SequencerDown.selector));
        chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

    function testFuzz_shouldFail_whenSequencerInGracePeriod(uint256 gracePeriod) external {
        gracePeriod = bound(gracePeriod, 0, Chainlink.L2_GRACE_PERIOD);
        _mockSequencerUptimeFeed(true, block.timestamp - gracePeriod);

        vm.expectRevert(
            abi.encodeWithSelector(Chainlink.GracePeriodNotOver.selector, gracePeriod, Chainlink.L2_GRACE_PERIOD)
        );
        chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

}


/*----------------------------------------------------------*|
|*  # CALCULATE PRICE                                       *|
|*----------------------------------------------------------*/

contract Chainlink_CalculatePrice_Test is ChainlinkTest {

    address baseAddr = makeAddr("baseAddr");
    address quoteAddr = makeAddr("quoteAddr");


    function test_shouldFail_whenInvalidInputLength() external {
        address[] memory feedIntermediaryDenominations;
        bool[] memory feedInvertFlags;

        feedIntermediaryDenominations = new address[](0);
        feedInvertFlags = new bool[](0);
        vm.expectRevert(abi.encodeWithSelector(Chainlink.ChainlinkInvalidInputLenghts.selector));
        chainlink.calculatePrice(feedRegistry, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);

        feedIntermediaryDenominations = new address[](5);
        feedInvertFlags = new bool[](5);
        vm.expectRevert(abi.encodeWithSelector(Chainlink.ChainlinkInvalidInputLenghts.selector));
        chainlink.calculatePrice(feedRegistry, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);

        feedIntermediaryDenominations = new address[](4);
        feedInvertFlags = new bool[](6);
        vm.expectRevert(abi.encodeWithSelector(Chainlink.ChainlinkInvalidInputLenghts.selector));
        chainlink.calculatePrice(feedRegistry, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);

        feedIntermediaryDenominations = new address[](10);
        feedInvertFlags = new bool[](6);
        vm.expectRevert(abi.encodeWithSelector(Chainlink.ChainlinkInvalidInputLenghts.selector));
        chainlink.calculatePrice(feedRegistry, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFetchIntermediaryPrices() external {
        address[] memory feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = makeAddr("denom1");
        feedIntermediaryDenominations[1] = makeAddr("denom2");

        bool[] memory feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = true;
        feedInvertFlags[1] = false;
        feedInvertFlags[2] = true;

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[0], baseAddr)
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[0], feedIntermediaryDenominations[1])
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, quoteAddr, feedIntermediaryDenominations[1])
        );

        chainlink.calculatePrice(feedRegistry, baseAddr, quoteAddr, feedIntermediaryDenominations, feedInvertFlags);
    }

}


/*----------------------------------------------------------*|
|*  # CONVERT PRICE DENOMINATION                            *|
|*----------------------------------------------------------*/

contract Chainlink_ConvertPriceDenomination_Test is ChainlinkTest {

    address oDenominator = makeAddr("originalDenomination");
    address nDenominator = makeAddr("newDenomination");


    function test_shouldFetchIntermediaryPriceFeed_whenNotInverted() external {
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(
                IChainlinkFeedRegistryLike.getFeed.selector, oDenominator, nDenominator
            )
        );

        chainlink.convertPriceDenomination(feedRegistry, 1e18, 18, oDenominator, nDenominator, false);
    }

    function test_shouldFetchIntermediaryPriceFeed_whenInverted() external {
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(
                IChainlinkFeedRegistryLike.getFeed.selector, nDenominator, oDenominator
            )
        );

        chainlink.convertPriceDenomination(feedRegistry, 1e18, 18, oDenominator, nDenominator, true);
    }

    function test_shouldScaleToBiggerDecimals() external {
        _mockFeedDecimals(aggregator, 10);
        (, uint8 decimals)
            = chainlink.convertPriceDenomination(feedRegistry, 1, 6, oDenominator, nDenominator, false);
        assertEq(decimals, 10);

        _mockFeedDecimals(aggregator, 6);
        (, decimals)
            = chainlink.convertPriceDenomination(feedRegistry, 1, 18, oDenominator, nDenominator, false);
        assertEq(decimals, 18);

        _mockFeedDecimals(aggregator, 8);
        (, decimals)
            = chainlink.convertPriceDenomination(feedRegistry, 1, 8, oDenominator, nDenominator, false);
        assertEq(decimals, 8);
    }

    function test_shouldConvertPrice_whenNotInverted() external {
        _mockFeedDecimals(aggregator, 8);

        _mockLastRoundData(aggregator, 3000e8, 1);
        (uint256 price,) = chainlink.convertPriceDenomination(feedRegistry, 6000e8, 8, oDenominator, nDenominator, false);
        assertEq(price, 18000000e8);

        _mockLastRoundData(aggregator, 500e8, 1);
        (price,) = chainlink.convertPriceDenomination(feedRegistry, 100e8, 8, oDenominator, nDenominator, false);
        assertEq(price, 50000e8);

        _mockLastRoundData(aggregator, 5000e8, 1);
        (price,) = chainlink.convertPriceDenomination(feedRegistry, 1e8, 8, oDenominator, nDenominator, false);
        assertEq(price, 5000e8);

        _mockLastRoundData(aggregator, 0.05e8, 1);
        (price,) = chainlink.convertPriceDenomination(feedRegistry, 10e8, 8, oDenominator, nDenominator, false);
        assertEq(price, 0.5e8);
    }

    function test_shouldConvertPrice_whenInverted() external {
        _mockFeedDecimals(aggregator, 8);

        _mockLastRoundData(aggregator, 3000e8, 1);
        (uint256 price,) = chainlink.convertPriceDenomination(feedRegistry, 6000e8, 8, oDenominator, nDenominator, true);
        assertEq(price, 2e8);

        _mockLastRoundData(aggregator, 500e8, 1);
        (price,) = chainlink.convertPriceDenomination(feedRegistry, 100e8, 8, oDenominator, nDenominator, true);
        assertEq(price, 0.2e8);

        _mockLastRoundData(aggregator, 5000e8, 1);
        (price,) = chainlink.convertPriceDenomination(feedRegistry, 1e8, 8, oDenominator, nDenominator, true);
        assertEq(price, 0.0002e8);
    }

}


/*----------------------------------------------------------*|
|*  # FETCH PRICE                                           *|
|*----------------------------------------------------------*/

// TODO should we add test that will check if we threw exception when price is 0?
contract Chainlink_FetchPrice_Test is ChainlinkTest {

    address denominator = makeAddr("denominator");


    function testFuzz_shouldGetFeedFromRegistry(address _asset, address _denominator) external {
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, _asset, _denominator)
        );

        chainlink.fetchPrice(feedRegistry, _asset, _denominator);
    }

    function test_shouldFail_whenAggregatorNotRegistered() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, denominator),
            "whatnot"
        );

        vm.expectRevert("whatnot");
        chainlink.fetchPrice(feedRegistry, asset, denominator);
    }

    function test_shouldFail_whenNegativePrice() external {
        _mockLastRoundData(aggregator, -1, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.ChainlinkFeedReturnedNegativePrice.selector, aggregator, -1, 1
            )
        );
        chainlink.fetchPrice(feedRegistry, asset, denominator);
    }

    function test_shouldFail_whenPriceTooOld() external {
        _mockLastRoundData(aggregator, 1, 1);

        vm.warp(Chainlink.MAX_CHAINLINK_FEED_PRICE_AGE + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.ChainlinkFeedPriceTooOld.selector, aggregator, 1
            )
        );
        chainlink.fetchPrice(feedRegistry, asset, denominator);
    }

    function testFuzz_shouldReturnPriceAndDecimals(uint256 _price, uint8 _decimals) external {
        // Price must be > 0 because fetchPrice reverts on price <= 0
        _price = bound(_price, 1, uint256(type(int256).max));

        _mockFeedDecimals(aggregator, _decimals);
        _mockLastRoundData(aggregator, int256(_price), 1);

        (uint256 price, uint8 decimals) = chainlink.fetchPrice(feedRegistry, asset, denominator);

        assertEq(price, _price);
        assertEq(decimals, _decimals);
    }

}


/*----------------------------------------------------------*|
|*  # SYNC DECIMALS UP                                      *|
|*----------------------------------------------------------*/

contract Chainlink_SyncDecimalsUp_Test is ChainlinkTest {

    function test_shouldUpdateDecimals() external {
        uint256 price1;
        uint256 price2;
        uint8 decimals;

        (price1, price2, decimals) = chainlink.syncDecimalsUp(1, 0, 100, 3);
        assertEq(price1, 1000);
        assertEq(price2, 100);
        assertEq(decimals, 3);

        (price1, price2, decimals) = chainlink.syncDecimalsUp(5e18, 18, 0, 21);
        assertEq(price1, 5e21);
        assertEq(price2, 0);
        assertEq(decimals, 21);

        (price1, price2, decimals) = chainlink.syncDecimalsUp(3319200, 3, 3, 1);
        assertEq(price1, 3319200);
        assertEq(price2, 300);
        assertEq(decimals, 3);

        (price1, price2, decimals) = chainlink.syncDecimalsUp(1e18, 18, 21e17, 18);
        assertEq(price1, 1e18);
        assertEq(price2, 21e17);
        assertEq(decimals, 18);
    }

}
