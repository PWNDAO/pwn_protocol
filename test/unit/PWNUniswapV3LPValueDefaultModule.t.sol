// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNInterestModule } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNUniswapV3LPValueDefaultModule,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE,
    UniswapV3,
    INonfungiblePositionManager,
    Chainlink,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike
} from "pwn/periphery/loan/module/default/PWNUniswapV3LPValueDefaultModule.sol";

using MultiToken for address;

abstract contract PWNUniswapV3LPValueDefaultModuleTest is Test {

    PWNUniswapV3LPValueDefaultModule defaultModule;
    address hub = makeAddr("hub");
    address uniswapV3PositionManager = makeAddr("uniswapV3PositionManager");
    address uniswapV3Factory = makeAddr("uniswapV3Factory");
    address chainlinkFeedRegistry = makeAddr("chainlinkFeedRegistry");
    address weth = makeAddr("weth");
    address priceFeed = makeAddr("priceFeed");
    address token0 = makeAddr("token0");
    address token1 = makeAddr("token1");
    uint24 fee = 3000;
    address pool = 0xb44E273AE4071AA4a0F2b05ee96f20BB6FfD568b;
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;
    PWNLoan.LOAN loan;
    bytes encodedProposerData;


    function setUp() public virtual {
        defaultModule = new PWNUniswapV3LPValueDefaultModule(
            PWNHub(hub),
            INonfungiblePositionManager(uniswapV3PositionManager),
            uniswapV3Factory,
            IChainlinkAggregatorLike(address(0)),
            IChainlinkFeedRegistryLike(chainlinkFeedRegistry),
            weth
        );

        loan = PWNLoan.LOAN({
            borrower: makeAddr("borrower"),
            lastUpdateTimestamp: uint40(0),
            collateral: uniswapV3PositionManager.ERC721(55),
            creditAddress: token0,
            principal: 100 ether,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            interestModule: IPWNInterestModule(makeAddr("interestModule")),
            defaultModule: IPWNDefaultModule(address(defaultModule)),
            liquidationModule: IPWNLiquidationModule(makeAddr("liquidationModule"))
        });

        encodedProposerData = _encodeProposerData(0.7e4, false, new address[](0), new bool[](0));

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
        _mockGetLOAN(loanId, loan);
        _mockLOANDebt(loanId, 100 ether);
        _mockAssetDecimals(loan.creditAddress, 18);

        vm.mockCall(uniswapV3PositionManager, abi.encodeWithSignature("factory()"), abi.encode(uniswapV3Factory));
        _mockPosition(loan.collateral.id, -1, 1, 100 ether, 0, 0);
        _mockPool(pool, 0);
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

    function _mockPosition(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 tokensOwed0,
        uint256 tokensOwed1
    ) internal {
        vm.mockCall(
            uniswapV3PositionManager,
            abi.encodeWithSelector(INonfungiblePositionManager.positions.selector, tokenId),
            abi.encode(0, 0, token0, token1, fee, tickLower, tickUpper, liquidity, 0, 0, tokensOwed0, tokensOwed1)
        );
    }

    function _mockPool(address _pool, int24 currentTick) internal {
        vm.mockCall(_pool, abi.encodeWithSignature("slot0()"), abi.encode(0, currentTick, 0, 2, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("observations(uint256)"), abi.encode(block.timestamp - 1, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("liquidity()"), abi.encode(0)); // need to not revert
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal0X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal1X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("ticks(int24)"), abi.encode(0, 0, 0, 0, 0, 0, 0, 0));
    }


    function _encodeProposerData(
        uint256 lltv,
        bool token0Denominator,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) internal pure returns (bytes memory) {
        return abi.encode(
            PWNUniswapV3LPValueDefaultModule.ProposerData(
                lltv, token0Denominator, feedIntermediaryDenominations, feedInvertFlags
            )
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNUniswapV3LPValueDefaultModule_OnLoanCreated_Test is PWNUniswapV3LPValueDefaultModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNUniswapV3LPValueDefaultModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);

        vm.expectRevert(PWNUniswapV3LPValueDefaultModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function test_shouldFail_whenCollateralNotERC721() external {
        loan.collateral = makeAddr("coll").ERC20(100);
        _mockGetLOAN(loanId, loan);

        vm.expectRevert(PWNUniswapV3LPValueDefaultModule.UnsupportedCollateral.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function test_shouldFail_whenCollateralNotUniswapV3LP() external {
        loan.collateral = makeAddr("coll").ERC721(55);
        _mockGetLOAN(loanId, loan);

        vm.expectRevert(PWNUniswapV3LPValueDefaultModule.UnsupportedCollateral.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, encodedProposerData);
    }

    function testFuzz_shouldFail_whenInvalidLLTV() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNUniswapV3LPValueDefaultModule.InvalidLLTV.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0, false, new address[](0), new bool[](0)));

        vm.prank(loanContract);
        vm.expectRevert(PWNUniswapV3LPValueDefaultModule.InvalidLLTV.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(1e4 + 1, false, new address[](0), new bool[](0)));
    }

    function test_shouldFail_whenCreditInLPPair_whenChainlinkNotEmpty() external {
        loan.creditAddress = token0;
        _mockGetLOAN(loanId, loan);

        vm.prank(loanContract);
        vm.expectRevert(Chainlink.ChainlinkInvalidInputLenghts.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, true, new address[](0), new bool[](1)));

        vm.prank(loanContract);
        vm.expectRevert(Chainlink.ChainlinkInvalidInputLenghts.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, false, new address[](0), new bool[](1)));

        loan.creditAddress = token1;
        _mockGetLOAN(loanId, loan);

        vm.prank(loanContract);
        vm.expectRevert(Chainlink.ChainlinkInvalidInputLenghts.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, true, new address[](0), new bool[](1)));

        vm.prank(loanContract);
        vm.expectRevert(Chainlink.ChainlinkInvalidInputLenghts.selector);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, false, new address[](0), new bool[](1)));
    }

    function test_shouldStoreDefaultDate() external {
        loan.creditAddress = makeAddr("credit");
        _mockGetLOAN(loanId, loan);

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.5e4, true, new address[](1), new bool[](2)));

        (
            uint256 lltv,
            bool token0Denominator,
            address[] memory feedIntermediaryDenominations,
            bool[] memory feedInvertFlags
        ) = defaultModule.defaultData(loanContract, loanId);

        assertEq(lltv, 0.5e4);
        assertEq(token0Denominator, true);
        assertEq(feedIntermediaryDenominations.length, 1);
        assertEq(feedInvertFlags.length, 2);
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

