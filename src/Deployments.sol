// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { stdJson } from "forge-std/StdJson.sol";
import { CommonBase } from "forge-std/Base.sol";

import { MultiTokenCategoryRegistry } from "MultiToken/MultiTokenCategoryRegistry.sol";

import { Strings } from "openzeppelin/utils/Strings.sol";

import { PWNConfig } from "pwn/core/config/PWNConfig.sol";
import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { PWNLOAN } from "pwn/core/token/PWNLOAN.sol";
import { IChainlinkFeedRegistryLike } from "pwn/periphery/interfaces/IChainlinkFeedRegistryLike.sol";
import { IChainlinkAggregatorLike } from "pwn/periphery/interfaces/IChainlinkAggregatorLike.sol";

import { PWNStableProduct } from "pwn/periphery/product/PWNStableProduct.sol";
import { PWNInstallmentsProduct } from "pwn/periphery/product/PWNInstallmentsProduct.sol";
import { PWNFixedProduct } from "pwn/periphery/product/PWNFixedProduct.sol";
import { PWNUniswapV3IndividualProduct } from "pwn/periphery/product/PWNUniswapV3IndividualProduct.sol";
import { PWNUniswapV3SetProduct } from "pwn/periphery/product/PWNUniswapV3SetProduct.sol";

import { PWNRefinanceBorrowerCreateHook } from "pwn/periphery/hook/borrower/PWNRefinanceBorrowerCreateHook.sol";
import { PWN4626VaultLenderHook } from "pwn/periphery/hook/lender/PWN4626VaultLenderHook.sol";
import { PWNAaveLenderHook, IAaveLike } from "pwn/periphery/hook/lender/PWNAaveLenderHook.sol";
import { PWNCompoundLenderHook } from "pwn/periphery/hook/lender/PWNCompoundLenderHook.sol";
import { PWNDirectLenderRepaymentHook } from "pwn/periphery/hook/lender/PWNDirectLenderRepaymentHook.sol";

import { PWNRevokedNonce } from "pwn/periphery/auxiliary/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/periphery/auxiliary/PWNUtilizedCredit.sol";

import { PWNCrowdsourceLenderVault } from "pwn/periphery/crowdsource/PWNCrowdsourceLenderVault.sol";


interface IPWNDeployer {
    function owner() external returns (address);
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address);
    function deployAndTransferOwnership(bytes32 salt, address owner, bytes memory bytecode) external returns (address);
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);
}

