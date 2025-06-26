// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import {
    PWNUniswapV3LPIndividualProposal,
    PWNBaseProposal,
    Terms,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike,
    INonfungiblePositionManager,
    MultiToken
} from "pwn/periphery/proposal/PWNUniswapV3LPIndividualProposal.sol";

import { PWNUniswapV3LPIndividualProposalHarness } from "test/harness/PWNUniswapV3LPIndividualProposalHarness.sol";


abstract contract PWNUniswapV3LPIndividualProposalTest is Test {

    PWNUniswapV3LPIndividualProposalHarness proposalContract;
    PWNUniswapV3LPIndividualProposal.Proposal proposal;

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

    address uniswapV3Factory = makeAddr("uniswapV3Factory");
    address uniswapNFTPositionManager = makeAddr("uniswapNFTPositionManager");
    address feedRegistry = makeAddr("feedRegistry");
    address feed = makeAddr("feed");
    address weth = makeAddr("weth");
    address l2SequencerUptimeFeed = makeAddr("l2SequencerUptimeFeed");

    uint256 collateralId = 420;
    address token0 = makeAddr("token0");
    address token1 = makeAddr("token1");
    address token = makeAddr("token");
    uint24 fee = 3000;
    address pool = 0xb44E273AE4071AA4a0F2b05ee96f20BB6FfD568b;
    uint256 token0Value = 101572;
    uint256 token1Value = 331794706808;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNUniswapV3LPIndividualProposal.Proposal proposal);

    function setUp() virtual public {
        proposalContract = new PWNUniswapV3LPIndividualProposalHarness(hub, revokedNonce, config, utilizedCredit, interestModule, defaultModule, liquidationModule, uniswapV3Factory, uniswapNFTPositionManager, feedRegistry, address(0), weth);

        proposal = PWNUniswapV3LPIndividualProposal.Proposal({
            collateralId: collateralId,
            token0Denominator: true,
            creditAddress: token0,
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            loanToValue: 10000, // 100%
            interestAPR: 0,
            duration: 1 days,
            minCreditAmount: 1,
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

        vm.mockCall(address(uniswapNFTPositionManager), abi.encodeWithSignature("factory()"), abi.encode(uniswapV3Factory));

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN), abi.encode(true));

        vm.mockCall(revokedNonce, abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"), abi.encode(true));
    }


    function _proposalHash(PWNUniswapV3LPIndividualProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNUniswapV3LPIndividualProposal"),
                keccak256("1.5"),
                block.chainid,
                address(proposalContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint256 collateralId,bool token0Denominator,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 interestAPR,uint256 duration,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"),
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

}


/*----------------------------------------------------------*|
|*  # GET PROPOSAL HASH                                     *|
|*----------------------------------------------------------*/

contract PWNUniswapV3LPIndividualProposal_GetProposalHash_Test is PWNUniswapV3LPIndividualProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNUniswapV3LPIndividualProposal_MakeProposal_Test is PWNUniswapV3LPIndividualProposalTest {

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

contract PWNUniswapV3LPIndividualProposal_EncodeDecodeProposalData_Test is PWNUniswapV3LPIndividualProposalTest {

    function test_shouldEncodeDecodedProposalData() external {
        (
            PWNUniswapV3LPIndividualProposal.Proposal memory _proposal
        ) = proposalContract.decodeProposalData(proposalContract.encodeProposalData(proposal));

        assertEq(proposal.collateralId, _proposal.collateralId);
        assertEq(proposal.token0Denominator, _proposal.token0Denominator);
        assertEq(proposal.creditAddress, _proposal.creditAddress);
        assertEq(proposal.feedIntermediaryDenominations, _proposal.feedIntermediaryDenominations);
        assertEq(proposal.feedInvertFlags.length, _proposal.feedInvertFlags.length);
        assertEq(keccak256(abi.encode(proposal.feedInvertFlags)), keccak256(abi.encode(_proposal.feedInvertFlags)));
        assertEq(proposal.loanToValue, _proposal.loanToValue);
        assertEq(proposal.interestAPR, _proposal.interestAPR);
        assertEq(proposal.duration, _proposal.duration);
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
    }

}


/*----------------------------------------------------------*|
|*  # GET CREDIT AMOUNT                                     *|
|*----------------------------------------------------------*/

contract PWNUniswapV3LPIndividualProposal_GetCreditAmount_Test is PWNUniswapV3LPIndividualProposalTest {

    function setUp() virtual override public {
        super.setUp();

        _mockPosition(100_000, 200_000, 100e6, 0, 0);
        _mockPool(pool, 150_000);
    }


    function test_shouldReturnLPValueInToken0_whenCreditIsToken0() external {
        uint256 credAmount = proposalContract
            .getCreditAmount(token0, collateralId, true, new address[](0), new bool[](0), 10000);

        assertEq(credAmount, token0Value);
    }

    function test_shouldReturnLPValueInToken1_whenCreditIsToken1() external {
        uint256 credAmount = proposalContract
            .getCreditAmount(token1, collateralId, false, new address[](0), new bool[](0), 10000);

        assertEq(credAmount, token1Value);
    }

    function test_shouldConvertDenominationViaChainlink_whenCreditNotToken01() external {
        address credAddr = makeAddr("credAddr");
        address[] memory feedIntermediaryDenominations = new address[](0);
        bool[] memory feedInvertFlags = new bool[](1);
        feedInvertFlags[0] = false;

        _mockFeed(feed);
        _mockLastRoundData(feed, 300e6, 1);
        _mockFeedDecimals(feed, 6);
        _mockAssetDecimals(credAddr, 22);
        _mockAssetDecimals(token0, 6);

        uint256 credAmount = proposalContract
            .getCreditAmount(credAddr, collateralId, true, feedIntermediaryDenominations, feedInvertFlags, 10000);
        assertEq(credAmount, token0Value * 300e16);
    }

    function test_shouldCalculateLoanToValue() external {
        uint256 credAmount = proposalContract
            .getCreditAmount(token1, collateralId, false, new address[](0), new bool[](0), 7000);

        assertEq(credAmount, token1Value * 7 / 10);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNUniswapV3LPIndividualProposal_AcceptProposal_Test is PWNUniswapV3LPIndividualProposalTest {

    function setUp() virtual public override {
        super.setUp();

        _mockPosition(100_000, 200_000, 100e6, 0, 0);
        _mockPool(pool, 150_000);
    }


    function test_shouldFail_whenZeroMinCreditAmount() external {
        proposal.minCreditAmount = 0;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNUniswapV3LPIndividualProposal.MinCreditAmountNotSet.selector));
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function test_shouldFail_whenCreditAmountLessThanMinCreditAmount() external {
        proposal.minCreditAmount = token0Value + 1;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNUniswapV3LPIndividualProposal.InsufficientCreditAmount.selector,
                token0Value,
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

    function test_shouldCallLoanContractWithLoanTerms() external {
        proposal.isProposerLender = true;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.prank(loanContract);
        Terms memory terms = proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(terms.proposalHash, proposalHash);
        assertEq(terms.lender, proposal.proposer);
        assertEq(terms.borrower, acceptor);
        assertEq(terms.proposerSpecHash, proposal.proposerSpecHash);
        assertEq(uint8(terms.collateral.category), uint8(MultiToken.Category.ERC721));
        assertEq(terms.collateral.assetAddress, uniswapNFTPositionManager);
        assertEq(terms.collateral.id, proposal.collateralId);
        assertEq(terms.collateral.amount, 0);
        assertEq(terms.creditAddress, proposal.creditAddress);
        assertEq(terms.principal, token0Value); // with LTV = 100%
        assertEq(address(terms.interestModule), address(interestModule));
        assertEq(terms.interestModuleProposerData.length, 32);
        assertEq(keccak256(terms.interestModuleProposerData), keccak256(abi.encode(proposal.interestAPR)));
        assertEq(address(terms.defaultModule), address(defaultModule));
        assertEq(terms.defaultModuleProposerData.length, 32);
        assertEq(keccak256(terms.defaultModuleProposerData), keccak256(abi.encode(proposal.duration)));
        assertEq(address(terms.liquidationModule), address(liquidationModule));
        assertEq(terms.liquidationModuleProposerData.length, 0);

        proposal.isProposerLender = false;

        proposalData = proposalContract.encodeProposalData(proposal);
        proposalHash = _proposalHash(proposal);

        vm.prank(loanContract);
        terms = proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(terms.lender, acceptor);
        assertEq(terms.borrower, proposal.proposer);
    }

}


/*----------------------------------------------------------*|
|*  # ERC712 ENCODE PROPOSAL                                *|
|*----------------------------------------------------------*/

contract PWNUniswapV3LPIndividualProposal_Erc712EncodeProposal_Test is PWNUniswapV3LPIndividualProposalTest {

    function test_shouldERC712EncodeProposal() external {
        PWNUniswapV3LPIndividualProposal.ERC712Proposal memory proposalErc712 = PWNUniswapV3LPIndividualProposal.ERC712Proposal(
            proposal.collateralId,
            proposal.token0Denominator,
            proposal.creditAddress,
            keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            proposal.loanToValue,
            proposal.interestAPR,
            proposal.duration,
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
