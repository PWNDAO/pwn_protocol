// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import {
    PWNFixedProduct,
    PWNLoan,
    Terms,
    PWNHub,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    Chainlink,
    MultiToken,
    decodeChainlinkPriceFeedData
} from "pwn/periphery/product/PWNFixedProduct.sol";

import { PWNFixedProductHarness } from "test/harness/PWNFixedProductHarness.sol";
import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";

using MultiToken for address;

abstract contract PWNFixedProductTest is Test {

    PWNHub hub = PWNHub(makeAddr("hub"));
    PWNRevokedNonce revokedNonce = PWNRevokedNonce(makeAddr("revokedNonce"));
    PWNUtilizedCredit utilizedCredit = PWNUtilizedCredit(makeAddr("utilizedCredit"));
    IChainlinkFeedRegistryLike feedRegistry = IChainlinkFeedRegistryLike(makeAddr("feedRegistry"));
    IChainlinkAggregatorLike l2SequencerUptimeFeed = IChainlinkAggregatorLike(makeAddr("l2SequencerUptimeFeed"));
    address weth = makeAddr("weth");

    address loanContract = makeAddr("loanContract");
    uint256 proposerPK = 73661723;
    address proposer = vm.addr(proposerPK);
    address acceptor = makeAddr("acceptor");
    address borrower = makeAddr("borrower");
    address liquidator = makeAddr("liquidator");
    address token = makeAddr("token");
    address feed = makeAddr("feed");
    uint256 loanId = 42;
    PWNLoan.LOAN loan;

    PWNFixedProductHarness product;
    PWNFixedProduct.Proposal proposal;
    PWNFixedProduct.AcceptorValues acceptorValues;

    function setUp() public virtual {
        product = new PWNFixedProductHarness(hub, revokedNonce, utilizedCredit, feedRegistry, IChainlinkAggregatorLike(address(0)), weth);

        proposal = PWNFixedProduct.Proposal({
            collateralAddress: token,
            creditAddress: token,
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](1),
            acceptableLoanToValue: 9000, // 90%
            interestAPR: 0,
            duration: 365 days,
            liquidationLoanToValue: 9500, // 95%
            minCreditAmount: 1 ether,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: block.timestamp + 1 days,
            proposerSpecHash: bytes32(0),
            isProposerLender: true,
            loanContract: loanContract
        });
        proposal.feedInvertFlags[0] = false;

        acceptorValues = PWNFixedProduct.AcceptorValues({
            creditAmount: 10 ether,
            loanToValue: 5000
        });

        _mockFeed(feed);
        _mockLastRoundData(feed, 1 ether, 1);
        _mockFeedDecimals(feed, 18);
        _mockSequencerUptimeFeed(true, block.timestamp - 1);

        vm.mockCall(token, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));
        vm.mockCall(token, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(token, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));

        vm.mockCall(address(hub), abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(address(hub), abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN), abi.encode(true));

        vm.mockCall(address(revokedNonce), abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"), abi.encode(true));

        loan = PWNLoan.LOAN({
            borrower: borrower,
            lastUpdateTimestamp: uint40(0),
            collateral: token.ERC20(20 ether),
            creditAddress: token,
            principal: 10 ether,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            product: product
        });

        _mockGetLOAN(loanId, loan);
        _mockLOANDebt(loanId, 10 ether);
    }

    function _hashProposalTypedData(PWNFixedProduct.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            keccak256("Proposal(address collateralAddress,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 acceptableLoanToValue,uint256 interestAPR,uint256 duration,uint256 liquidationLoanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"),
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

    function _proposalData() internal view returns (bytes memory) {
        return abi.encode(proposal, acceptorValues);
    }

}


/*----------------------------------------------------------*|
|*  # GET COLLATERAL AMOUNT                                 *|
|*----------------------------------------------------------*/