contract PWNUniswapV3LPValueDefaultModule_IsDefaulted_Test is PWNUniswapV3LPValueDefaultModuleTest {

    uint256 lpValue;

    function setUp() public override {
        super.setUp();

        _mockLOANDebt(loanId, 1e15);

        (lpValue, ) = UniswapV3.getLPValue(
            UniswapV3.Config(INonfungiblePositionManager(uniswapV3PositionManager), uniswapV3Factory),
            loan.collateral.id,
            true
        );
    }


    function test_shouldFetchLoanData() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.8e4, true, new address[](0), new bool[](0)));

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, loanId));

        defaultModule.isDefaulted(loanContract, loanId);
    }

    function testFuzz_shouldReturnFalse_whenLTVBelowLLTV_whenCreditIsLPDenomination(uint256 debt) external {
        loan.creditAddress = token0;
        _mockGetLOAN(loanId, loan);
        _mockLOANDebt(loanId, bound(debt, 1, (lpValue * 8 / 10) - 1));

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.8e4, true, new address[](0), new bool[](0)));

        assertFalse(defaultModule.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnTrue_whenLTVAboveLLTV_whenCreditIsLPDenomination(uint256 debt) external {
        loan.creditAddress = token0;
        _mockGetLOAN(loanId, loan);
        _mockLOANDebt(loanId, bound(debt, (lpValue * 8 / 10) + 1, 1_000 ether));

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(0.8e4, true, new address[](0), new bool[](0)));

        assertTrue(defaultModule.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnFalse_whenLTVBelowLLTV_whenCreditIsNotLPDenomination(uint256 debt) external {
        loan.creditAddress = makeAddr("credit");
        _mockGetLOAN(loanId, loan);
        _mockAssetDecimals(loan.creditAddress, 18);
        _mockLOANDebt(loanId, bound(debt, 1, lpValue * 2 - 1));
        _mockCollateralPrice(2 ether);

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(1e4, true, new address[](0), new bool[](1)));

        assertFalse(defaultModule.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnTrue_whenLTVAboveLLTV_whenCreditIsNotLPDenomination(uint256 debt) external {
        loan.creditAddress = makeAddr("credit");
        _mockGetLOAN(loanId, loan);
        _mockAssetDecimals(loan.creditAddress, 18);
        _mockLOANDebt(loanId, bound(debt, lpValue * 2 + 1, type(uint256).max));
        _mockCollateralPrice(2 ether);

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, _encodeProposerData(1e4, true, new address[](0), new bool[](1)));

        assertTrue(defaultModule.isDefaulted(loanContract, loanId));
    }

}


/*----------------------------------------------------------*|
|*  # DEFAULT DATA                                          *|
|*----------------------------------------------------------*/

contract PWNUniswapV3LPValueDefaultModule_DefaultData_Test is PWNUniswapV3LPValueDefaultModuleTest {

    function testFuzz_shouldReturnDefaultData(uint256 lltv) external {
        lltv = bound(lltv, 1, 10 ** defaultModule.LLTV_DECIMALS());

        loan.creditAddress = makeAddr("credit");
        _mockGetLOAN(loanId, loan);

        bool[] memory feedInvertFlags = new bool[](2);
        feedInvertFlags[0] = true;
        feedInvertFlags[1] = false;
        address[] memory feedIntermediaryDenominations = new address[](1);
        feedIntermediaryDenominations[0] = makeAddr("intermediary");

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(PWNUniswapV3LPValueDefaultModule.ProposerData(
            lltv,
            true,
            feedIntermediaryDenominations,
            feedInvertFlags
        )));

        (
            uint256 _lltv,
            bool _token0Denominator,
            address[] memory _feedIntermediaryDenominations,
            bool[] memory _feedInvertFlags
        ) = defaultModule.defaultData(loanContract, loanId);

        assertEq(_lltv, lltv);
        assertEq(_token0Denominator, true);
        assertEq(_feedInvertFlags.length, 2);
        assertEq(_feedIntermediaryDenominations.length, 1);
        for (uint256 i; i < 2; ++i) assertEq(_feedInvertFlags[i], feedInvertFlags[i]);
        assertEq(_feedIntermediaryDenominations[0], feedIntermediaryDenominations[0]);
    }

}
