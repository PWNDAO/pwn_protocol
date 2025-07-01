// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { console2 } from "forge-std/Test.sol";

import { MultiToken, IERC20, IERC721 } from "MultiToken/MultiToken.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    PWNUniswapV3LPIndividualProposal,
    INonfungiblePositionManager,
    IChainlinkAggregatorLike
} from "pwn/periphery/proposal/PWNUniswapV3LPIndividualProposal.sol";

import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";
import {
    PWNLoan,
    DeploymentTest
} from "test/DeploymentTest.t.sol";


interface IUSDT {
    function approve(address spender, uint256 amount) external;
}

contract PWNUniswapV3LPIndividualProposalForkTest is DeploymentTest {
    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 DAI  = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 UNI  = IERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    IERC20 PLUME = IERC20(0x4C1746A800D224393fE2470C70A35717eD4eA5F1);

    PWNLoan.LenderSpec lenderSpec;
    PWNLoan.BorrowerSpec borrowerSpec;
    PWNUniswapV3LPIndividualProposal.Proposal proposal;

    function setUp() public override virtual {
        vm.createSelectFork("mainnet");

        super.setUp();

        deal(lender, 10000 ether);
        deal(address(USDT), lender, 1_000_000e6, false);
        deal(address(DAI), lender, 1_000_000e6, false);

        vm.startPrank(lender);
        IUSDT(address(USDT)).approve(address(__d.loan), type(uint256).max);
        DAI.approve(address(__d.loan), type(uint256).max);
        vm.stopPrank();

        vm.prank(borrower);
        IERC721(__e.uniswapV3NFTPositionManager).setApprovalForAll(address(__d.loan), true);

        _registerFeed(address(USDC), ChainlinkDenominations.USD, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        _registerFeed(address(USDT), ChainlinkDenominations.USD, 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D);
        _registerFeed(address(UNI), ChainlinkDenominations.USD, 0x553303d460EE0afB37EdFf9bE42922D8FF63220e);
    }

    function _transferLPOwnership(uint256 tokenId) internal {
        address owner = IERC721(__e.uniswapV3NFTPositionManager).ownerOf(tokenId);
        vm.prank(owner);
        IERC721(__e.uniswapV3NFTPositionManager).transferFrom(owner, borrower, tokenId);
    }

    function _registerFeed(address base, address quote, address feed) internal {
        try __d.chainlinkFeedRegistry.getFeed(base, quote) returns (IChainlinkAggregatorLike) {
            return;
        } catch {
            vm.startPrank(__e.protocolTimelock);
            __d.chainlinkFeedRegistry.proposeFeed(base, quote, feed);
            __d.chainlinkFeedRegistry.confirmFeed(base, quote, feed);
            vm.stopPrank();
        }
    }

    function _test(uint256 tokenId, bool token0Denominator) internal {
        _test(tokenId, token0Denominator, "");
    }

    function _test(uint256 tokenId, bool token0Denominator, bytes memory err) internal {
        if (tokenId != 851566) _transferLPOwnership(tokenId); // use token id 851566 to test call for non-existent token

        proposal = PWNUniswapV3LPIndividualProposal.Proposal({
            collateralId: tokenId,
            token0Denominator: token0Denominator,
            creditAddress: address(USDT),
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            loanToValue: 7500,
            interestAPR: 0,
            duration: 1 days,
            minCreditAmount: 1,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: uint40(block.timestamp + 7 days),
            proposer: lender,
            proposerSpecHash: bytes32(0),
            isProposerLender: true,
            loanContract: address(__d.loan)
        });

        proposal.feedIntermediaryDenominations.push(ChainlinkDenominations.USD);
        proposal.feedInvertFlags.push(false);
        proposal.feedInvertFlags.push(true);

        bytes memory signature = _sign(lenderPK, __d.uniswapV3LPIndividualProposal.getProposalHash(proposal));
        bytes memory proposalData = __d.uniswapV3LPIndividualProposal.encodeProposalData(proposal);

        if (err.length > 0) { vm.expectRevert(err); }
        vm.prank(borrower);
        __d.loan.create({
            proposalSpec: PWNLoan.ProposalSpec({
                proposalContract: address(__d.uniswapV3LPIndividualProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        console2.log(USDT.balanceOf(borrower));
    }


    // Following tests are for sanity check and will start failling once the LP position is closed

    function test_shouldFail_whenInvalidId() external {
        // https://app.uniswap.org/positions/v3/ethereum/3
        // usdc/weth (closed)
        _test(3, true, abi.encodeWithSelector(PWNUniswapV3LPIndividualProposal.InsufficientCreditAmount.selector, 0, 1));
    }

    function test_sanity_PLUME_USDC() external {
        // https://app.uniswap.org/positions/v3/ethereum/951585
        _test(951585, false); // plume/usdc
    }

    function test_sanity_UNI_WETH_outOfRange() external {
        // https://app.uniswap.org/positions/v3/ethereum/1
        _test(1, true); // uni/weth
    }

}
