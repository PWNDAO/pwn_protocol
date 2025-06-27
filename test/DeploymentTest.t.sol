// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Create2 } from "openzeppelin/utils/Create2.sol";

import {
    Deployments,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    PWNDurationDefaultModule,
    PWNStableInterestModule,
    PWNClaimLiquidationModule,
    PWNElasticChainlinkProposal,
    PWNElasticProposal,
    PWNSimpleProposal,
    PWNUniswapV3LPIndividualProposal,
    PWNUniswapV3LPSetProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry,
    IChainlinkFeedRegistryLike
} from "pwn/Deployments.sol";


abstract contract DeploymentTest is Deployments, Test {

    uint256 lenderPK = uint256(777);
    address lender = vm.addr(lenderPK);
    uint256 borrowerPK = uint256(888);
    address borrower = vm.addr(borrowerPK);

    function setUp() public virtual {
        _loadDeployedAddresses();

        vm.label(lender, "lender");
        vm.label(borrower, "borrower");
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }


    function _protocolNotDeployedOnSelectedChain() internal override {
        __e.protocolTimelock = makeAddr("protocolTimelock");
        __e.adminTimelock = makeAddr("adminTimelock");
        __e.daoSafe = makeAddr("daoSafe");

        // Deploy feed registry
        __d.chainlinkFeedRegistry = IChainlinkFeedRegistryLike(Create2.deploy({
            amount: 0,
            salt: keccak256("PWNChainlinkFeedRegistry"),
            bytecode: __cc.chainlinkFeedRegistry
        }));
        __d.chainlinkFeedRegistry.transferOwnership(__e.protocolTimelock);
        vm.prank(__e.protocolTimelock);
        __d.chainlinkFeedRegistry.acceptOwnership();

        // Deploy category registry
        vm.prank(__e.protocolTimelock);
        __d.categoryRegistry = new MultiTokenCategoryRegistry();

        // Deploy protocol
        __d.configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(__d.configSingleton),
            __e.adminTimelock,
            abi.encodeWithSignature("initialize(address,uint16,address)", __e.protocolTimelock, 0, __e.daoSafe)
        );
        __d.config = PWNConfig(address(proxy));

        vm.prank(__e.protocolTimelock);
        __d.hub = new PWNHub();

        __d.revokedNonce = new PWNRevokedNonce(address(__d.hub), PWNHubTags.NONCE_MANAGER);
        __d.utilizedCredit = new PWNUtilizedCredit(address(__d.hub), PWNHubTags.LOAN_PROPOSAL);

        __d.stableInterestModule = new PWNStableInterestModule(__d.hub);
        __d.durationDefaultModule = new PWNDurationDefaultModule(__d.hub);
        __d.claimLiquidationModule = new PWNClaimLiquidationModule();

        __d.loanToken = new PWNLOAN(address(__d.hub));
        __d.loan = new PWNLoan(
            address(__d.hub),
            address(__d.loanToken),
            address(__d.config),
            address(__d.categoryRegistry)
        );

        __d.simpleProposal = new PWNSimpleProposal(
            address(__d.hub),
            address(__d.revokedNonce),
            address(__d.config),
            address(__d.utilizedCredit),
            address(__d.stableInterestModule),
            address(__d.durationDefaultModule),
            address(__d.claimLiquidationModule)
        );
        __d.elasticChainlinkProposal = new PWNElasticChainlinkProposal(
            address(__d.hub),
            address(__d.revokedNonce),
            address(__d.config),
            address(__d.utilizedCredit),
            address(__d.stableInterestModule),
            address(__d.durationDefaultModule),
            address(__d.claimLiquidationModule),
            address(__d.chainlinkFeedRegistry),
            __e.chainlinkL2SequencerUptimeFeed,
            __e.weth
        );
        __d.elasticProposal = new PWNElasticProposal(
            address(__d.hub),
            address(__d.revokedNonce),
            address(__d.config),
            address(__d.utilizedCredit),
            address(__d.stableInterestModule),
            address(__d.durationDefaultModule),
            address(__d.claimLiquidationModule)
        );
        __d.uniswapV3LPIndividualProposal = new PWNUniswapV3LPIndividualProposal(
            address(__d.hub),
            address(__d.revokedNonce),
            address(__d.config),
            address(__d.utilizedCredit),
            address(__d.stableInterestModule),
            address(__d.durationDefaultModule),
            address(__d.claimLiquidationModule),
            __e.uniswapV3Factory,
            __e.uniswapV3NFTPositionManager,
            address(__d.chainlinkFeedRegistry),
            __e.chainlinkL2SequencerUptimeFeed,
            __e.weth
        );
        __d.uniswapV3LPSetProposal = new PWNUniswapV3LPSetProposal(
            address(__d.hub),
            address(__d.revokedNonce),
            address(__d.config),
            address(__d.utilizedCredit),
            address(__d.stableInterestModule),
            address(__d.durationDefaultModule),
            address(__d.claimLiquidationModule),
            __e.uniswapV3Factory,
            __e.uniswapV3NFTPositionManager,
            address(__d.chainlinkFeedRegistry),
            __e.chainlinkL2SequencerUptimeFeed,
            __e.weth
        );

        // Set hub tags
        address[] memory addrs = new address[](15);
        addrs[0] = address(__d.loan);
        addrs[1] = address(__d.loan);

        addrs[2] = address(__d.simpleProposal);
        addrs[3] = address(__d.simpleProposal);

        addrs[4] = address(__d.elasticChainlinkProposal);
        addrs[5] = address(__d.elasticChainlinkProposal);

        addrs[6] = address(__d.elasticProposal);
        addrs[7] = address(__d.elasticProposal);

        addrs[8] = address(__d.uniswapV3LPIndividualProposal);
        addrs[9] = address(__d.uniswapV3LPIndividualProposal);

        addrs[10] = address(__d.uniswapV3LPSetProposal);
        addrs[11] = address(__d.uniswapV3LPSetProposal);

        addrs[12] = address(__d.stableInterestModule);
        addrs[13] = address(__d.durationDefaultModule);
        addrs[14] = address(__d.claimLiquidationModule);

        bytes32[] memory tags = new bytes32[](15);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.NONCE_MANAGER;

        tags[2] = PWNHubTags.LOAN_PROPOSAL;
        tags[3] = PWNHubTags.NONCE_MANAGER;

        tags[4] = PWNHubTags.LOAN_PROPOSAL;
        tags[5] = PWNHubTags.NONCE_MANAGER;

        tags[6] = PWNHubTags.LOAN_PROPOSAL;
        tags[7] = PWNHubTags.NONCE_MANAGER;

        tags[8] = PWNHubTags.LOAN_PROPOSAL;
        tags[9] = PWNHubTags.NONCE_MANAGER;

        tags[10] = PWNHubTags.LOAN_PROPOSAL;
        tags[11] = PWNHubTags.NONCE_MANAGER;

        tags[12] = PWNHubTags.MODULE;
        tags[13] = PWNHubTags.MODULE;
        tags[14] = PWNHubTags.MODULE;

        vm.prank(__e.protocolTimelock);
        __d.hub.setTags(addrs, tags, true);
    }

}