contract PWNFixedProductTest_getCollateralAmount_Test is PWNFixedProductTest {

    address collAddr = makeAddr("collAddr");
    address credAddr = makeAddr("credAddr");
    uint256 credAmount = 10 ether;
    address[] fid = new address[](0);
    bool[] fif = new bool[](1);
    uint256 L2_GRACE_PERIOD = Chainlink.L2_GRACE_PERIOD;

    function setUp() virtual override public {
        super.setUp();

        _mockAssetDecimals(collAddr, 18);
        _mockAssetDecimals(credAddr, 18);
    }


    function test_shouldFail_whenLTVIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(PWNFixedProduct.LoanToValueZero.selector));
        product.getCollateralAmount(credAddr, credAmount, collAddr, fid, fif, 0);
    }

    function test_shouldReturnCollateralAmount() external {
        _mockFeedDecimals(feed, 8);

        _mockLastRoundData(feed, 2_500e8, 1);
        assertEq(
            product.getCollateralAmount(credAddr, 2 ether, collAddr, fid, fif, 5000),
            10_000 ether
        );

        _mockLastRoundData(feed, 1e8, 1);
        assertEq(
            product.getCollateralAmount(credAddr, 0, collAddr, fid, fif, 9500),
            0
        );

        _mockLastRoundData(feed, 0.5e8, 1);
        assertEq(
            product.getCollateralAmount(credAddr, 20 ether, collAddr, fid, fif, 2500),
            40 ether
        );

        _mockLastRoundData(feed, 4e8, 1);
        assertEq(
            product.getCollateralAmount(credAddr, 20 ether, collAddr, fid, fif, 20000),
            40 ether
        );
    }

}


/*----------------------------------------------------------*|
|*  # PROPOSAL MODULE                                       *|
|*----------------------------------------------------------*/

