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
    PWNLOAN,
    PWNStableProduct,
    PWNFixedProduct,
    PWNUniswapV3IndividualProduct,
    PWNUniswapV3SetProduct,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    PWNRefinanceBorrowerCreateHook,
    PWN4626VaultLenderHook,
    PWNAaveLenderHook,
    PWNCompoundLenderHook,
    PWNDirectLenderRepaymentHook
} from "pwn/Deployments.sol";
import { INonfungiblePositionManager } from "pwn/periphery/lib/UniswapV3.sol";


abstract contract DeploymentTest is Deployments, Test {

    uint256 lenderPK;
    address lender;
    uint256 borrowerPK;
    address borrower;

    function setUp() public virtual {
        _loadDeployedAddresses();

        (lender, lenderPK) = makeAddrAndKey("lender");
        (borrower, borrowerPK) = makeAddrAndKey("borrower");

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

        __d.loanToken = new PWNLOAN(address(__d.hub));
        __d.loan = new PWNLoan(
            address(__d.hub),
            address(__d.loanToken),
            address(__d.config),
            address(__d.categoryRegistry)
        );

        // Products
        __d.products.stable = new PWNStableProduct(
            __d.hub,
            __d.revokedNonce,
            __d.utilizedCredit,
            __d.chainlinkFeedRegistry,
            IChainlinkAggregatorLike(__e.chainlinkL2SequencerUptimeFeed),
            __e.weth
        );
        __d.products._fixed = new PWNFixedProduct(
            __d.hub,
            __d.revokedNonce,
            __d.utilizedCredit,
            __d.chainlinkFeedRegistry,
            IChainlinkAggregatorLike(__e.chainlinkL2SequencerUptimeFeed),
            __e.weth
        );
        __d.products.uniswapV3Individual = new PWNUniswapV3IndividualProduct(
            __d.hub,
            __d.revokedNonce,
            __e.uniswapV3Factory,
            INonfungiblePositionManager(__e.uniswapV3NFTPositionManager),
            __d.chainlinkFeedRegistry,
            IChainlinkAggregatorLike(__e.chainlinkL2SequencerUptimeFeed),
            __e.weth
        );
        __d.products.uniswapV3Set = new PWNUniswapV3SetProduct(
            __d.hub,
            __d.revokedNonce,
            __d.utilizedCredit,
            __e.uniswapV3Factory,
            INonfungiblePositionManager(__e.uniswapV3NFTPositionManager),
            __d.chainlinkFeedRegistry,
            IChainlinkAggregatorLike(__e.chainlinkL2SequencerUptimeFeed),
            __e.weth
        );

        // Hooks
        __d.hooks.refinanceBorrowerCreate = new PWNRefinanceBorrowerCreateHook(__d.hub);
        __d.hooks.vaultLender = new PWN4626VaultLenderHook(__d.hub);
        __d.hooks.aaveLender = new PWNAaveLenderHook(__d.hub, __e.aave);
        __d.hooks.compoundLender = new PWNCompoundLenderHook(__d.hub);
        __d.hooks.directLenderRepayment = new PWNDirectLenderRepaymentHook();

        // Set hub tags
        address[] memory addrs = new address[](13);
        addrs[0] = address(__d.loan);

        addrs[1] = address(__d.products.stable);
        addrs[2] = address(__d.products._fixed);
        addrs[3] = address(__d.products.uniswapV3Individual);
        addrs[4] = address(__d.products.uniswapV3Set);

        addrs[5] = address(__d.products.stable);
        addrs[6] = address(__d.products._fixed);
        addrs[7] = address(__d.products.uniswapV3Set);

        addrs[8] = address(__d.hooks.refinanceBorrowerCreate);
        addrs[9] = address(__d.hooks.vaultLender);
        addrs[10] = address(__d.hooks.aaveLender);
        addrs[11] = address(__d.hooks.compoundLender);
        addrs[12] = address(__d.hooks.directLenderRepayment);

        bytes32[] memory tags = new bytes32[](13);
        tags[0] = PWNHubTags.ACTIVE_LOAN;

        tags[1] = PWNHubTags.NONCE_MANAGER;
        tags[2] = PWNHubTags.NONCE_MANAGER;
        tags[3] = PWNHubTags.NONCE_MANAGER;
        tags[4] = PWNHubTags.NONCE_MANAGER;

        tags[5] = PWNHubTags.LOAN_PROPOSAL;
        tags[6] = PWNHubTags.LOAN_PROPOSAL;
        tags[7] = PWNHubTags.LOAN_PROPOSAL;

        tags[8] = PWNHubTags.HOOK;
        tags[9] = PWNHubTags.HOOK;
        tags[10] = PWNHubTags.HOOK;
        tags[11] = PWNHubTags.HOOK;
        tags[12] = PWNHubTags.HOOK;

        vm.prank(__e.protocolTimelock);
        __d.hub.setTags(addrs, tags, true);
    }

}
