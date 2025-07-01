// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNInterestModule } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNChainlinkValueDefaultModule,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE,
    Chainlink,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike
} from "pwn/periphery/loan/module/default/PWNChainlinkValueDefaultModule.sol";

import { PWNChainlinkValueDefaultModuleHarness } from "test/harness/PWNChainlinkValueDefaultModuleHarness.sol";

using MultiToken for address;

abstract contract PWNChainlinkValueDefaultModuleTest is Test {

    PWNChainlinkValueDefaultModuleHarness defaultModule;
    address hub = makeAddr("hub");
    address chainlinkFeedRegistry = makeAddr("chainlinkFeedRegistry");
    address weth = makeAddr("weth");
    address priceFeed = makeAddr("priceFeed");
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;
    PWNLoan.LOAN loan;
    bytes encodedProposerData;


    function setUp() public virtual {
        defaultModule = new PWNChainlinkValueDefaultModuleHarness(
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

        encodedProposerData = _encodeProposerData(0.7e4, new address[](0), new bool[](1));

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

    function _mockPrice(uint256 price) internal {
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
        bool[] memory feedInvertFlags
    ) internal pure returns (bytes memory) {
        return abi.encode(
            PWNChainlinkValueDefaultModule.ProposerData(
                lltv, feedIntermediaryDenominations, feedInvertFlags
            )
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNChainlinkValueDefaultModule_OnLoanCreated_Test is PWNChainlinkValueDefaultModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNChainlinkValueDefaultModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);

        vm.expectRevert(PWNChainlinkValueDefaultModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function test_shouldFail_whenCollateralNotERC20() external {
        loan.collateral = makeAddr("coll").ERC721(100);
        _mockGetLOAN(loanId, loan);

        vm.expectRevert(PWNChainlinkValueDefaultModule.UnsupportedCollateral.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function testFuzz_shouldFail_whenInvalidLLTV() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNChainlinkValueDefaultModule.InvalidLLTV.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0, new address[](0), new bool[](1)));

        vm.prank(loanContract);
        vm.expectRevert(PWNChainlinkValueDefaultModule.InvalidLLTV.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(1e4 + 1, new address[](0), new bool[](1)));
    }

    function test_shouldStoreDefaultDate() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, new address[](0), new bool[](1)));

        (
            uint256 lltv,
            address[] memory feedIntermediaryDenominations,
            bool[] memory feedInvertFlags
        ) = defaultModule.defaultData(loanContract, loanId);

        assertEq(lltv, 0.5e4);
        assertEq(feedIntermediaryDenominations.length, 0);
        assertEq(feedInvertFlags.length, 1);
        assertFalse(feedInvertFlags[0]);
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

contract PWNChainlinkValueDefaultModule_IsDefaulted_Test is PWNChainlinkValueDefaultModuleTest {

    function setUp() public override {
        super.setUp();

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.8e4, new address[](0), new bool[](1)));
        _mockLOANDebt(loanId, 100 ether);

        // 80% LLTV: collateral price = 1.25
    }


    function test_shouldFetchLoanData() external {
        _mockPrice(2 ether);

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, loanId));

        defaultModule.isDefaulted(loanContract, loanId);
    }

    function testFuzz_shouldReturnFalse_whenCreditValueBelowLLTV(uint256 price) external {
        _mockPrice(bound(price, 0.1 ether, 0.8 ether - 1));
        assertFalse(defaultModule.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnTrue_whenCreditValueAboveLLTV(uint256 price) external {
        _mockPrice(bound(price, 0.8 ether, 10 ether));
        assertTrue(defaultModule.isDefaulted(loanContract, loanId));
    }

}


/*----------------------------------------------------------*|
|*  # DEFAULT DATA                                          *|
|*----------------------------------------------------------*/

contract PWNChainlinkValueDefaultModule_DefaultData_Test is PWNChainlinkValueDefaultModuleTest {

    function testFuzz_shouldReturnDefaultData(uint256 lltv) external {
        lltv = bound(lltv, 1, 10 ** defaultModule.LLTV_DECIMALS());

        bool[] memory feedInvertFlags = new bool[](2);
        feedInvertFlags[0] = true;
        feedInvertFlags[1] = false;
        address[] memory feedIntermediaryDenominations = new address[](1);
        feedIntermediaryDenominations[0] = makeAddr("intermediary");

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(PWNChainlinkValueDefaultModule.ProposerData(
            lltv,
            feedIntermediaryDenominations,
            feedInvertFlags
        )));

        (
            uint256 _lltv,
            address[] memory _feedIntermediaryDenominations,
            bool[] memory _feedInvertFlags
        ) = defaultModule.defaultData(loanContract, loanId);

        assertEq(_lltv, lltv);
        assertEq(_feedInvertFlags.length, 2);
        assertEq(_feedIntermediaryDenominations.length, 1);
        for (uint256 i; i < 2; ++i) assertEq(_feedInvertFlags[i], feedInvertFlags[i]);
        assertEq(_feedIntermediaryDenominations[0], feedIntermediaryDenominations[0]);
    }

}


