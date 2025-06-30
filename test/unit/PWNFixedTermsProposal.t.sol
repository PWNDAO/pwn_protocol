// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import {
    PWNFixedTermsProposal,
    PWNBaseProposal,
    Terms,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    Chainlink,
    MultiToken,
    PWNChainlinkValueDefaultModule
} from "pwn/periphery/proposal/PWNFixedTermsProposal.sol";

import { PWNFixedTermsProposalHarness } from "test/harness/PWNFixedTermsProposalHarness.sol";
import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";


abstract contract PWNFixedTermsProposalTest is Test {

    address hub = makeAddr("hub");
    address revokedNonce = makeAddr("revokedNonce");
    address config = makeAddr("config");
    address utilizedCredit = makeAddr("utilizedCredit");
    address interestModule = makeAddr("interestModule");
    address defaultModule = makeAddr("defaultModule");
    address liquidationModule = makeAddr("liquidationModule");
    address loanContract = makeAddr("loanContract");
    uint256 proposerPK = 73661723;
    address proposer = vm.addr(proposerPK);
    address acceptor = makeAddr("acceptor");
    address token = makeAddr("token");
    address feedRegistry = makeAddr("feedRegistry");
    address feed = makeAddr("feed");
    address weth = makeAddr("weth");
    address l2SequencerUptimeFeed = makeAddr("l2SequencerUptimeFeed");

    PWNFixedTermsProposalHarness proposalContract;
    PWNFixedTermsProposal.Proposal proposal;
    PWNFixedTermsProposal.AcceptorValues acceptorValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNFixedTermsProposal.Proposal proposal);

    function setUp() virtual public {
        proposalContract = new PWNFixedTermsProposalHarness(hub, revokedNonce, config, utilizedCredit, interestModule, defaultModule, liquidationModule, feedRegistry, address(0), weth);

        proposal = PWNFixedTermsProposal.Proposal({
            collateralAddress: token,
            creditAddress: token,
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](1),
            maxAcceptableLTV: 9000, // 90%
            interestAPR: 0,
            fixationPeriod: 365 days,
            lltv: 9500, // 95%
            minCreditAmount: 1 ether,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: block.timestamp + 1 days,
            proposer: proposer,
            proposerSpecHash: keccak256("proposer spec"),
            isProposerLender: true,
            loanContract: loanContract
        });
        proposal.feedInvertFlags[0] = false;

        acceptorValues = PWNFixedTermsProposal.AcceptorValues({
            creditAmount: 10 ether,
            collateralAmount: 20 ether
        });

        _mockFeed(feed);
        _mockLastRoundData(feed, 1e18, 1);
        _mockFeedDecimals(feed, 18);
        _mockSequencerUptimeFeed(true, block.timestamp - 1);

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN), abi.encode(true));

        vm.mockCall(revokedNonce, abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"), abi.encode(true));
    }


    function _proposalHash(PWNFixedTermsProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNFixedTermsProposal"),
                keccak256("1.5"),
                block.chainid,
                address(proposalContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(address collateralAddress,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 maxAcceptableLTV,uint256 interestAPR,uint256 fixationPeriod,uint256 lltv,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"),
                proposalContract.exposed_erc712EncodeProposal(_proposal)
            ))
        ));
    }

    function _sign(uint256 pk, bytes32 proposalHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, proposalHash);
        return abi.encodePacked(r, s, v);
    }

    function _mockFeed(address _feed) internal {
        vm.mockCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector),
            abi.encode(_feed)
        );
    }

    function _mockFeed(address _feed, address base, address quote) internal {
        vm.mockCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, base, quote),
            abi.encode(_feed)
        );
    }

    function _mockLastRoundData(address _feed, int256 answer, uint256 updatedAt) internal {
        vm.mockCall(
            _feed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, answer, 0, updatedAt, 0)
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
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, isUp ? 0 : 1, startedAt, 0, 0)
        );
    }

    function _mockAssetDecimals(address asset, uint8 decimals) internal {
        vm.mockCall(asset, abi.encodeWithSignature("decimals()"), abi.encode(decimals));
    }

}


/*----------------------------------------------------------*|
|*  # GET PROPOSAL HASH                                     *|
|*----------------------------------------------------------*/

