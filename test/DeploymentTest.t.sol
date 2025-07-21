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
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry,
    IChainlinkAggregatorLike,
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

        __d.loanToken = new PWNLOAN(address(__d.hub));
        __d.loan = new PWNLoan(
            address(__d.hub),
            address(__d.loanToken),
            address(__d.config),
            address(__d.categoryRegistry)
        );

        // todo: deploy products

        // Set hub tags
        address[] memory addrs = new address[](1);
        addrs[0] = address(__d.loan);

        bytes32[] memory tags = new bytes32[](1);
        tags[0] = PWNHubTags.ACTIVE_LOAN;

        vm.prank(__e.protocolTimelock);
        __d.hub.setTags(addrs, tags, true);
    }

}
