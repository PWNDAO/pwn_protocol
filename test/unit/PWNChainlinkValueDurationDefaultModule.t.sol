// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNInterestModule } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNChainlinkValueDurationDefaultModule,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE,
    Chainlink,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike
} from "pwn/periphery/loan/module/default/PWNChainlinkValueDurationDefaultModule.sol";

using MultiToken for address;

abstract contract PWNChainlinkValueDurationDefaultModuleTest is Test {

    PWNChainlinkValueDurationDefaultModule defaultModule;
    address hub = makeAddr("hub");
    address chainlinkFeedRegistry = makeAddr("chainlinkFeedRegistry");
    address weth = makeAddr("weth");
    address priceFeed = makeAddr("priceFeed");
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;
    PWNLoan.LOAN loan;
    bytes encodedProposerData;


    function setUp() public virtual {
        defaultModule = new PWNChainlinkValueDurationDefaultModule(
            PWNHub(hub),
            IChainlinkAggregatorLike(address(0)),
            IChainlinkFeedRegistryLike(chainlinkFeedRegistry),
            weth
        );

        loan = PWNLoan.LOAN({
            borrower: makeAddr("borrower"),
            lastUpdateTimestamp: uint40(0),
            collateral: makeAddr("collateral").ERC20(100 ether),
            creditAddress: makeAddr("creditAddress"),
            principal: 100 ether,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            interestModule: IPWNInterestModule(makeAddr("interestModule")),
            defaultModule: IPWNDefaultModule(address(defaultModule)),
            liquidationModule: IPWNLiquidationModule(makeAddr("liquidationModule"))
        });

        encodedProposerData = _encodeProposerData(0.7e4, new address[](0), new bool[](1), 30 days);

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
        _mockGetLOAN(loanId, loan);
        _mockLOANDebt(loanId, 100 ether);
        _mockAssetDecimals(loan.collateral.assetAddress, 18);
        _mockAssetDecimals(loan.creditAddress, 18);
    }


    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

    function _mockGetLOAN(uint256 _loanId, PWNLoan.LOAN memory _loan) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, _loanId), abi.encode(_loan));
    }

    function _mockLOANDebt(uint256 _loanId, uint256 _debt) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, _loanId), abi.encode(_debt));
    }

    function _mockAssetDecimals(address _asset, uint8 _decimals) internal {
        vm.mockCall(_asset, abi.encodeWithSignature("decimals()"), abi.encode(_decimals));
    }

    function _mockCollateralPrice(uint256 price) internal {
        vm.mockCall(
            chainlinkFeedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector),
            abi.encode(priceFeed)
        );
        vm.mockCall(
            priceFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, int256(price), 0, block.timestamp, 0)
        );
        vm.mockCall(priceFeed, abi.encodeWithSelector(IChainlinkAggregatorLike.decimals.selector), abi.encode(18));
    }


    function _encodeProposerData(
        uint256 lltv,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags,
        uint256 duration
    ) internal pure returns (bytes memory) {
        return abi.encode(
            PWNChainlinkValueDurationDefaultModule.ProposerData(
                lltv, feedIntermediaryDenominations, feedInvertFlags, duration
            )
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNChainlinkValueDurationDefaultModule_OnLoanCreated_Test is PWNChainlinkValueDurationDefaultModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNChainlinkValueDurationDefaultModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);

        vm.expectRevert(PWNChainlinkValueDurationDefaultModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function test_shouldFail_whenCollateralNotERC20() external {
        loan.collateral = makeAddr("coll").ERC721(100);
        _mockGetLOAN(loanId, loan);

        vm.expectRevert(PWNChainlinkValueDurationDefaultModule.UnsupportedCollateral.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function testFuzz_shouldFail_whenInvalidLLTV() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNChainlinkValueDurationDefaultModule.InvalidLLTV.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0, new address[](0), new bool[](1), 1 days));

        vm.prank(loanContract);
        vm.expectRevert(PWNChainlinkValueDurationDefaultModule.InvalidLLTV.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(1e4 + 1, new address[](0), new bool[](1), 1 days));
    }

    function testFuzz_shouldFail_whenDurationTooShort(uint256 duration) external {
        duration = bound(duration, 0, defaultModule.MIN_DURATION() - 1);

        vm.prank(loanContract);
        vm.expectRevert(PWNChainlinkValueDurationDefaultModule.DurationTooShort.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, new address[](0), new bool[](1), duration));
    }

    function test_shouldStoreDefaultDate() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, new address[](0), new bool[](1), 1 days));

        (
            uint256 lltv,
            address[] memory feedIntermediaryDenominations,
            bool[] memory feedInvertFlags,
            uint256 defaultTimestamp
        ) = defaultModule.defaultData(loanContract, loanId);

        assertEq(lltv, 0.5e4);
        assertEq(feedIntermediaryDenominations.length, 0);
        assertEq(feedInvertFlags.length, 1);
        assertFalse(feedInvertFlags[0]);
        assertEq(defaultTimestamp, block.timestamp + 1 days);
    }

    function test_shouldReturnInitHookValue() external {
        vm.prank(loanContract);
        bytes32 result = defaultModule.onLoanCreated(loanId, encodedProposerData);

        assertEq(result, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE);
    }

}


