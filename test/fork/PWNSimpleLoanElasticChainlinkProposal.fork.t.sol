// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IERC20 } from "MultiToken/MultiToken.sol";

import { IChainlinkAggregatorLike } from "src/periphery/proposal/PWNElasticChainlinkProposal.sol";

import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";
import {
    DeploymentTest,
    PWNLoan,
    PWNElasticChainlinkProposal
} from "test/DeploymentTest.t.sol";


contract PWNElasticChainlinkProposalForkTest is DeploymentTest {

    PWNLoan.LenderSpec lenderSpec;
    PWNLoan.BorrowerSpec borrowerSpec;
    PWNElasticChainlinkProposal.Proposal proposal;
    PWNElasticChainlinkProposal.AcceptorValues values;

    function setUp() public override virtual {
        vm.createSelectFork("mainnet");

        super.setUp();

        proposal = PWNElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(0),
            collateralId: 0,
            creditAddress: address(0),
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            loanToValue: 8000,
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
    }

    function _registerFeed(address base, address quote, address feed) private {
        try __d.chainlinkFeedRegistry.getFeed(base, quote) returns (IChainlinkAggregatorLike) {
            return;
        } catch {
            vm.startPrank(__e.protocolTimelock);
            __d.chainlinkFeedRegistry.proposeFeed(base, quote, feed);
            __d.chainlinkFeedRegistry.confirmFeed(base, quote, feed);
            vm.stopPrank();
        }
    }

    function _createLoan() private {
        bytes memory signature = _sign(lenderPK, __d.elasticChainlinkProposal.getProposalHash(proposal));
        bytes memory proposalData = __d.elasticChainlinkProposal.encodeProposalData(proposal, values);

        vm.prank(borrower);
        __d.loan.create({
            proposalSpec: PWNLoan.ProposalSpec({
                proposalContract: address(__d.elasticChainlinkProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }


    function test_oneFeed_APE_WETH() external {
        IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 APE = IERC20(0x4d224452801ACEd8B2F0aebE155379bb5D594381);
        address APE_ETH_Feed = 0xc7de7f4d4C9c991fF62a07D18b3E31e349833A18;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(WETH), borrower, 1e18, false);
        deal(address(APE), lender, 1000e18, false);

        // Register APE/ETH feed
        _registerFeed(address(APE), ChainlinkDenominations.ETH, APE_ETH_Feed);

        proposal.collateralAddress = address(WETH);
        proposal.creditAddress = address(APE);
        proposal.feedInvertFlags.push(false);
        proposal.availableCreditLimit = 1000 ether;

        values.creditAmount = 300 ether;

        vm.prank(borrower);
        WETH.approve(address(__d.loan), type(uint256).max);
        vm.prank(lender);
        APE.approve(address(__d.loan), type(uint256).max);

        _createLoan();

        (, int256 price,,,) = IChainlinkAggregatorLike(APE_ETH_Feed).latestRoundData();
        uint256 expectedCollAmount = 300 * uint256(price) / 8 * 10;

        assertEq(APE.balanceOf(lender), 700e18);
        assertEq(APE.balanceOf(borrower), 300e18);
        assertApproxEqAbs(WETH.balanceOf(borrower), 1e18 - expectedCollAmount, 0.00001e18);
        assertApproxEqAbs(WETH.balanceOf(address(__d.loan)), expectedCollAmount, 0.00001e18);
    }

    function test_twoFeeds_USDT_WETH() external {
        IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        address ETH_USD_Feed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        address USDT_USD_Feed = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(WETH), borrower, 1e18, false);
        deal(address(USDT), lender, 1000e6, false);

        // Register USDT/USD & ETH/USD feed
        _registerFeed(address(USDT), ChainlinkDenominations.USD, USDT_USD_Feed);
        _registerFeed(ChainlinkDenominations.ETH, ChainlinkDenominations.USD, ETH_USD_Feed);

        proposal.collateralAddress = address(WETH);
        proposal.creditAddress = address(USDT);
        proposal.feedIntermediaryDenominations.push(ChainlinkDenominations.USD);
        proposal.feedInvertFlags.push(false);
        proposal.feedInvertFlags.push(true);
        proposal.availableCreditLimit = 1000e6;

        values.creditAmount = 500e6;

        vm.prank(borrower);
        WETH.approve(address(__d.loan), type(uint256).max);

        // USDT doesn't return bool and IERC20 interface call fails
        vm.prank(lender);
        (bool success, ) = address(USDT).call(abi.encodeWithSignature("approve(address,uint256)", address(__d.loan), type(uint256).max));
        require(success);

        _createLoan();

        (, int256 usdtPrice,,,) = IChainlinkAggregatorLike(USDT_USD_Feed).latestRoundData();
        (, int256 ethPrice,,,) = IChainlinkAggregatorLike(ETH_USD_Feed).latestRoundData();
        uint256 expectedCollAmount = 500e18 * uint256(usdtPrice) / uint256(ethPrice) / 8 * 10;

        assertEq(USDT.balanceOf(lender), 500e6);
        assertEq(USDT.balanceOf(borrower), 500e6);
        assertApproxEqAbs(WETH.balanceOf(borrower), 1e18 - expectedCollAmount, 0.00001e18);
        assertApproxEqAbs(WETH.balanceOf(address(__d.loan)), expectedCollAmount, 0.00001e18);
    }

    function test_twoFeeds_ARB_WETH() external {
        IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 ARB = IERC20(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1);
        address ETH_USD_Feed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        address ARB_USD_Feed = 0x31697852a68433DbCc2Ff612c516d69E3D9bd08F;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(WETH), borrower, 1e18, false);
        deal(address(ARB), lender, 1000e18, false);

        // Register ARB/USD & ETH/USD feed
        _registerFeed(address(ARB), ChainlinkDenominations.USD, ARB_USD_Feed);
        _registerFeed(ChainlinkDenominations.ETH, ChainlinkDenominations.USD, ETH_USD_Feed);

        proposal.collateralAddress = address(WETH);
        proposal.creditAddress = address(ARB);
        proposal.feedIntermediaryDenominations.push(ChainlinkDenominations.USD);
        proposal.feedInvertFlags.push(false);
        proposal.feedInvertFlags.push(true);
        proposal.availableCreditLimit = 1000 ether;

        values.creditAmount = 500 ether;

        vm.prank(borrower);
        WETH.approve(address(__d.loan), type(uint256).max);
        vm.prank(lender);
        ARB.approve(address(__d.loan), type(uint256).max);

        _createLoan();

        (, int256 arbPrice,,,) = IChainlinkAggregatorLike(ARB_USD_Feed).latestRoundData();
        (, int256 ethPrice,,,) = IChainlinkAggregatorLike(ETH_USD_Feed).latestRoundData();
        uint256 expectedCollAmount = 500e18 * uint256(arbPrice) / uint256(ethPrice) / 8 * 10;

        assertEq(ARB.balanceOf(lender), 500e18);
        assertEq(ARB.balanceOf(borrower), 500e18);
        assertApproxEqAbs(WETH.balanceOf(borrower), 1e18 - expectedCollAmount, 0.00001e18);
        assertApproxEqAbs(WETH.balanceOf(address(__d.loan)), expectedCollAmount, 0.00001e18);
    }

    function test_twoFeeds_USDT_ARB() external {
        IERC20 ARB = IERC20(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1);
        IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        address ARB_USD_Feed = 0x31697852a68433DbCc2Ff612c516d69E3D9bd08F;
        address USDT_USD_Feed = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(ARB), borrower, 3000e18, false);
        deal(address(USDT), lender, 1000e6, false);

        // Register ARB/USD & ETH/USD feed
        _registerFeed(address(ARB), ChainlinkDenominations.USD, ARB_USD_Feed);
        _registerFeed(address(USDT), ChainlinkDenominations.USD, USDT_USD_Feed);

        proposal.collateralAddress = address(ARB);
        proposal.creditAddress = address(USDT);
        proposal.feedIntermediaryDenominations.push(ChainlinkDenominations.USD);
        proposal.feedInvertFlags.push(false);
        proposal.feedInvertFlags.push(true);
        proposal.availableCreditLimit = 1000e6;

        values.creditAmount = 500e6;

        vm.prank(borrower);
        ARB.approve(address(__d.loan), type(uint256).max);

        // USDT doesn't return bool and IERC20 interface call fails
        vm.prank(lender);
        (bool success, ) = address(USDT).call(abi.encodeWithSignature("approve(address,uint256)", address(__d.loan), type(uint256).max));
        require(success);

        _createLoan();

        (, int256 usdtPrice,,,) = IChainlinkAggregatorLike(USDT_USD_Feed).latestRoundData();
        (, int256 arbPrice,,,) = IChainlinkAggregatorLike(ARB_USD_Feed).latestRoundData();
        uint256 expectedCollAmount = 500e18 * uint256(usdtPrice) / uint256(arbPrice) / 8 * 10;

        assertEq(USDT.balanceOf(lender), 500e6);
        assertEq(USDT.balanceOf(borrower), 500e6);
        assertApproxEqAbs(ARB.balanceOf(borrower), 3000e18 - expectedCollAmount, 0.00001e18);
        assertApproxEqAbs(ARB.balanceOf(address(__d.loan)), expectedCollAmount, 0.00001e18);
    }

    function test_twoFeeds_WETH_WBTC() external {
        IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        address WBTC_BTC_Feed = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
        address BTC_ETH_Feed = 0xdeb288F737066589598e9214E782fa5A8eD689e8;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(WBTC), borrower, 50e8, false);
        deal(address(WETH), lender, 1000e18, false);

        // Register WBTC/BTC, & BTC/ETH feed
        _registerFeed(address(WBTC), ChainlinkDenominations.BTC, WBTC_BTC_Feed);
        _registerFeed(ChainlinkDenominations.BTC, ChainlinkDenominations.ETH, BTC_ETH_Feed);

        proposal.collateralAddress = address(WBTC);
        proposal.creditAddress = address(WETH);
        proposal.feedIntermediaryDenominations.push(ChainlinkDenominations.BTC);
        proposal.feedInvertFlags.push(true);
        proposal.feedInvertFlags.push(true);
        proposal.availableCreditLimit = 1000 ether;

        values.creditAmount = 500 ether;

        vm.prank(borrower);
        WBTC.approve(address(__d.loan), type(uint256).max);
        vm.prank(lender);
        WETH.approve(address(__d.loan), type(uint256).max);

        _createLoan();

        (, int256 wbtcPrice,,,) = IChainlinkAggregatorLike(WBTC_BTC_Feed).latestRoundData();
        (, int256 btcPrice,,,) = IChainlinkAggregatorLike(BTC_ETH_Feed).latestRoundData();
        uint256 expectedCollAmount = 500e8 * 1e18 / uint256(btcPrice) * 1e8 / uint256(wbtcPrice) / 8 * 10;

        assertEq(WETH.balanceOf(lender), 500e18);
        assertEq(WETH.balanceOf(borrower), 500e18);
        assertApproxEqAbs(WBTC.balanceOf(borrower), 50e8 - expectedCollAmount, 0.00001e8);
        assertApproxEqAbs(WBTC.balanceOf(address(__d.loan)), expectedCollAmount, 0.00001e8);
    }

}
