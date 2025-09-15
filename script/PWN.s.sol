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
    PWNStableProduct,
    PWNInstallmentsProduct
} from "pwn/Deployments.sol";

import { PWNCrowdsourceLenderVault } from "pwn/periphery/crowdsource/PWNCrowdsourceLenderVault.sol";


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
    bytes32 internal constant INSTALLMENTS_PRODUCT = keccak256("PWNInstallmentsProduct");

    // Others
    bytes32 internal constant CROWDSOURCE_LENDER_VAULT = keccak256("PWNCrowdsourceLenderVault");
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

        __d.products.installments = PWNInstallmentsProduct(
            _deploy(
                PWNContractDeployerSalt.INSTALLMENTS_PRODUCT,
                abi.encodePacked(
                    type(PWNInstallmentsProduct).creationCode,
                    abi.encode(address(__d.hub), address(__d.revokedNonce), address(__d.utilizedCredit), address(__d.chainlinkFeedRegistry), __e.chainlinkL2SequencerUptimeFeed, __e.weth)
                )
            )
        );

        console2.log("PWNLoan:", address(__d.loan));
        console2.log("PWNInstallmentsProduct:", address(__d.products.installments));

        address[] memory addrs = new address[](2);
        addrs[0] = address(__d.loan);
        addrs[1] = address(__d.products.installments);

        bytes32[] memory tags = new bytes32[](2);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.LOAN_PROPOSAL;

        // TODO on what contract this should be called?
        console2.logBytes(abi.encodeWithSignature("setTags(address[],bytes32[],bool)", addrs, tags, true));

        address[] memory feedIntermediaryDenominations = new address[](1);
        // USDC / USD feed + ETH / USD feed
        feedIntermediaryDenominations[0] = address(840); // USD representation in chainlink
        bool[] memory feedInvertFlags = new bool[](2);
        feedInvertFlags[0] = false;
        feedInvertFlags[1] = true;

        __d.crowdsourceLenderVault = PWNCrowdsourceLenderVault(
            _deploy(
                PWNContractDeployerSalt.CROWDSOURCE_LENDER_VAULT,
                abi.encodePacked(
                    type(PWNCrowdsourceLenderVault).creationCode,
                    // TODO Terms terms parameter
                    abi.encode(
                        address(__d.loan), 
                        address(__d.products.installments), 
                        address(__e.aave), 
                        "PWNInstallmentsProduct", 
                        "PWNInstallmentsProduct",
                        PWNCrowdsourceLenderVault.Terms({
                            collateralAddress: address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9),
                            creditAddress: address(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8),
                            feedIntermediaryDenominations: feedIntermediaryDenominations,
                            feedInvertFlags: feedInvertFlags,
                            loanToValue: 7500, // 75%
                            interestAPR: 1000, // 10%
                            postponement: 2592000, // 30 days in seconds
                            duration: 63072000, // 730 days (2 years) in seconds
                            minCreditAmount: 5000000000, // 5000 tokens (assuming 6 decimals)
                            expiration: block.timestamp + 10368000 // 120 days from now
                        })
                    )
                )
            )
        );

        console2.log("PWNCrowdsourceLenderVault:", address(__d.crowdsourceLenderVault));

        // TODO anything else to do here?

        vm.stopBroadcast();
    }

}
