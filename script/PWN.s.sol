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
    PWNInstallmentsProduct,
    IAaveLike
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

        // !!! TODO LOADING ADDRESSES FROM JSON DOES NOT WORK SOMEHOW, SO I AM JUST HARDCODING THE ADDRESSES HERE !!!

        // __d.loan = PWNLoan(0x7f53449251EF28991C99EA25698B37BC13b173B8);
        __e.aave = IAaveLike(address(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951));
        __d.hub = PWNHub(0x37807A2F031b3B44081F4b21500E5D70EbaDAdd5);
        __d.revokedNonce = PWNRevokedNonce(0x972204fF33348ee6889B2d0A3967dB67d7b08e4c);
        __d.utilizedCredit = PWNUtilizedCredit(0x8E6F44DEa3c11d69C63655BDEcbA25Fa986BCE9D);
        __d.chainlinkFeedRegistry = IChainlinkFeedRegistryLike(0x8D5e90706E52a52853dA9A14fA1c63889a412851);
        __e.chainlinkL2SequencerUptimeFeed = address(0x0000000000000000000000000000000000000000);
        __e.weth = address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9);
        __d.products.installments = PWNInstallmentsProduct(0x68669e7ec29070e3dfa684cb4893282Cd4C9E608);


        __d.loanToken = PWNLOAN(0x4440C069272cC34b80C7B11bEE657D0349Ba9C23);
        __d.config = PWNConfig(0xd52a2898d61636bB3eEF0d145f05352FF543bdCC);
        __d.categoryRegistry = MultiTokenCategoryRegistry(0xbB2168d5546A94AE2DA9254e63D88F7f137B2534);

        __d.loan = PWNLoan(
            _deploy(
                PWNContractDeployerSalt.LOAN,
                abi.encodePacked(
                    type(PWNLoan).creationCode,
                    abi.encode(
                        address(__d.loanToken), 
                        address(__d.config), 
                        address(__d.categoryRegistry)
                    )
                )
            )
        );

        // __d.products.installments = PWNInstallmentsProduct(
        //     _deploy(
        //         PWNContractDeployerSalt.INSTALLMENTS_PRODUCT,
        //         abi.encodePacked(
        //             type(PWNInstallmentsProduct).creationCode,
        //             abi.encode(
        //                 address(__d.hub), 
        //                 address(__d.revokedNonce), 
        //                 address(__d.utilizedCredit), 
        //                 address(__d.chainlinkFeedRegistry), 
        //                 __e.chainlinkL2SequencerUptimeFeed, 
        //                 __e.weth
        //             )
        //         )
        //     )
        // );

        console2.log("PWNLoan:", address(__d.loan));
        // console2.log("PWNInstallmentsProduct:", address(__d.products.installments));
        // console2.log("Aave:", address(__e.aave));

        // address[] memory addrs = new address[](2);
        // addrs[0] = address(__d.loan);
        // addrs[1] = address(__d.products.installments);

        address[] memory addrs = new address[](1);
        addrs[0] = address(__d.loan);

        // bytes32[] memory tags = new bytes32[](2);
        // tags[0] = PWNHubTags.ACTIVE_LOAN;
        // tags[1] = PWNHubTags.LOAN_PROPOSAL;

        bytes32[] memory tags = new bytes32[](1);
        tags[0] = PWNHubTags.ACTIVE_LOAN;

        // // TODO on what contract this should be called?
        console2.logBytes(abi.encodeWithSignature("setTags(address[],bytes32[],bool)", addrs, tags, true));

        address[] memory feedIntermediaryDenominations = new address[](1);
        feedIntermediaryDenominations[0] = address(0x0000000000000000000000000000000000000348);
        // USDC / USD feed + ETH / USD feed
        // feedIntermediaryDenominations[0] = address(840); // USD representation in chainlink
        // LINK / ETH feed
        // feedIntermediaryDenominations[0] = address(0x42585eD362B3f1BCa95c640FdFf35Ef899212734); 
        // EUR / ETH feed
        // feedIntermediaryDenominations[0] = address(0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910);
        bool[] memory feedInvertFlags = new bool[](2);
        feedInvertFlags[0] = false;
        feedInvertFlags[1] = true;
        // feedInvertFlags[0] = false;
        // feedInvertFlags[1] = true;


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
                        // USDC CREDIT on Sepolia
                        // PWNCrowdsourceLenderVault.Terms({
                        //     collateralAddress: address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9),
                        //     creditAddress: address(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8),
                        //     feedIntermediaryDenominations: feedIntermediaryDenominations,
                        //     feedInvertFlags: feedInvertFlags,
                        //     loanToValue: 7500, // 75%
                        //     interestAPR: 1000, // 10%
                        //     postponement: 2592000, // 30 days in seconds
                        //     duration: 63072000, // 730 days (2 years) in seconds
                        //     minCreditAmount: 5000000000, // 5000 tokens (assuming 6 decimals)
                        //     expiration: block.timestamp + 10368000 // 120 days from now
                        // })
                        // LINK CREDIT on Sepolia
                        // PWNCrowdsourceLenderVault.Terms({
                        //     collateralAddress: address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9),
                        //     creditAddress: address(0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5),
                        //     feedIntermediaryDenominations: feedIntermediaryDenominations,
                        //     feedInvertFlags: feedInvertFlags,
                        //     loanToValue: 7500, // 75%
                        //     interestAPR: 1000, // 10%
                        //     postponement: 2592000, // 30 days in seconds
                        //     duration: 63072000, // 730 days (2 years) in seconds
                        //     minCreditAmount: 500000000000000000000,
                        //     expiration: block.timestamp + 10368000 // 120 days from now
                        // })
                        // EURS CREDIT on Sepolia
                        PWNCrowdsourceLenderVault.Terms({
                            collateralAddress: address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9),
                            creditAddress: address(0x6d906e526a4e2Ca02097BA9d0caA3c382F52278E),
                            feedIntermediaryDenominations: feedIntermediaryDenominations,
                            feedInvertFlags: feedInvertFlags,
                            loanToValue: 7500, // 75%
                            interestAPR: 1000, // 10%
                            // postponement: 2592000, // 30 days in seconds
                            postponement: 1200, // 20 minutes in seconds
                            // duration: 63072000, // 730 days (2 years) in seconds
                            duration: 7200, // 2 hours in seconds
                            // minCreditAmount: 50000, // 500 EURS
                            minCreditAmount: 10000, // 100 EURS
                            // expiration: block.timestamp + 10368000 // 120 days from now
                            expiration: block.timestamp + 36000 // 10 hours from now
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
