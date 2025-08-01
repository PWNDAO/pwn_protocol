// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import { IPWNProposalModule } from "pwn/core/loan/module/IPWNProposalModule.sol";
import { Permit, IPermit2Like } from "pwn/core/loan/Permit.sol";
import { IPWNProduct } from "pwn/core/product/IPWNProduct.sol";
import { IChainlinkAggregatorLike } from "pwn/periphery/lib/Chainlink.sol";

import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";
import {
    DeploymentTest,
    PWNLoan,
    PWNStableProduct
} from "test/DeploymentTest.t.sol";


contract PWNStableProductForkTest is DeploymentTest {

    bytes32 public constant PERMIT2_DOMAIN_SEPARATOR = 0x866a5aba21966af95d6c7ab78eb2b2fc913915c28be3b9aa07cc04ff903e3f28;
    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256("PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)");

    PWNLoan.ProposalSpec proposalSpec;
    PWNLoan.LenderSpec lenderSpec;
    PWNLoan.BorrowerSpec borrowerSpec;
    PWNStableProduct.Proposal proposal;
    PWNStableProduct.AcceptorValues values;
    Permit permit;

    function setUp() public override virtual {
        vm.createSelectFork("mainnet");

        super.setUp();

        proposal = PWNStableProduct.Proposal({
            collateralAddress: address(0),
            creditAddress: address(0),
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            acceptableLoanToValue: 8000, // 80%
            interestAPR: 0,
            duration: 1 days,
            liquidationLoanToValue: 9000, // 90%
            minCreditAmount: 1,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: block.timestamp + 7 days,
            proposerSpecHash: bytes32(0),
            isProposerLender: true,
            loanContract: address(__d.loan)
        });

        proposalSpec = PWNLoan.ProposalSpec({
            proposer: lender,
            product: IPWNProduct(__d.products.stable),
            proposalData: "",
            proposalInclusionProof: new bytes32[](0),
            signature: ""
        });

        permit.permit.nonce = 0;
        permit.permit.deadline = block.timestamp + 1 days;
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

    function _createLoan(uint256 creditAmount, uint256 ltv) private {
        _createLoan(creditAmount, ltv, "");
    }

    function _createLoan(uint256 creditAmount, uint256 ltv, bytes memory err) private {
        values.creditAmount = creditAmount;
        values.loanToValue = ltv;

        proposalSpec.proposalData = __d.products.stable.encodeProposalData(proposal, values);

        vm.prank(lender);
        __d.loan.makeProposalAcceptable(IPWNProposalModule(address(__d.products.stable)), proposalSpec.proposalData);

        if (err.length > 0) {
            vm.expectRevert(err);
        }
        vm.prank(borrower);
        __d.loan.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            permit: permit,
            extra: ""
        });
    }

    function _hashPermit(Permit memory _permit, address spender) internal pure returns (bytes32) {
        bytes32 tokenPermissionsHash = keccak256(
            abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, _permit.permit.permitted)
        );
        bytes32 typedDataHash = keccak256(
            abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissionsHash, spender, _permit.permit.nonce, _permit.permit.deadline)
        );
        return keccak256(abi.encodePacked(hex"1901", PERMIT2_DOMAIN_SEPARATOR, typedDataHash));
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

        vm.prank(borrower);
        WETH.approve(address(__e.permit2), type(uint256).max);
        vm.startPrank(lender);
        APE.approve(address(__e.permit2), type(uint256).max);
        IPermit2Like(__e.permit2).approve(address(APE), address(__d.loan), 1000 ether, uint48(block.timestamp + 1 days));
        vm.stopPrank();

        permit.permit.permitted.token = address(WETH);
        permit.permit.permitted.amount = 1000 ether;
        bytes32 digest = _hashPermit(permit, address(__d.loan));
        permit.signature = _sign(borrowerPK, digest);

        _createLoan(500e18, 6000);

        (, int256 apePrice,,,) = IChainlinkAggregatorLike(APE_ETH_Feed).latestRoundData();
        uint256 coll = 500 * uint256(apePrice) * 10 / 6;

        assertApproxEqRel(WETH.balanceOf(address(__d.loan)), coll, 0.0001 ether); // 0.01% tolerance
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

        vm.prank(borrower);
        WETH.approve(address(__e.permit2), type(uint256).max);

        // USDT doesn't return bool and IERC20 interface call fails
        vm.startPrank(lender);
        (bool success, ) = address(USDT).call(abi.encodeWithSignature("approve(address,uint256)", address(__e.permit2), type(uint256).max));
        require(success);
        IPermit2Like(__e.permit2).approve(address(USDT), address(__d.loan), 1000e6, uint48(block.timestamp + 1 days));
        vm.stopPrank();

        permit.permit.permitted.token = address(WETH);
        permit.permit.permitted.amount = 1000 ether;
        bytes32 digest = _hashPermit(permit, address(__d.loan));
        permit.signature = _sign(borrowerPK, digest);

        _createLoan(500e6, 3000);

        (, int256 usdtPrice,,,) = IChainlinkAggregatorLike(USDT_USD_Feed).latestRoundData();
        (, int256 ethPrice,,,) = IChainlinkAggregatorLike(ETH_USD_Feed).latestRoundData();
        uint256 coll = 500e18 * uint256(usdtPrice) / uint256(ethPrice) * 10 / 3;

        assertApproxEqRel(WETH.balanceOf(address(__d.loan)), coll, 0.0001 ether); // 0.01% tolerance
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

        vm.prank(borrower);
        WETH.approve(address(__e.permit2), type(uint256).max);
        vm.startPrank(lender);
        ARB.approve(address(__e.permit2), type(uint256).max);
        IPermit2Like(__e.permit2).approve(address(ARB), address(__d.loan), 1000 ether, uint48(block.timestamp + 1 days));
        vm.stopPrank();

        permit.permit.permitted.token = address(WETH);
        permit.permit.permitted.amount = 1000 ether;
        bytes32 digest = _hashPermit(permit, address(__d.loan));
        permit.signature = _sign(borrowerPK, digest);

        _createLoan(500e18, 8000);

        (, int256 arbPrice,,,) = IChainlinkAggregatorLike(ARB_USD_Feed).latestRoundData();
        (, int256 ethPrice,,,) = IChainlinkAggregatorLike(ETH_USD_Feed).latestRoundData();
        uint256 coll = 500e18 * uint256(arbPrice) / uint256(ethPrice) * 10 / 8;

        assertApproxEqRel(WETH.balanceOf(address(__d.loan)), coll, 0.0001 ether); // 0.01% tolerance
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

        vm.prank(borrower);
        ARB.approve(address(__e.permit2), type(uint256).max);

        // USDT doesn't return bool and IERC20 interface call fails
        vm.startPrank(lender);
        (bool success, ) = address(USDT).call(abi.encodeWithSignature("approve(address,uint256)", address(__e.permit2), type(uint256).max));
        require(success);
        IPermit2Like(__e.permit2).approve(address(USDT), address(__d.loan), 1000e6, uint48(block.timestamp + 1 days));
        vm.stopPrank();

        permit.permit.permitted.token = address(ARB);
        permit.permit.permitted.amount = 3000 ether;
        bytes32 digest = _hashPermit(permit, address(__d.loan));
        permit.signature = _sign(borrowerPK, digest);

        _createLoan(500e6, 5500);

        (, int256 usdtPrice,,,) = IChainlinkAggregatorLike(USDT_USD_Feed).latestRoundData();
        (, int256 arbPrice,,,) = IChainlinkAggregatorLike(ARB_USD_Feed).latestRoundData();
        uint256 coll = 500e18 * uint256(usdtPrice) / uint256(arbPrice) * 100 / 55;

        assertApproxEqRel(ARB.balanceOf(address(__d.loan)), coll, 0.0001 ether); // 0.01% tolerance
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

        vm.prank(borrower);
        WBTC.approve(address(__e.permit2), type(uint256).max);
        vm.startPrank(lender);
        WETH.approve(address(__e.permit2), type(uint256).max);
        IPermit2Like(__e.permit2).approve(address(WETH), address(__d.loan), 1000 ether, uint48(block.timestamp + 1 days));
        vm.stopPrank();

        permit.permit.permitted.token = address(WBTC);
        permit.permit.permitted.amount = 1000 ether;
        bytes32 digest = _hashPermit(permit, address(__d.loan));
        permit.signature = _sign(borrowerPK, digest);

        _createLoan(500e18, 7000);

        (, int256 wbtcPrice,,,) = IChainlinkAggregatorLike(WBTC_BTC_Feed).latestRoundData();
        (, int256 btcPrice,,,) = IChainlinkAggregatorLike(BTC_ETH_Feed).latestRoundData();
        uint256 coll = 500e8 * 1e18 / uint256(btcPrice) * 1e8 / uint256(wbtcPrice) * 10 / 7;

        assertApproxEqRel(WBTC.balanceOf(address(__d.loan)), coll, 0.0001 ether); // 0.01% tolerance
    }

}