contract PWNFixedTermsProposal_GetProposalHash_Test is PWNFixedTermsProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNFixedTermsProposal_MakeProposal_Test is PWNFixedTermsProposalTest {

    function testFuzz_shouldFail_whenCallerIsNotProposer(address caller) external {
        vm.assume(caller != proposal.proposer);

        vm.expectRevert(abi.encodeWithSelector(PWNBaseProposal.CallerIsNotStatedProposer.selector, proposal.proposer));
        vm.prank(caller);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldEmit_ProposalMade() external {
        vm.expectEmit();
        emit ProposalMade(_proposalHash(proposal), proposal.proposer, proposal);

        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldMakeProposal() external {
        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);

        assertTrue(proposalContract.proposalsMade(_proposalHash(proposal)));
    }

    function test_shouldReturnProposalHash() external {
        vm.prank(proposal.proposer);
        assertEq(proposalContract.makeProposal(proposal), _proposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # ENCODE DECODE PROPOSAL DATA                           *|
|*----------------------------------------------------------*/

contract PWNFixedTermsProposal_EncodeDecodeProposalData_Test is PWNFixedTermsProposalTest {

    function test_shouldEncodeDecodedProposalData() external {
        (
            PWNFixedTermsProposal.Proposal memory _proposal,
            PWNFixedTermsProposal.AcceptorValues memory _acceptorValues
        ) = proposalContract.decodeProposalData(proposalContract.encodeProposalData(proposal, acceptorValues));

        assertEq(proposal.collateralAddress, _proposal.collateralAddress);
        assertEq(proposal.creditAddress, _proposal.creditAddress);
        assertEq(proposal.feedIntermediaryDenominations, _proposal.feedIntermediaryDenominations);
        assertEq(proposal.feedInvertFlags.length, _proposal.feedInvertFlags.length);
        assertEq(keccak256(abi.encode(proposal.feedInvertFlags)), keccak256(abi.encode(_proposal.feedInvertFlags)));
        assertEq(proposal.maxAcceptableLTV, _proposal.maxAcceptableLTV);
        assertEq(proposal.interestAPR, _proposal.interestAPR);
        assertEq(proposal.fixationPeriod, _proposal.fixationPeriod);
        assertEq(proposal.lltv, _proposal.lltv);
        assertEq(proposal.minCreditAmount, _proposal.minCreditAmount);
        assertEq(proposal.availableCreditLimit, _proposal.availableCreditLimit);
        assertEq(proposal.utilizedCreditId, _proposal.utilizedCreditId);
        assertEq(proposal.nonceSpace, _proposal.nonceSpace);
        assertEq(proposal.nonce, _proposal.nonce);
        assertEq(proposal.expiration, _proposal.expiration);
        assertEq(proposal.proposer, _proposal.proposer);
        assertEq(proposal.proposerSpecHash, _proposal.proposerSpecHash);
        assertEq(proposal.isProposerLender, _proposal.isProposerLender);
        assertEq(proposal.loanContract, _proposal.loanContract);

        assertEq(acceptorValues.creditAmount, _acceptorValues.creditAmount);
        assertEq(acceptorValues.collateralAmount, _acceptorValues.collateralAmount);
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN TO VALUE                                     *|
|*----------------------------------------------------------*/

contract PWNFixedTermsProposal_GetLoanToValue_Test is PWNFixedTermsProposalTest {

    address collAddr = makeAddr("collAddr");
    address credAddr = makeAddr("credAddr");
    uint256 credAmount = 10 ether;
    uint256 collAmount = 20 ether;
    address[] feedIntermediaryDenominations = new address[](0);
    bool[] feedInvertFlags = new bool[](1);
    uint256 L2_GRACE_PERIOD = Chainlink.L2_GRACE_PERIOD;

    function setUp() virtual override public {
        super.setUp();

        _mockAssetDecimals(collAddr, 18);
        _mockAssetDecimals(credAddr, 18);
    }


    function test_shouldFail_whenCollateralAmountIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(PWNFixedTermsProposal.CollateralAmountZero.selector));
        proposalContract.getLoanToValue(credAddr, credAmount, collAddr, 0, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFetchSequencerUptimeFeed_whenFeedSet() external {
        vm.warp(1e9);

        proposalContract = new PWNFixedTermsProposalHarness(hub, revokedNonce, config, utilizedCredit, interestModule, defaultModule, liquidationModule, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(true, block.timestamp - L2_GRACE_PERIOD - 1);
        _mockLastRoundData(feed, 1e18, block.timestamp);

        vm.expectCall(
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector)
        );

        proposalContract.getLoanToValue(credAddr, credAmount, collAddr, collAmount, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFail_whenL2SequencerDown_whenFeedSet() external {
        vm.warp(1e9);

        proposalContract = new PWNFixedTermsProposalHarness(hub, revokedNonce, config, utilizedCredit, interestModule, defaultModule, liquidationModule, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(false, block.timestamp - L2_GRACE_PERIOD - 1);

        vm.expectRevert(abi.encodeWithSelector(Chainlink.L2SequencerDown.selector));
        proposalContract.getLoanToValue(credAddr, credAmount, collAddr, collAmount, feedIntermediaryDenominations, feedInvertFlags);
    }

    function testFuzz_shouldFail_whenL2SequencerUp_whenInGracePeriod_whenFeedSet(uint256 startedAt) external {
        vm.warp(1e9);
        startedAt = bound(startedAt, block.timestamp - L2_GRACE_PERIOD, block.timestamp);

        proposalContract = new PWNFixedTermsProposalHarness(hub, revokedNonce, config, utilizedCredit, interestModule, defaultModule, liquidationModule, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(true, startedAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.GracePeriodNotOver.selector,
                block.timestamp - startedAt, L2_GRACE_PERIOD
            )
        );
        proposalContract.getLoanToValue(credAddr, credAmount, collAddr, collAmount, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldNotFetchSequencerUptimeFeed_whenFeedNotSet() external {
        vm.expectCall(
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            0
        );

        proposalContract.getLoanToValue(credAddr, credAmount, collAddr, collAmount, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFail_whenIntermediaryDenominationsOutOfBounds() external {
        uint256 max = proposalContract.MAX_INTERMEDIARY_DENOMINATIONS();
        feedIntermediaryDenominations = new address[](max + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.IntermediaryDenominationsOutOfBounds.selector,
                max + 1, max
            )
        );
        proposalContract.getLoanToValue(credAddr, credAmount, collAddr, collAmount, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFetchCreditAndCollateralPrices() external {
        feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = makeAddr("inter1");
        feedIntermediaryDenominations[1] = makeAddr("inter2");
        feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = false;
        feedInvertFlags[1] = false;
        feedInvertFlags[2] = false;

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, feedIntermediaryDenominations[0])
        );
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[0], feedIntermediaryDenominations[1])
        );
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[1], collAddr)
        );

        proposalContract.getLoanToValue(credAddr, credAmount, collAddr, collAmount, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldFetchETHPrice_whenWETH() external {
        _mockAssetDecimals(weth, 18);

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, collAddr)
        );
        proposalContract.getLoanToValue(weth, credAmount, collAddr, collAmount, feedIntermediaryDenominations, feedInvertFlags);

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH)
        );
        proposalContract.getLoanToValue(credAddr, credAmount, weth, collAmount, feedIntermediaryDenominations, feedInvertFlags);
    }

    function test_shouldReturnLoanToValue() external {
        _mockFeedDecimals(feed, 8);

        _mockLastRoundData(feed, 2500e8, 1);
        assertEq(
            proposalContract.getLoanToValue(credAddr, 2e18, collAddr, 5000e18, feedIntermediaryDenominations, feedInvertFlags),
            10000
        );

        _mockLastRoundData(feed, 1e8, 1);
        assertEq(
            proposalContract.getLoanToValue(credAddr, 0, collAddr, 1000e18, feedIntermediaryDenominations, feedInvertFlags),
            0
        );

        _mockLastRoundData(feed, 0.5e8, 1);
        assertEq(
            proposalContract.getLoanToValue(credAddr, 20e18, collAddr, 20e18, feedIntermediaryDenominations, feedInvertFlags),
            5000
        );

        _mockLastRoundData(feed, 4e8, 1);
        assertEq(
            proposalContract.getLoanToValue(credAddr, 20e18, collAddr, 100e18, feedIntermediaryDenominations, feedInvertFlags),
            8000
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNFixedTermsProposal_AcceptProposal_Test is PWNFixedTermsProposalTest {

    function testFuzz_shouldFail_whenLLTVLowerThanAcceptableLTV(uint256 lltv) external {
        proposal.maxAcceptableLTV = 9000;
        proposal.lltv = bound(lltv, 0, proposal.maxAcceptableLTV - 1);

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(PWNFixedTermsProposal.InvalidLiquidationLoanToValue.selector);
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldFail_whenLLTVHigherThan100(uint256 lltv) external {
        proposal.lltv = bound(lltv, 10001, type(uint256).max);

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(PWNFixedTermsProposal.InvalidLiquidationLoanToValue.selector);
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function test_shouldFail_whenLTVHigherThanMaxAcceptableLTV() external {
        proposal.maxAcceptableLTV = 9000;

        acceptorValues.creditAmount = 9.001 ether; // 90.01%
        acceptorValues.collateralAmount = 10 ether;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNFixedTermsProposal.LoanToValueTooHigh.selector, 9001, 9000));
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function test_shouldFail_whenZeroMinCreditAmount() external {
        proposal.minCreditAmount = 0;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(PWNFixedTermsProposal.MinCreditAmountNotSet.selector);
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldFail_whenCreditAmountLessThanMinCreditAmount(uint256 creditAmount) external {
        acceptorValues.creditAmount = bound(creditAmount, 1, proposal.minCreditAmount - 1);

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNFixedTermsProposal.InsufficientCreditAmount.selector,
                acceptorValues.creditAmount,
                proposal.minCreditAmount
            )
        );
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 creditAmount, uint256 collateralAmount, bool isProposerLender
    ) external {
        acceptorValues.creditAmount = bound(creditAmount, proposal.minCreditAmount, 1_000_000 ether);
        acceptorValues.collateralAmount = bound(collateralAmount, acceptorValues.creditAmount * 2, acceptorValues.creditAmount * 3);
        proposal.isProposerLender = isProposerLender;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.prank(loanContract);
        Terms memory terms = proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(terms.proposalHash, proposalHash);
        assertEq(terms.lender, isProposerLender ? proposal.proposer : acceptor);
        assertEq(terms.borrower, isProposerLender ? acceptor : proposal.proposer);
        assertEq(terms.proposerSpecHash, proposal.proposerSpecHash);
        assertEq(uint8(terms.collateral.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.collateral.assetAddress, proposal.collateralAddress);
        assertEq(terms.collateral.id, 0);
        assertEq(terms.collateral.amount, acceptorValues.collateralAmount);
        assertEq(terms.creditAddress, proposal.creditAddress);
        assertEq(terms.principal, acceptorValues.creditAmount);
        assertEq(address(terms.interestModule), address(interestModule));
        bytes memory expectedInterestData = abi.encode(proposal.interestAPR, proposal.fixationPeriod);
        assertEq(terms.interestModuleProposerData.length, expectedInterestData.length);
        assertEq(keccak256(terms.interestModuleProposerData), keccak256(expectedInterestData));
        assertEq(address(terms.defaultModule), address(defaultModule));
        bytes memory expectedDefaultData = abi.encode(PWNChainlinkValueDefaultModule.ProposerData(proposal.lltv, proposal.feedIntermediaryDenominations, proposal.feedInvertFlags));
        assertEq(terms.defaultModuleProposerData.length, expectedDefaultData.length);
        assertEq(keccak256(terms.defaultModuleProposerData), keccak256(expectedDefaultData));
        assertEq(address(terms.liquidationModule), address(liquidationModule));
        assertEq(terms.liquidationModuleProposerData.length, 0);
    }

}


/*----------------------------------------------------------*|
|*  # ERC712 ENCODE PROPOSAL                                *|
|*----------------------------------------------------------*/

contract PWNFixedTermsProposal_Erc712EncodeProposal_Test is PWNFixedTermsProposalTest {

    function test_shouldERC712EncodeProposal() external {
        PWNFixedTermsProposal.ERC712Proposal memory proposalErc712 = PWNFixedTermsProposal.ERC712Proposal(
            proposal.collateralAddress,
            proposal.creditAddress,
            keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            proposal.maxAcceptableLTV,
            proposal.interestAPR,
            proposal.fixationPeriod,
            proposal.lltv,
            proposal.minCreditAmount,
            proposal.availableCreditLimit,
            proposal.utilizedCreditId,
            proposal.nonceSpace,
            proposal.nonce,
            proposal.expiration,
            proposal.proposer,
            proposal.proposerSpecHash,
            proposal.isProposerLender,
            proposal.loanContract
        );

        assertEq(
            keccak256(abi.encode(proposalErc712)),
            keccak256(proposalContract.exposed_erc712EncodeProposal(proposal))
        );
    }

}
