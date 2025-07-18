// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import {
    PWNUniswapV3IndividualProduct,
    PWNLoan,
    Terms,
    PWNHub,
    PWNRevokedNonce,
    INonfungiblePositionManager,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    Chainlink,
    MultiToken,
    decodeChainlinkPriceFeedData
} from "pwn/periphery/product/PWNUniswapV3IndividualProduct.sol";

import { PWNUniswapV3IndividualProductHarness } from "test/harness/PWNUniswapV3IndividualProductHarness.sol";
import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";

using MultiToken for address;

abstract contract PWNUniswapV3IndividualProductTest is Test {

    PWNHub hub = PWNHub(makeAddr("hub"));
    PWNRevokedNonce revokedNonce = PWNRevokedNonce(makeAddr("revokedNonce"));
    address uniswapV3Factory = makeAddr("uniswapV3Factory");
    INonfungiblePositionManager uniswapNFTPositionManager = INonfungiblePositionManager(makeAddr("uniswapNFTPositionManager"));
    IChainlinkFeedRegistryLike feedRegistry = IChainlinkFeedRegistryLike(makeAddr("feedRegistry"));
    IChainlinkAggregatorLike l2SequencerUptimeFeed = IChainlinkAggregatorLike(makeAddr("l2SequencerUptimeFeed"));
    address weth = makeAddr("weth");

    address loanContract = makeAddr("loanContract");
    address borrower = makeAddr("borrower");
    address proposer = borrower;
    address acceptor = makeAddr("acceptor");
    address liquidator = makeAddr("liquidator");
    address feed = makeAddr("feed");
    uint256 loanId = 42;
    PWNLoan.LOAN loan;

    address token0 = makeAddr("token0");
    address token1 = makeAddr("token1");
    address token = token1;
    uint24 fee = 3000;
    address pool = 0xb44E273AE4071AA4a0F2b05ee96f20BB6FfD568b;
    uint256 token0Value = 101572;
    uint256 token1Value = 331794706808;

    PWNUniswapV3IndividualProductHarness product;
    PWNUniswapV3IndividualProduct.Proposal proposal;

    function setUp() public virtual {
        product = new PWNUniswapV3IndividualProductHarness(hub, revokedNonce, uniswapV3Factory, uniswapNFTPositionManager, feedRegistry, IChainlinkAggregatorLike(address(0)), weth);

        proposal = PWNUniswapV3IndividualProduct.Proposal({
            collateralId: 42,
            token0Denominator: false,
            creditAddress: token,
            creditAmount: 1e10,
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            acceptableLoanToValue: 9000, // 90%
            interestAPR: 0,
            duration: 365 days,
            liquidationLoanToValue: 9500, // 95%
            nonceSpace: 0,
            nonce: 0,
            expiration: block.timestamp + 1 days,
            proposerSpecHash: bytes32(0),
            loanContract: loanContract
        });

        vm.mockCall(token, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));
        vm.mockCall(token, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(token, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));

        vm.mockCall(address(hub), abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(address(hub), abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN), abi.encode(true));

        vm.mockCall(address(revokedNonce), abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"), abi.encode(true));

        vm.mockCall(address(uniswapNFTPositionManager), abi.encodeWithSignature("factory()"), abi.encode(uniswapV3Factory));
        _mockPosition(100_000, 200_000, 100e6, 0, 0);
        _mockPool(pool, 150_000);

        loan = PWNLoan.LOAN({
            borrower: borrower,
            lastUpdateTimestamp: uint40(0),
            collateral: address(uniswapNFTPositionManager).ERC721(proposal.collateralId),
            creditAddress: token,
            principal: 1e10,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            product: product
        });

        _mockGetLOAN(loanId, loan);
        _mockLOANDebt(loanId, 1e10);
    }

    function _hashProposalTypedData(PWNUniswapV3IndividualProduct.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            keccak256("Proposal(uint256 collateralId,bool token0Denominator,address creditAddress,uint256 creditAmount,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 acceptableLoanToValue,uint256 interestAPR,uint256 duration,uint256 liquidationLoanToValue,uint256 nonceSpace,uint256 nonce,uint256 expiration,bytes32 proposerSpecHash,address loanContract)"),
            product.exposed_erc712EncodeProposal(_proposal)
        ));
    }

    function _mockFeed(address _feed) internal {
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector),
            abi.encode(_feed)
        );
    }

    function _mockFeed(address _feed, address base, address quote) internal {
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, base, quote),
            abi.encode(_feed)
        );
    }

    function _mockLastRoundData(address _feed, uint256 answer, uint256 updatedAt) internal {
        vm.mockCall(
            _feed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, int256(answer), 0, updatedAt, 0)
        );
    }

    function _mockFeedDecimals(address _feed, uint8 decimals) internal {
        vm.mockCall(
            _feed,
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

    function _mockAssetDecimals(address asset, uint8 decimals) internal {
        vm.mockCall(asset, abi.encodeWithSignature("decimals()"), abi.encode(decimals));
    }

    function _mockGetLOAN(uint256 _loanId, PWNLoan.LOAN memory _loan) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, _loanId), abi.encode(_loan));
    }

    function _mockLOANDebt(uint256 _loanId, uint256 _debt) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, _loanId), abi.encode(_debt));
    }

    function _mockPosition(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 tokensOwed0,
        uint256 tokensOwed1
    ) internal {
        vm.mockCall(
            address(uniswapNFTPositionManager),
            abi.encodeWithSelector(INonfungiblePositionManager.positions.selector),
            abi.encode(0, 0, token0, token1, fee, tickLower, tickUpper, liquidity, 0, 0, tokensOwed0, tokensOwed1)
        );
    }

    function _mockPool(address _pool, int24 currentTick) internal {
        vm.mockCall(_pool, abi.encodeWithSignature("slot0()"), abi.encode(0, currentTick, 0, 2, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("observations(uint256)"), abi.encode(0, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("liquidity()"), abi.encode(0)); // need to not revert
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal0X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal1X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("ticks(int24)"), abi.encode(0, 0, 0, 0, 0, 0, 0, 0));
    }

    function _proposalData() internal view returns (bytes memory) {
        return abi.encode(proposal);
    }

}