contract PWNFixedProductTest_ProposalModule_Test is PWNFixedProductTest {

    function test_shouldReturnNameAndVersion() external {
        (string memory name, string memory version) = product.nameAndVersion();
        assertEq(name, "PWN Fixed Product");
        assertEq(version, "1.5");
    }

    function test_shouldHashProposalTypedData() external {
        bytes memory proposalData = product.encodeProposalData(proposal, acceptorValues);
        assertEq(
            product.hashProposalTypedData(proposalData),
            _hashProposalTypedData(proposal)
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNFixedProductTest_acceptProposal_Test is PWNFixedProductTest {

    function testFuzz_shouldFail_whenCallerIsNotProposedLoanContract(address caller) external {
        vm.assume(caller != loanContract);

        vm.expectRevert(
            abi.encodeWithSelector(PWNFixedProduct.CallerNotLoanContract.selector, caller, loanContract)
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
            abi.encodeWithSelector(PWNFixedProduct.AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN)
        );
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, proposal.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(PWNFixedProduct.Expired.selector, timestamp, proposal.expiration));
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

        vm.expectRevert(abi.encodeWithSelector(PWNFixedProduct.DurationTooShort.selector));
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function test_shouldFail_whenMinCreditAmountZero() external {
        proposal.minCreditAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(PWNFixedProduct.MinCreditAmountNotSet.selector));
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenCreditLessThanMinCreditAmount(uint256 creditAmount) external {
        proposal.minCreditAmount = 10 ether;
        acceptorValues.creditAmount = bound(creditAmount, 0, proposal.minCreditAmount - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNFixedProduct.InsufficientCreditAmount.selector,
                acceptorValues.creditAmount, proposal.minCreditAmount
            )
        );
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function test_shouldRevokeNonce_whenAvailableCreditLimitEqualToZero(uint256 nonceSpace, uint256 nonce) external {
        proposal.availableCreditLimit = 0;
        proposal.nonceSpace = nonceSpace;
        proposal.nonce = nonce;

        vm.expectCall(
            address(revokedNonce),
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldUtilizeCredit(bytes32 id, uint256 creditAmount, uint256 limit) external {
        proposal.availableCreditLimit = bound(limit, 1 ether, 10_000_000_000 ether);
        proposal.utilizedCreditId = id;
        acceptorValues.creditAmount = bound(creditAmount, 1 ether, proposal.availableCreditLimit);

        vm.mockCall(
            address(utilizedCredit),
            abi.encodeWithSelector(PWNUtilizedCredit.utilizeCredit.selector),
            abi.encode("")
        );

        vm.expectCall(
            address(utilizedCredit),
            abi.encodeWithSelector(
                PWNUtilizedCredit.utilizeCredit.selector,
                proposer, proposal.utilizedCreditId, acceptorValues.creditAmount, proposal.availableCreditLimit
            )
        );

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenAcceptableLTVZero() external {
        proposal.acceptableLoanToValue = 0;

        vm.expectRevert(PWNFixedProduct.InvalidAcceptableLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidAcceptableLTV(uint256 ltv) external {
        proposal.acceptableLoanToValue = bound(ltv, 10001, type(uint256).max);

        vm.expectRevert(PWNFixedProduct.InvalidAcceptableLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidLLTV(uint256 lltv) external {
        proposal.acceptableLoanToValue = 9000;

        proposal.liquidationLoanToValue = bound(lltv, 0, proposal.acceptableLoanToValue - 1);
        vm.expectRevert(PWNFixedProduct.InvalidLiquidationLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        proposal.liquidationLoanToValue = bound(lltv, 10001, type(uint256).max);
        vm.expectRevert(PWNFixedProduct.InvalidLiquidationLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidLTV_whenLenderProposer(uint256 ltv) external {
        proposal.isProposerLender = true;
        proposal.acceptableLoanToValue = 9000;
        acceptorValues.loanToValue = bound(ltv, proposal.acceptableLoanToValue + 1, type(uint256).max);

        vm.expectRevert(PWNFixedProduct.InvalidLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidLTV_whenBorrowerProposer(uint256 ltv) external {
        proposal.isProposerLender = false;
        proposal.acceptableLoanToValue = 9000;
        acceptorValues.loanToValue = ltv;

        vm.assume(ltv != proposal.acceptableLoanToValue);

        vm.expectRevert(PWNFixedProduct.InvalidLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldStoreLoanData() external {
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        (uint40 apr, uint40 loanStart, uint40 defaultTimestamp, uint16 lltv, bytes memory feedData)
            = product.loanData(loanContract, loanId);

        assertEq(uint256(apr), proposal.interestAPR);
        assertEq(uint256(loanStart), block.timestamp);
        assertEq(uint256(defaultTimestamp), block.timestamp + proposal.duration);
        assertEq(uint256(lltv), proposal.liquidationLoanToValue);
        (bool[] memory fif, address[] memory fid) = decodeChainlinkPriceFeedData(feedData);
        assertEq(keccak256(abi.encode(fif)), keccak256(abi.encode(proposal.feedInvertFlags)));
        assertEq(fid, proposal.feedIntermediaryDenominations);
    }

    function testFuzz_shouldReturnLoanTerms(uint256 creditAmount, bool isProposerLender) external {
        proposal.isProposerLender = isProposerLender;
        acceptorValues.creditAmount = bound(creditAmount, proposal.minCreditAmount, 1_000_000 ether);
        acceptorValues.loanToValue = proposal.acceptableLoanToValue;

        vm.prank(loanContract);
        Terms memory terms = product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        uint256 collateralAmount = product.getCollateralAmount(
            proposal.creditAddress,
            acceptorValues.creditAmount,
            proposal.collateralAddress,
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags,
            acceptorValues.loanToValue
        );

        assertEq(terms.isProposerLender, isProposerLender);
        assertEq(terms.proposerSpecHash, proposal.proposerSpecHash);
        assertEq(uint8(terms.collateral.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.collateral.assetAddress, proposal.collateralAddress);
        assertEq(terms.collateral.id, 0);
        assertEq(terms.collateral.amount, collateralAmount);
        assertEq(terms.creditAddress, proposal.creditAddress);
        assertEq(terms.principal, acceptorValues.creditAmount);
    }

}


/*----------------------------------------------------------*|
|*  # INTEREST MODULE                                       *|
|*----------------------------------------------------------*/

contract PWNFixedProductTest_interest_Test is PWNFixedProductTest {

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

    function test_shouldCalculateInterest_whenLastUpdatedTimestampIsLoanStart() external {
        loan.pastAccruedInterest = 46 ether; // should be ignored
        loan.principal = 100 ether;
        loan.lastUpdateTimestamp = uint40(block.timestamp);
        _mockGetLOAN(loanId, loan);

        vm.warp(block.timestamp);

        product.workaround_updateApr(loanContract, loanId, 100); // 1%
        assertEq(product.interest(loanContract, loanId), 1 ether);

        vm.warp(182.5 days);

        product.workaround_updateApr(loanContract, loanId, 1000); // 10%
        assertEq(product.interest(loanContract, loanId), 10 ether);

        vm.warp(365 days);

        product.workaround_updateApr(loanContract, loanId, 10000); // 100%
        assertEq(product.interest(loanContract, loanId), 100 ether);
    }

    function test_shouldReturnZero_whenLastUpdateTimestampIsAfterLoanStart() external {
        loan.lastUpdateTimestamp = uint40(block.timestamp + 1);
        _mockGetLOAN(loanId, loan);

        vm.warp(block.timestamp);

        product.workaround_updateApr(loanContract, loanId, 100); // 1%
        assertEq(product.interest(loanContract, loanId), 0);

        vm.warp(182.5 days);

        product.workaround_updateApr(loanContract, loanId, 1000); // 10%
        assertEq(product.interest(loanContract, loanId), 0);

        vm.warp(365 days);

        product.workaround_updateApr(loanContract, loanId, 10000); // 100%
        assertEq(product.interest(loanContract, loanId), 0);
    }

}


/*----------------------------------------------------------*|
|*  # DEFAULT MODULE                                        *|
|*----------------------------------------------------------*/

contract PWNFixedProductTest_isDefaulted_Test is PWNFixedProductTest {

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
        _mockLastRoundData(feed, 2 ether, 1);

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, loanId));

        product.isDefaulted(loanContract, loanId);
    }

    function testFuzz_shouldReturnFalse_whenCollateralValueAboveLLTV(uint256 price) external {
        _mockLastRoundData(feed, bound(price, 0.1 ether, 1.9 ether - 1), 1);
        assertFalse(product.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnTrue_whenCollateralValueBelowLLTV(uint256 price) external {
        _mockLastRoundData(feed, bound(price, 1.9 ether, 10 ether), 1);
        assertTrue(product.isDefaulted(loanContract, loanId));
    }

}


/*----------------------------------------------------------*|
|*  # LIQUIDATION MODULE                                    *|
|*----------------------------------------------------------*/

contract PWNFixedProductTest_liquidate_Test is PWNFixedProductTest {

    function setUp() override public virtual {
        super.setUp();

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }


    function test_shouldFail_whenDataIsNotEmpty() external {
        vm.expectRevert(PWNFixedProduct.LiquidationDataNotEmpty.selector);
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

    function test_shouldTransferCollateralValueSurplusToBorrower() external {
        _mockLastRoundData(feed, 1 ether, 1);
        uint256 surplus = 9 ether;

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", liquidator, borrower, surplus)
        );

        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, 10 ether, loan.creditAddress, loan.collateral, "");
    }

    function test_shouldTransferCollateralToLiquidator() external {
        vm.expectCall(
            loan.collateral.assetAddress,
            abi.encodeWithSignature("transfer(address,uint256)", liquidator, loan.collateral.amount)
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
