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

        // !!! IMPORTANT: LOADING ADDRESSES FROM JSON DOES NOT WORK SOMEHOW, SO I AM JUST HARDCODING THE ADDRESSES HERE !!!

        __d.loanToken = PWNLOAN(0x4440C069272cC34b80C7B11bEE657D0349Ba9C23);
        __d.config = PWNConfig(0xd52a2898d61636bB3eEF0d145f05352FF543bdCC);
        __d.categoryRegistry = MultiTokenCategoryRegistry(0xbB2168d5546A94AE2DA9254e63D88F7f137B2534);

        // __d.loan = PWNLoan(
        //     _deploy(
        //         PWNContractDeployerSalt.LOAN,
        //         abi.encodePacked(
        //             type(PWNLoan).creationCode,
        //             abi.encode(
        //                 address(__d.loanToken), 
        //                 address(__d.config), 
        //                 address(__d.categoryRegistry)
        //             )
        //         )
        //     )
        // );
        __d.loan = PWNLoan(0xc58791ec351349a82036aE712976109C10e34217);

        // console2.log("PWNLoan:", address(__d.loan));

        __d.hub = PWNHub(0x37807A2F031b3B44081F4b21500E5D70EbaDAdd5);
        __d.revokedNonce = PWNRevokedNonce(0x972204fF33348ee6889B2d0A3967dB67d7b08e4c);
        __d.utilizedCredit = PWNUtilizedCredit(0x8E6F44DEa3c11d69C63655BDEcbA25Fa986BCE9D);
        __d.chainlinkFeedRegistry = IChainlinkFeedRegistryLike(0x8D5e90706E52a52853dA9A14fA1c63889a412851);
        __e.chainlinkL2SequencerUptimeFeed = address(0x0000000000000000000000000000000000000000);
        __e.weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        __d.products.installments = PWNInstallmentsProduct(
            _deploy(
                PWNContractDeployerSalt.INSTALLMENTS_PRODUCT,
                abi.encodePacked(
                    type(PWNInstallmentsProduct).creationCode,
                    abi.encode(
                        address(__d.hub), 
                        address(__d.revokedNonce), 
                        address(__d.utilizedCredit), 
                        address(__d.chainlinkFeedRegistry), 
                        __e.chainlinkL2SequencerUptimeFeed, 
                        __e.weth
                    )
                )
            )
        );
        // __d.products.installments = PWNInstallmentsProduct(address(0x366a95aDB86282d53c905F9b7d62746b02C4F679));
        console2.log("PWNInstallmentsProduct:", address(__d.products.installments));

        address[] memory addrs = new address[](3);
        addrs[0] = address(__d.loan);
        addrs[1] = address(__d.products.installments);
        addrs[2] = address(__d.products.installments);

        bytes32[] memory tags = new bytes32[](3);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.LOAN_PROPOSAL;
        tags[2] = PWNHubTags.NONCE_MANAGER;

// 0xf12715a1000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c58791ec351349a82036ae712976109c10e34217000000000000000000000000e24d470dfda38ace1e154f55997df34859892970000000000000000000000000e24d470dfda38ace1e154f55997df3485989297000000000000000000000000000000000000000000000000000000000000000039e56ea094d7a53440eef11fa42b63159fbf703b4ee579494a6ae85afc5603594c0ba7a416221f318a8087fd62f9ff407488b7f5501e79caf9b0666c2df326b9ce41b33e4d1c538d376dd219215a123562fbb87b8c85fa2aa4ebbd8810c2454d9

        // 0x000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c58791ec351349a82036ae712976109c10e34217000000000000000000000000e24d470dfda38ace1e154f55997df34859892970000000000000000000000000e24d470dfda38ace1e154f55997df3485989297000000000000000000000000000000000000000000000000000000000000000039e56ea094d7a53440eef11fa42b63159fbf703b4ee579494a6ae85afc5603594c0ba7a416221f318a8087fd62f9ff407488b7f5501e79caf9b0666c2df326b9ce41b33e4d1c538d376dd219215a123562fbb87b8c85fa2aa4ebbd8810c2454d9

        // note: this should be called on the protocolTimelock contract and use `schedule` and then `execute`
        //  functions where the target arg is the PWNHub and the data is the encoded bytes logged below
        // note 2: when setting tags for proposal, it needs to have both LOAN_PROPOSAL and NONCE_MANAGER
        //  tags in order to work fully correctly
        console2.logBytes(abi.encodeWithSignature("setTags(address[],bytes32[],bool)", addrs, tags, true));

        /*
            USDC --> weETH route
            1) USDC --> USD  ( 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6 , non inverted )
            2) USD --> ETH   ( 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 , inverted )
            3) eth --> weETH ( 0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22 , inverted )
        */

        address[] memory feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = address(0x0000000000000000000000000000000000000348); // USD
        feedIntermediaryDenominations[1] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH
        bool[] memory feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = false;
        feedInvertFlags[1] = true;
        feedInvertFlags[2] = true;
       
        /*
            SEPOLIA ROUTE
            EURS --> WETH route
            - assuming EURS === EUR as there is no separate EURS feed on Sepolia
            - assuming that WETH === ETH as there is no separate WETH feed on Sepolia
            1) EUR --> USD (0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910, non inverted)
            2) USD --> ETH (0x694AA1769357215DE4FAC081bf1f309aDC325306, inverted)
        address[] memory feedIntermediaryDenominations = new address[](1);
        feedIntermediaryDenominations[0] = address(0x0000000000000000000000000000000000000348); // USD
        bool[] memory feedInvertFlags = new bool[](2);
        feedInvertFlags[0] = false;
        feedInvertFlags[1] = true;
        */

        // __d.loan = PWNLoan(0xc58791ec351349a82036aE712976109C10e34217);
        // __d.products.installments = PWNInstallmentsProduct(0x68669e7ec29070e3dfa684cb4893282Cd4C9E608);
        __e.aave = IAaveLike(address(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2));

        __d.crowdsourceLenderVault = PWNCrowdsourceLenderVault(
            _deploy(
                PWNContractDeployerSalt.CROWDSOURCE_LENDER_VAULT,
                abi.encodePacked(
                    type(PWNCrowdsourceLenderVault).creationCode,
                    abi.encode(
                        address(__d.loan), 
                        address(__d.products.installments), 
                        address(__e.aave),
                        "BordelMortgageVaultShare", 
                        "BORDEL",
                        PWNCrowdsourceLenderVault.Terms({
                            collateralAddress: address(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee), // weETH
                            creditAddress: address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), // USDC
                            feedIntermediaryDenominations: feedIntermediaryDenominations,
                            feedInvertFlags: feedInvertFlags,
                            loanToValue: 7500, // 75%
                            interestAPR: 250, // 2.5%
                            postponement: 15780000, // 6 months in seconds
                            duration: 157800000, // 5 years in seconds
                            minCreditAmount: 180000000000, // 180 000 USDC (6 decimals)
                            expiration: block.timestamp + 6480000, // 75 days from now
                            allowedAcceptor: address(0x8a7a728a181E674833E018706422cb28543abD87)
                        })
                    )
                )
            )
        );

        console2.log("PWNCrowdsourceLenderVault:", address(__d.crowdsourceLenderVault));

        vm.stopBroadcast();
    }

}