/*----------------------------------------------------------*|
|*  # GET LP VALUE                                          *|
|*----------------------------------------------------------*/

contract PWNUniswapV3IndividualProductTest_getLPValue_Test is PWNUniswapV3IndividualProductTest {

    address[] fid = new address[](0);
    bool[] fif = new bool[](0);
    uint256 L2_GRACE_PERIOD = Chainlink.L2_GRACE_PERIOD;


    function test_shouldReturnLPValueInToken0_whenCreditIsToken0() external {
        assertEq(
            product.getLPValue(token0, proposal.collateralId, true, fid, fif),
            token0Value
        );
    }

    function test_shouldReturnLPValueInToken1_whenCreditIsToken1() external {
        assertEq(
            product.getLPValue(token1, proposal.collateralId, false, fid, fif),
            token1Value
        );
    }

    function test_shouldConvertDenominationViaChainlink_whenCreditNotToken0Or1() external {
        address credAddr = makeAddr("credAddr");
        fif = new bool[](1);
        fif[0] = false;

        _mockFeed(feed);
        _mockLastRoundData(feed, 300e6, 1);
        _mockFeedDecimals(feed, 6);
        _mockAssetDecimals(credAddr, 22);
        _mockAssetDecimals(token0, 6);

        assertEq(
            product.getLPValue(credAddr, proposal.collateralId, true, fid, fif),
            token0Value * 300e16
        );
    }

}


/*----------------------------------------------------------*|
|*  # PROPOSAL MODULE                                       *|
|*----------------------------------------------------------*/