/*----------------------------------------------------------*|
|*  # IS DEFAULTED                                          *|
|*----------------------------------------------------------*/

contract PWNChainlinkValueDurationDefaultModule_IsDefaulted_Test is PWNChainlinkValueDurationDefaultModuleTest {

    function setUp() public override {
        super.setUp();

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.8e4, new address[](0), new bool[](1), 1 days));
        _mockLOANDebt(loanId, 100 ether);

        // 80% LLTV: collateral price = 1.25
    }


    function testFuzz_shouldFail_whenAfterDefaultTimestamp(uint256 timestamp) external {
        vm.warp(bound(timestamp, block.timestamp + 1 days, type(uint256).max));

        assertTrue(defaultModule.isDefaulted(loanContract, loanId));
    }

    function test_shouldFetchLoanData() external {
        _mockCollateralPrice(2 ether);

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, loanId));

        defaultModule.isDefaulted(loanContract, loanId);
    }

    function testFuzz_shouldReturnFalse_whenCollateralValueAboveLLTV(uint256 price) external {
        _mockCollateralPrice(bound(price, 1.25 ether + 1, 10 ether));
        assertFalse(defaultModule.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnTrue_whenCollateralValueBelowLLTV(uint256 price) external {
        _mockCollateralPrice(bound(price, 0.1 ether, 1.25 ether));
        assertTrue(defaultModule.isDefaulted(loanContract, loanId));
    }

}


/*----------------------------------------------------------*|
|*  # DEFAULT DATA                                          *|
|*----------------------------------------------------------*/

contract PWNChainlinkValueDurationDefaultModule_DefaultData_Test is PWNChainlinkValueDurationDefaultModuleTest {

    function testFuzz_shouldReturnDefaultData(uint256 lltv, uint256 duration) external {
        lltv = bound(lltv, 1, 10 ** defaultModule.LLTV_DECIMALS());
        duration = bound(duration, defaultModule.MIN_DURATION(), type(uint256).max - 100 days);

        bool[] memory feedInvertFlags = new bool[](2);
        feedInvertFlags[0] = true;
        feedInvertFlags[1] = false;
        address[] memory feedIntermediaryDenominations = new address[](1);
        feedIntermediaryDenominations[0] = makeAddr("intermediary");

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(PWNChainlinkValueDurationDefaultModule.ProposerData(
            lltv,
            feedIntermediaryDenominations,
            feedInvertFlags,
            duration
        )));

        (
            uint256 _lltv,
            address[] memory _feedIntermediaryDenominations,
            bool[] memory _feedInvertFlags,
            uint256 _defaultTimestamp
        ) = defaultModule.defaultData(loanContract, loanId);

        assertEq(_lltv, lltv);
        assertEq(_feedInvertFlags.length, 2);
        assertEq(_feedIntermediaryDenominations.length, 1);
        for (uint256 i; i < 2; ++i) assertEq(_feedInvertFlags[i], feedInvertFlags[i]);
        assertEq(_feedIntermediaryDenominations[0], feedIntermediaryDenominations[0]);
        assertEq(_defaultTimestamp, block.timestamp + duration);
    }

}
