// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import {
    PWNInstallmentsProduct,
    PWNLoan,
    Terms,
    PWNHub,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    Chainlink,
    MultiToken
} from "pwn/periphery/product/PWNInstallmentsProduct.sol";

import { PWNInstallmentsProductHarness } from "test/harness/PWNInstallmentsProductHarness.sol";

using MultiToken for address;

abstract contract PWNInstallmentsProductTest is Test {

    PWNHub hub = PWNHub(makeAddr("hub"));
    PWNRevokedNonce revokedNonce = PWNRevokedNonce(makeAddr("revokedNonce"));
    PWNUtilizedCredit utilizedCredit = PWNUtilizedCredit(makeAddr("utilizedCredit"));
    IChainlinkFeedRegistryLike feedRegistry = IChainlinkFeedRegistryLike(makeAddr("feedRegistry"));
    IChainlinkAggregatorLike l2SequencerUptimeFeed = IChainlinkAggregatorLike(makeAddr("l2SequencerUptimeFeed"));
    address weth = makeAddr("weth");

    address loanContract = makeAddr("loanContract");
    address proposer = makeAddr("proposer");
    address acceptor = makeAddr("acceptor");
    address borrower = makeAddr("borrower");
    address liquidator = makeAddr("liquidator");
    address token = makeAddr("token");
    address feed = makeAddr("feed");
    uint256 loanId = 42;
    PWNLoan.LOAN loan;

    PWNInstallmentsProductHarness product;
    PWNInstallmentsProduct.Proposal proposal;
    PWNInstallmentsProduct.AcceptorValues acceptorValues;

    function setUp() public virtual {
        product = new PWNInstallmentsProductHarness(hub, revokedNonce, utilizedCredit, feedRegistry, IChainlinkAggregatorLike(address(0)), weth);

        proposal = PWNInstallmentsProduct.Proposal({
            collateralAddress: token,
            creditAddress: token,
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](1),
            loanToValue: 5000, // 50%
            interestAPR: 0,
            postponement: 90 days,
            duration: 365 days,
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

        acceptorValues = PWNInstallmentsProduct.AcceptorValues({
            creditAmount: 10 ether
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

    function _hashProposalTypedData(PWNInstallmentsProduct.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            keccak256("Proposal(address collateralAddress,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 interestAPR,uint256 postponement,uint256 duration,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"),
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

contract PWNInstallmentsProduct_getCollateralAmount_Test is PWNInstallmentsProductTest {

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
        vm.expectRevert(abi.encodeWithSelector(PWNInstallmentsProduct.LoanToValueZero.selector));
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

contract PWNInstallmentsProduct_ProposalModule_Test is PWNInstallmentsProductTest {

    function test_shouldReturnNameAndVersion() external {
        (string memory name, string memory version) = product.nameAndVersion();
        assertEq(name, "PWN Installments Product");
        assertEq(version, "1.5");
    }

    function test_shouldHashProposalTypedData() external {
        bytes memory proposalData = abi.encode(proposal);
        assertEq(
            product.hashProposalTypedData(proposalData),
            _hashProposalTypedData(proposal)
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNInstallmentsProduct_acceptProposal_Test is PWNInstallmentsProductTest {

    function testFuzz_shouldFail_whenCallerIsNotProposedLoanContract(address caller) external {
        vm.assume(caller != loanContract);

        vm.expectRevert(
            abi.encodeWithSelector(PWNInstallmentsProduct.CallerNotLoanContract.selector, caller, loanContract)
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
            abi.encodeWithSelector(PWNInstallmentsProduct.AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN)
        );
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, proposal.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(PWNInstallmentsProduct.Expired.selector, timestamp, proposal.expiration));
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

        vm.expectRevert(abi.encodeWithSelector(PWNInstallmentsProduct.DurationTooShort.selector));
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function test_shouldFail_whenMinCreditAmountZero() external {
        proposal.minCreditAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(PWNInstallmentsProduct.MinCreditAmountNotSet.selector));
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenCreditLessThanMinCreditAmount(uint256 creditAmount) external {
        proposal.minCreditAmount = 10 ether;
        acceptorValues.creditAmount = bound(creditAmount, 0, proposal.minCreditAmount - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNInstallmentsProduct.InsufficientCreditAmount.selector,
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

    function testFuzz_shouldFail_whenLTVZero() external {
        proposal.loanToValue = 0;

        vm.expectRevert(PWNInstallmentsProduct.InvalidLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldFail_whenInvalidLTV(uint256 ltv) external {
        proposal.loanToValue = bound(ltv, 10001, type(uint256).max);

        vm.expectRevert(PWNInstallmentsProduct.InvalidLoanToValue.selector);
        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }

    function testFuzz_shouldStoreLoanData(uint256 principal, uint256 duration, uint256 postponement) external {
        principal = bound(principal, proposal.minCreditAmount, 1e40);
        duration = bound(duration, 90 days, 3650 days);
        postponement = bound(postponement, 0, duration / 2);

        proposal.duration = duration;
        proposal.postponement = postponement;
        acceptorValues.creditAmount = principal;

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        (uint40 apr, uint40 defaultTimestamp, uint176 debtLimitTangent) = product.loanData(loanContract, loanId);

        assertEq(uint256(apr), proposal.interestAPR);
        assertEq(uint256(defaultTimestamp), block.timestamp + proposal.duration);
        assertEq(uint256(debtLimitTangent), principal * 1e8 / (duration - postponement));
    }

    function testFuzz_shouldReturnLoanTerms(uint256 creditAmount, bool isProposerLender) external {
        proposal.isProposerLender = isProposerLender;
        acceptorValues.creditAmount = bound(creditAmount, proposal.minCreditAmount, 1_000_000 ether);

        vm.prank(loanContract);
        Terms memory terms = product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        uint256 collateralAmount = product.getCollateralAmount(
            proposal.creditAddress,
            acceptorValues.creditAmount,
            proposal.collateralAddress,
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags,
            proposal.loanToValue
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

contract PWNInstallmentsProduct_interest_Test is PWNInstallmentsProductTest {

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

contract PWNInstallmentsProduct_isDefaulted_Test is PWNInstallmentsProductTest {

    function setUp() override public virtual {
        super.setUp();

        proposal.postponement = 1;

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());
    }


    function testFuzz_shouldReturnTrue_whenAfterDefaultTimestamp(uint256 timestamp) external {
        vm.warp(bound(timestamp, block.timestamp + proposal.duration, type(uint256).max));

        assertTrue(product.isDefaulted(loanContract, loanId));
    }

    function test_shouldReturnTrue_whenDebtAboveLimit() external {
        assertFalse(product.isDefaulted(loanContract, loanId));

        vm.warp(block.timestamp + 1);
        assertTrue(product.isDefaulted(loanContract, loanId));

        vm.warp(block.timestamp + proposal.duration / 2 - 1);
        _mockLOANDebt(loanId, 5 ether);
        assertFalse(product.isDefaulted(loanContract, loanId));

        vm.warp(block.timestamp + 1);
        assertTrue(product.isDefaulted(loanContract, loanId));

        vm.warp(block.timestamp + proposal.duration / 4);
        _mockLOANDebt(loanId, 2.4 ether);
        assertFalse(product.isDefaulted(loanContract, loanId));

        _mockLOANDebt(loanId, 2.51 ether);
        assertTrue(product.isDefaulted(loanContract, loanId));
    }

}


/*----------------------------------------------------------*|
|*  # GET DEFAULT DEBT LIMIT                                *|
|*----------------------------------------------------------*/

contract PWNInstallmentsProduct_getDefaultDebtLimit_Test is PWNInstallmentsProductTest {

    function testFuzz_shouldReturnZero_whenPastDefaultTimestamp(uint256 timestamp) external {
        product.workaround_updateDefaultTimestamp(loanContract, loanId, 1);

        timestamp = bound(timestamp, 1, type(uint256).max);
        assertEq(product.getDefaultDebtLimit(loanContract, loanId, timestamp), 0);
    }

    function test_shouldReturnDebtLimit() external {
        uint256 duration = 360 days;
        product.workaround_updateDefaultTimestamp(loanContract, loanId, uint40(1 + duration));
        product.workaround_updateDebtLimitTangent(loanContract, loanId, 100e8); // 8 = debt limit tangent decimal

        assertEq(product.getDefaultDebtLimit(loanContract, loanId, 1), duration * 100);
        assertEq(product.getDefaultDebtLimit(loanContract, loanId, 1 + 12 days), (duration - 12 days) * 100);
        assertEq(product.getDefaultDebtLimit(loanContract, loanId, 1 + 120 days), (duration - 120 days) * 100);
        assertEq(product.getDefaultDebtLimit(loanContract, loanId, 1 + 180 days), (duration - 180 days) * 100);
        assertEq(product.getDefaultDebtLimit(loanContract, loanId, 1 + 300 days), (duration - 300 days) * 100);
        assertEq(product.getDefaultDebtLimit(loanContract, loanId, 1 + 360 days), 0);
    }

}


/*----------------------------------------------------------*|
|*  # LIQUIDATION MODULE                                    *|
|*----------------------------------------------------------*/

contract PWNInstallmentsProduct_liquidate_Test is PWNInstallmentsProductTest {

    address loanToken = makeAddr("loanToken");

    function setUp() override public virtual {
        super.setUp();

        vm.prank(loanContract);
        product.acceptProposal(loanId, acceptor, proposer, _proposalData());

        vm.mockCall(loanContract, abi.encodeWithSignature("loanToken()"), abi.encode(loanToken));
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId), abi.encode(liquidator));
    }


    function test_shouldFail_whenDataIsNotEmpty() external {
        vm.expectRevert(PWNInstallmentsProduct.LiquidationDataNotEmpty.selector);
        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, 1, loan.creditAddress, loan.collateral, "data");
    }

    function test_shouldFail_whenLiquidatorIsNotLoanOwner() external {
        address loanOwner = makeAddr("loanOwner");
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId), abi.encode(loanOwner));

        vm.expectCall(loanContract, abi.encodeWithSignature("loanToken()"));
        vm.expectCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId));

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNInstallmentsProduct.LiquidatorNotLoanOwner.selector,
                loanOwner, liquidator, loanContract, loanId
            )
        );
        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, 1, loan.creditAddress, loan.collateral, "");
    }

    function test_shouldTransferCollateralToLiquidator() external {
        vm.expectCall(
            loan.collateral.assetAddress,
            abi.encodeWithSignature("transfer(address,uint256)", liquidator, loan.collateral.amount)
        );

        vm.prank(loanContract);
        product.liquidate(loanId, liquidator, borrower, 1, loan.creditAddress, loan.collateral, "");
    }

    function test_shouldReturnZero() external {
        vm.prank(loanContract);
        uint256 result = product.liquidate(loanId, liquidator, borrower, 1, loan.creditAddress, loan.collateral, "");
        assertEq(result, 0);
    }

}