contract PWNUniswapV3IndividualProductTest_ProposalModule_Test is PWNUniswapV3IndividualProductTest {

    function test_shouldReturnNameAndVersion() external {
        (string memory name, string memory version) = product.nameAndVersion();
        assertEq(name, "PWN Uniswap V3 Individual Product");
        assertEq(version, "1.5");
    }

    function test_shouldHashProposalTypedData() external {
        bytes memory proposalData = product.encodeProposalData(proposal);
        assertEq(
            product.hashProposalTypedData(proposalData),
            _hashProposalTypedData(proposal)
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNUniswapV3IndividualProductTest_acceptProposal_Test is PWNUniswapV3IndividualProductTest {

    function testFuzz_shouldFail_whenCallerIsNotProposedLoanContract(address caller) external {
        vm.assume(caller != loanContract);

        vm.expectRevert(
            abi.encodeWithSelector(PWNUniswapV3IndividualProduct.CallerNotLoanContract.selector, caller, loanContract)
        );
        vm.prank(caller);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function test_shouldFail_whenCallerNotTagged_ACTIVE_LOAN() external {
        vm.mockCall(
            address(hub),
            abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNUniswapV3IndividualProduct.AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN)
        );
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, proposal.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(PWNUniswapV3IndividualProduct.Expired.selector, timestamp, proposal.expiration));
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenNonceNotUsable(uint256 nonceSpace, uint256 nonce) external {
        proposal.nonceSpace = nonceSpace;
        proposal.nonce = nonce;

        vm.mockCall(
            address(revokedNonce),
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            address(revokedNonce),
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceNotUsable.selector, proposer, nonceSpace, nonce));
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenDurationShorterThanMin(uint256 duration) external {
        proposal.duration = bound(duration, 0, product.MIN_DURATION() - 1);

        vm.expectRevert(abi.encodeWithSelector(PWNUniswapV3IndividualProduct.DurationTooShort.selector));
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function test_shouldRevokeNonce(uint256 nonceSpace, uint256 nonce) external {
        proposal.nonceSpace = nonceSpace;
        proposal.nonce = nonce;

        vm.expectCall(
            address(revokedNonce),
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenAcceptableLTVZero() external {
        proposal.acceptableLoanToValue = 0;

        vm.expectRevert(PWNUniswapV3IndividualProduct.InvalidAcceptableLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidAcceptableLTV(uint256 ltv) external {
        proposal.acceptableLoanToValue = bound(ltv, 10001, type(uint256).max);

        vm.expectRevert(PWNUniswapV3IndividualProduct.InvalidAcceptableLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidLLTV(uint256 lltv) external {
        proposal.acceptableLoanToValue = 9000;

        proposal.liquidationLoanToValue = bound(lltv, 0, proposal.acceptableLoanToValue - 1);
        vm.expectRevert(PWNUniswapV3IndividualProduct.InvalidLiquidationLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        proposal.liquidationLoanToValue = bound(lltv, 10001, type(uint256).max);
        vm.expectRevert(PWNUniswapV3IndividualProduct.InvalidLiquidationLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidLTV(uint256 creditAmount) external {
        proposal.acceptableLoanToValue = 9000;
        proposal.creditAmount = bound(creditAmount, token1Value * 1e4 / 9000, 1_000_000 ether);
        uint256 ltv = proposal.creditAmount * 1e4 / token1Value;

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNUniswapV3IndividualProduct.InvalidLoanToValue.selector, ltv, proposal.acceptableLoanToValue
            )
        );
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function test_shouldStoreLoanData() external {
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        (uint40 apr, uint40 defaultTimestamp, uint16 lltv, bool token0Denominator, bytes memory feedData)
            = product.loanData(loanContract, loanId);

        assertEq(uint256(apr), proposal.interestAPR);
        assertEq(uint256(defaultTimestamp), block.timestamp + proposal.duration);
        assertEq(uint256(lltv), proposal.liquidationLoanToValue);
        assertEq(token0Denominator, proposal.token0Denominator);
        (bool[] memory fif, address[] memory fid) = decodeChainlinkPriceFeedData(feedData);
        assertEq(keccak256(abi.encode(fif)), keccak256(abi.encode(proposal.feedInvertFlags)));
        assertEq(fid, proposal.feedIntermediaryDenominations);
    }

    function test_shouldReturnLoanTerms() external {
        vm.prank(loanContract);
        Terms memory terms = product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        assertEq(terms.isProposerLender, false);
        assertEq(terms.proposerSpecHash, proposal.proposerSpecHash);
        assertEq(uint8(terms.collateral.category), uint8(MultiToken.Category.ERC721));
        assertEq(terms.collateral.assetAddress, address(uniswapNFTPositionManager));
        assertEq(terms.collateral.id, proposal.collateralId);
        assertEq(terms.collateral.amount, 0);
        assertEq(terms.creditAddress, proposal.creditAddress);
        assertEq(terms.principal, proposal.creditAmount);
    }

}


/*----------------------------------------------------------*|
|*  # INTEREST MODULE                                       *|
|*----------------------------------------------------------*/

contract PWNUniswapV3IndividualProductTest_interest_Test is PWNUniswapV3IndividualProductTest {

    function setUp() override public virtual {
        super.setUp();

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }


    function test_shouldFetchLoanData() external {
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));

        product.interest(loanContract, loanId);
    }

    function test_shouldReturnZero_whenLastUpdateTimestampIsInFuture() external {
        loan.lastUpdateTimestamp = uint40(block.timestamp + 1);
        _mockGetLOAN(loanId, loan);

        assertEq(product.interest(loanContract, loanId), 0);
    }

    function test_shouldCalculateInterest() external {
        loan.pastAccruedInterest = 46 ether; // should be ignored
        loan.principal = 100 ether;
        loan.lastUpdateTimestamp = uint40(0);
        _mockGetLOAN(loanId, loan);

        vm.warp(0);

        product.workaround_updateApr(loanContract, loanId, 100); // 1%
        assertEq(product.interest(loanContract, loanId), 0);

        product.workaround_updateApr(loanContract, loanId, 1000); // 10%
        assertEq(product.interest(loanContract, loanId), 0);

        product.workaround_updateApr(loanContract, loanId, 10000); // 100%
        assertEq(product.interest(loanContract, loanId), 0);

        vm.warp(182.5 days);

        product.workaround_updateApr(loanContract, loanId, 100); // 1%
        assertEq(product.interest(loanContract, loanId), 0.5 ether);

        product.workaround_updateApr(loanContract, loanId, 1000); // 10%
        assertEq(product.interest(loanContract, loanId), 5 ether);

        product.workaround_updateApr(loanContract, loanId, 10000); // 100%
        assertEq(product.interest(loanContract, loanId), 50 ether);

        vm.warp(365 days);

        product.workaround_updateApr(loanContract, loanId, 100); // 1%
        assertEq(product.interest(loanContract, loanId), 1 ether);

        product.workaround_updateApr(loanContract, loanId, 1000); // 10%
        assertEq(product.interest(loanContract, loanId), 10 ether);

        product.workaround_updateApr(loanContract, loanId, 10000); // 100%
        assertEq(product.interest(loanContract, loanId), 100 ether);
    }

}


/*----------------------------------------------------------*|
|*  # DEFAULT MODULE                                        *|
|*----------------------------------------------------------*/

contract PWNUniswapV3IndividualProductTest_isDefaulted_Test is PWNUniswapV3IndividualProductTest {

    function setUp() override public virtual {
        super.setUp();

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }


    function testFuzz_shouldFail_whenAfterDefaultTimestamp(uint256 timestamp) external {
        vm.warp(bound(timestamp, block.timestamp + proposal.duration, type(uint256).max));

        assertTrue(product.isDefaulted(loanContract, loanId));
    }

    function test_shouldFetchLoanData() external {
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, loanId));

        product.isDefaulted(loanContract, loanId);
    }

    function testFuzz_shouldReturnFalse_whenCollateralValueAboveLLTV(uint256 debt) external {
        _mockLOANDebt(loanId, bound(debt, 1, token1Value * 9500 / 1e4 - 1));
        assertFalse(product.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnTrue_whenCollateralValueBelowLLTV(uint256 debt) external {
        _mockLOANDebt(loanId, bound(debt, token1Value * 9500 / 1e4, type(uint256).max));
        assertTrue(product.isDefaulted(loanContract, loanId));
    }

}


/*----------------------------------------------------------*|
|*  # LIQUIDATION MODULE                                    *|
|*----------------------------------------------------------*/

contract PWNUniswapV3IndividualProductTest_liquidate_Test is PWNUniswapV3IndividualProductTest {

    function setUp() override public virtual {
        super.setUp();

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }


    function test_shouldFail_whenDataIsNotEmpty() external {
        vm.expectRevert(PWNUniswapV3IndividualProduct.LiquidationDataNotEmpty.selector);
        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, 1, loan.creditAddress, loan.collateral, "data");
    }

    function testFuzz_shouldTransferDebtFromLiquidator(uint256 debt) external {
        debt = bound(debt, 1, type(uint256).max);

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", liquidator, address(product), debt)
        );

        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, debt, loan.creditAddress, loan.collateral, "");
    }

    function testFuzz_shouldApproveDebtAmountToLoanContract(uint256 debt) external {
        debt = bound(debt, 1, type(uint256).max);

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature("approve(address,uint256)", loanContract, debt)
        );

        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, debt, loan.creditAddress, loan.collateral, "");
    }

    function testFuzz_shouldTransferCollateralValueSurplusToBorrower(uint256 debt) external {
        uint256 lpLiquidationValue = token1Value * 9500 / 1e4;
        debt = bound(debt, 1, lpLiquidationValue - 1);
        uint256 surplus = lpLiquidationValue - debt;

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", liquidator, borrower, surplus)
        );

        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, debt, loan.creditAddress, loan.collateral, "");
    }

    function test_shouldTransferCollateralToLiquidator() external {
        vm.expectCall(
            loan.collateral.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(product), liquidator, loan.collateral.id)
        );

        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, 1, loan.creditAddress, loan.collateral, "");
    }

    function testFuzz_shouldReturnDebtAmount(uint256 debt) external {
        debt = bound(debt, 1, type(uint256).max);

        vm.prank(loanContract);
        uint256 result = product.liquidate(loanId, liquidator, borrower, debt, loan.creditAddress, loan.collateral, "");
        assertEq(result, debt);
    }

}