abstract contract Deployments is CommonBase {
    using stdJson for string;
    using Strings for uint256;

    string public deploymentsSubpath;

    bool wasPredeployedOnFork;
    Deployment __d;
    External __e;
    CreationCode __cc;

    struct Products {
        PWNStableProduct stable;
        PWNInstallmentsProduct installments;
        PWNFixedProduct _fixed; // Note: `fixed` is a reserved keyword (might need to be first to be alphabetically ordered)
        PWNUniswapV3IndividualProduct uniswapV3Individual;
        PWNUniswapV3SetProduct uniswapV3Set;
    }

    struct Hooks {
        PWN4626VaultLenderHook vaultLender;
        PWNAaveLenderHook aaveLender;
        PWNCompoundLenderHook compoundLender;
        PWNDirectLenderRepaymentHook directLenderRepayment;
        PWNRefinanceBorrowerCreateHook refinanceBorrowerCreate;
    }

    /// @dev Properties need to be in alphabetical order.
    struct Deployment {
        MultiTokenCategoryRegistry categoryRegistry;
        IChainlinkFeedRegistryLike chainlinkFeedRegistry;
        PWNConfig config;
        PWNConfig configSingleton;
        PWNCrowdsourceLenderVault crowdsourceLenderVault;
        Hooks hooks;
        PWNHub hub;
        PWNLoan loan;
        PWNLOAN loanToken;
        Products products;
        PWNRevokedNonce revokedNonce;
        PWNUtilizedCredit utilizedCredit;
    }

    /// @dev Properties need to be in alphabetical order.
    struct External {
        IAaveLike aave;
        address adminTimelock;
        address chainlinkL2SequencerUptimeFeed;
        address dao;
        address daoSafe;
        IPWNDeployer deployer;
        address deployerSafe;
        bool isL2;
        address protocolTimelock;
        address uniswapV3Factory;
        address uniswapV3NFTPositionManager;
        address weth;
    }

    /// @dev Properties need to be in alphabetical order.
    struct CreationCode {
        bytes categoryRegistry;
        bytes chainlinkFeedRegistry;
        bytes config;
        bytes configSingleton_v1_2;
        bytes hub;
        bytes loanToken;
        bytes revokedNonce;
        bytes utilizedCredit;
        // todo: add loan & proposals
    }


    function _loadDeployedAddresses() internal {
        string memory root = vm.projectRoot();
        string memory chainIdKey = block.chainid.toString();

        // Load creation code
        _loadCreationCode(root);

        // Load external addresses
        _loadExternalAddresses(root, chainIdKey);

        // Load deployment addresses
        _loadDeploymentAddresses(root, chainIdKey);
    }

    function _loadCreationCode(string memory root) internal {
        string memory creationJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/creation/creationCode.json"));
        __cc.categoryRegistry = creationJson.readBytes(".categoryRegistry");
        __cc.chainlinkFeedRegistry = creationJson.readBytes(".chainlinkFeedRegistry");
        __cc.config = creationJson.readBytes(".config");
        __cc.configSingleton_v1_2 = creationJson.readBytes(".configSingleton_v1_2");
        __cc.hub = creationJson.readBytes(".hub");
        __cc.loanToken = creationJson.readBytes(".loanToken");
        __cc.revokedNonce = creationJson.readBytes(".revokedNonce");
        __cc.utilizedCredit = creationJson.readBytes(".utilizedCredit");
    }

    function _loadExternalAddresses(string memory root, string memory chainIdKey) internal {
        string memory externalJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/external/external.json"));
        string memory externalKey = string.concat(".", chainIdKey);
        __e.aave = IAaveLike(externalJson.readAddress(string.concat(externalKey, ".aave")));
        __e.adminTimelock = externalJson.readAddress(string.concat(externalKey, ".adminTimelock"));
        __e.chainlinkL2SequencerUptimeFeed = externalJson.readAddress(string.concat(externalKey, ".chainlinkL2SequencerUptimeFeed"));
        __e.dao = externalJson.readAddress(string.concat(externalKey, ".dao"));
        __e.daoSafe = externalJson.readAddress(string.concat(externalKey, ".daoSafe"));
        __e.deployer = IPWNDeployer(externalJson.readAddress(string.concat(externalKey, ".deployer")));
        __e.deployerSafe = externalJson.readAddress(string.concat(externalKey, ".deployerSafe"));
        __e.isL2 = externalJson.readBool(string.concat(externalKey, ".isL2"));
        __e.protocolTimelock = externalJson.readAddress(string.concat(externalKey, ".protocolTimelock"));
        __e.uniswapV3Factory = externalJson.readAddress(string.concat(externalKey, ".uniswapV3Factory"));
        __e.uniswapV3NFTPositionManager = externalJson.readAddress(string.concat(externalKey, ".uniswapV3NFTPositionManager"));
        __e.weth = externalJson.readAddress(string.concat(externalKey, ".weth"));
    }

    function _loadDeploymentAddresses(string memory root, string memory chainIdKey) private {
        string memory deploymentsJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/protocol/v1.5.json"));
        string memory deploymentKey = string.concat(".", chainIdKey);
        
        // Check if deployment exists for this chain by checking if raw bytes exist
        bytes memory rawDeployment = deploymentsJson.parseRaw(deploymentKey);
        
        if (rawDeployment.length > 0) {
            wasPredeployedOnFork = true;
            _loadDeploymentTopLevel(deploymentsJson, deploymentKey);
            _loadDeploymentProducts(deploymentsJson, deploymentKey);
            _loadDeploymentHooks(deploymentsJson, deploymentKey);
        } else {
            wasPredeployedOnFork = false;
            _protocolNotDeployedOnSelectedChain();
        }
    }

    function _safeReadAddress(string memory json, string memory key) private pure returns (address) {
        string memory addrStr = json.readString(key);
        if (bytes(addrStr).length == 0) {
            return address(0);
        }
        return json.readAddress(key);
    }

    function _loadDeploymentTopLevel(string memory deploymentsJson, string memory deploymentKey) private {
        __d.categoryRegistry = MultiTokenCategoryRegistry(_safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".categoryRegistry")));
        __d.chainlinkFeedRegistry = IChainlinkFeedRegistryLike(_safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".chainlinkFeedRegistry")));
        __d.config = PWNConfig(_safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".config")));
        __d.configSingleton = PWNConfig(_safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".configSingleton")));
        __d.hub = PWNHub(_safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".hub")));
        __d.loanToken = PWNLOAN(_safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".loanToken")));

        address addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".crowdsourceLenderVault"));
        if (addr != address(0)) __d.crowdsourceLenderVault = PWNCrowdsourceLenderVault(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".loan"));
        if (addr != address(0)) __d.loan = PWNLoan(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".revokedNonce"));
        if (addr != address(0)) __d.revokedNonce = PWNRevokedNonce(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".utilizedCredit"));
        if (addr != address(0)) __d.utilizedCredit = PWNUtilizedCredit(addr);
    }

    function _loadDeploymentProducts(string memory deploymentsJson, string memory deploymentKey) private {
        address addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".products.stable"));
        if (addr != address(0)) __d.products.stable = PWNStableProduct(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".products.installments"));
        if (addr != address(0)) __d.products.installments = PWNInstallmentsProduct(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".products.fixed"));
        if (addr != address(0)) __d.products._fixed = PWNFixedProduct(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".products.uniswapV3Individual"));
        if (addr != address(0)) __d.products.uniswapV3Individual = PWNUniswapV3IndividualProduct(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".products.uniswapV3Set"));
        if (addr != address(0)) __d.products.uniswapV3Set = PWNUniswapV3SetProduct(addr);
    }

    function _loadDeploymentHooks(string memory deploymentsJson, string memory deploymentKey) private {
        address addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".hooks.aaveLender"));
        if (addr != address(0)) __d.hooks.aaveLender = PWNAaveLenderHook(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".hooks.compoundLender"));
        if (addr != address(0)) __d.hooks.compoundLender = PWNCompoundLenderHook(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".hooks.directLenderRepayment"));
        if (addr != address(0)) __d.hooks.directLenderRepayment = PWNDirectLenderRepaymentHook(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".hooks.refinanceBorrowerCreate"));
        if (addr != address(0)) __d.hooks.refinanceBorrowerCreate = PWNRefinanceBorrowerCreateHook(addr);

        addr = _safeReadAddress(deploymentsJson, string.concat(deploymentKey, ".hooks.vaultLender"));
        if (addr != address(0)) __d.hooks.vaultLender = PWN4626VaultLenderHook(addr);
    }

    function _protocolNotDeployedOnSelectedChain() internal virtual {
        // Override
    }

}
