// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Script, console2 } from "forge-std/Script.sol";

import { ITransparentUpgradeableProxy } from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { GnosisSafeLike, GnosisSafeUtils } from "./lib/GnosisSafeUtils.sol";
import { TimelockController, TimelockUtils } from "./lib/TimelockUtils.sol";

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
    IChainlinkFeedRegistryLike,
    PWNStableProduct
} from "pwn/Deployments.sol";


library PWNContractDeployerSalt {

    // Singletons
    bytes32 internal constant CONFIG = keccak256("PWNConfig");
    bytes32 internal constant CONFIG_PROXY = keccak256("PWNConfigProxy");
    bytes32 internal constant HUB = keccak256("PWNHub");
    bytes32 internal constant LOAN_TOKEN = keccak256("PWNLOAN");
    bytes32 internal constant REVOKED_NONCE = keccak256("PWNRevokedNonce");
    bytes32 internal constant UTILIZED_CREDIT = keccak256("PWNUtilizedCredit");
    bytes32 internal constant CHAINLINK_FEED_REGISTRY = keccak256("PWNChainlinkFeedRegistry");

    // Loan types
    bytes32 internal constant LOAN = keccak256("PWNLoan");

    // Proposal types
    bytes32 internal constant STABLE_PRODUCT = keccak256("PWNStableProduct");
    bytes32 internal constant FIXED_PRODUCT = keccak256("PWNFixedProduct");
    bytes32 internal constant UNISWAP_V3_INDIVIDUAL_PRODUCT = keccak256("PWNUniswapV3IndividualProduct");
    bytes32 internal constant UNISWAP_V3_SET_PRODUCT = keccak256("PWNUniswapV3SetProduct");

}

using GnosisSafeUtils for GnosisSafeLike;
using TimelockUtils for TimelockController;

contract Deploy is Deployments, Script {

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments/latest.json");
    }

    function _deployAndTransferOwnership(
        bytes32 salt,
        address owner,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(__e.deployerSafe).execTransaction({
            to: address(__e.deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deployAndTransferOwnership.selector, salt, owner, bytecode
            )
        });
        require(success, "Deploy failed");
        return __e.deployer.computeAddress(salt, keccak256(bytecode));
    }

    function _deploy(
        bytes32 salt,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(__e.deployerSafe).execTransaction({
            to: address(__e.deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deploy.selector, salt, bytecode
            )
        });
        require(success, "Deploy failed");
        return __e.deployer.computeAddress(salt, keccak256(bytecode));
    }


/**
forge script script/PWN.s.sol:Deploy --sig "deploy()" \
--rpc-url $RPC_URL --private-key $PRIVATE_KEY \
--broadcast --verify
*/
    function deploy() external {
        _loadDeployedAddresses();
        vm.startBroadcast();

        __d.loan = PWNLoan(
            _deploy(
                PWNContractDeployerSalt.LOAN,
                abi.encodePacked(
                    type(PWNLoan).creationCode,
                    abi.encode(address(__d.loanToken), address(__d.config), address(__d.categoryRegistry))
                )
            )
        );

        __d.products.stable = PWNStableProduct(
            _deploy(
                PWNContractDeployerSalt.STABLE_PRODUCT,
                abi.encodePacked(
                    type(PWNStableProduct).creationCode,
                    abi.encode(address(__d.hub), address(__d.revokedNonce), address(__d.utilizedCredit), address(__d.chainlinkFeedRegistry), __e.chainlinkL2SequencerUptimeFeed, __e.weth)
                )
            )
        );

        console2.log("PWNLoan:", address(__d.loan));
        console2.log("PWNStableProduct:", address(__d.products.stable));

        address[] memory addrs = new address[](3);
        addrs[0] = address(__d.loan);
        addrs[1] = address(__d.products.stable);
        addrs[2] = address(__d.products.stable);

        bytes32[] memory tags = new bytes32[](3);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.LOAN_PROPOSAL;
        tags[2] = PWNHubTags.NONCE_MANAGER;

        console2.logBytes(abi.encodeWithSignature("setTags(address[],bytes32[],bool)", addrs, tags, true));

        vm.stopBroadcast();
    }

}