/*----------------------------------------------------------*|
|*  # ENCODE/DECODE PRICE FEED DATA                         *|
|*----------------------------------------------------------*/

contract PWNChainlinkValueDefaultModule_EncodeDecodePriceFeedData_Test is PWNChainlinkValueDefaultModuleTest {

    function testFuzz_shouldFail_whenFeedInvertFlagsAndFeedIntermediaryDenominationsLengthMismatch(
        uint256 invertFlagsLength,
        uint256 intermediaryDenominationsLength
    ) external {
        invertFlagsLength = bound(invertFlagsLength, 0, 5);
        intermediaryDenominationsLength = bound(intermediaryDenominationsLength, 0, 4);
        vm.assume(invertFlagsLength != intermediaryDenominationsLength + 1);

        bool[] memory feedInvertFlags = new bool[](invertFlagsLength);
        address[] memory feedIntermediaryDenominations = new address[](intermediaryDenominationsLength);

        vm.expectRevert(Chainlink.ChainlinkInvalidInputLenghts.selector);
        defaultModule.exposed_encodePriceFeedData(feedInvertFlags, feedIntermediaryDenominations);
    }

    function test_shouldFail_whenFeedItermediaryDenominationsOverMax() external {
        bool[] memory feedInvertFlags = new bool[](6);
        address[] memory feedIntermediaryDenominations = new address[](5);

        vm.expectRevert(abi.encodeWithSelector(Chainlink.IntermediaryDenominationsOutOfBounds.selector, 5, 4));
        defaultModule.exposed_encodePriceFeedData(feedInvertFlags, feedIntermediaryDenominations);
    }

    function test_shouldEncodePriceFeedData() external {
        bool[] memory feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = true;
        feedInvertFlags[1] = false;
        feedInvertFlags[2] = true;

        address[] memory feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = makeAddr("intermediary1");
        feedIntermediaryDenominations[1] = makeAddr("intermediary2");

        bytes memory encodedData = defaultModule.exposed_encodePriceFeedData(
            feedInvertFlags,
            feedIntermediaryDenominations
        );

        assertEq(
            keccak256(encodedData),
            keccak256(abi.encodePacked(feedInvertFlags[0], feedIntermediaryDenominations[0], feedInvertFlags[1], feedIntermediaryDenominations[1], feedInvertFlags[2]))
        );

        (bool[] memory decodedFeedInvertFlags, address[] memory decodedFeedIntermediaryDenominations) =
            defaultModule.exposed_decodePriceFeedData(encodedData);

        assertEq(decodedFeedInvertFlags.length, 3);
        assertEq(decodedFeedIntermediaryDenominations.length, 2);
        for (uint256 i; i < 3; ++i) assertEq(decodedFeedInvertFlags[i], feedInvertFlags[i]);
        for (uint256 i; i < 2; ++i) assertEq(decodedFeedIntermediaryDenominations[i], feedIntermediaryDenominations[i]);
    }

}
