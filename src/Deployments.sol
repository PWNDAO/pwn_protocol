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
        PWNFixedProduct _fixed; // Note: `fixed` is a reserved keyword
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
        address permit2;
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

        string memory creationJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/creation/creationCode.json"));
        bytes memory rawCreation = creationJson.parseRaw(".");
        __cc = abi.decode(rawCreation, (CreationCode));

        string memory externalJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/external/external.json"));
        bytes memory rawExternal = externalJson.parseRaw(string.concat(".", block.chainid.toString()));
        __e = abi.decode(rawExternal, (External));

        string memory deploymentsJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/protocol/v1.5.json"));
        bytes memory rawDeployment = deploymentsJson.parseRaw(string.concat(".", block.chainid.toString()));

        if (rawDeployment.length > 0) {
            wasPredeployedOnFork = true;
            __d = abi.decode(rawDeployment, (Deployment));
        } else {
            wasPredeployedOnFork = false;
            _protocolNotDeployedOnSelectedChain();
        }
    }

    function _protocolNotDeployedOnSelectedChain() internal virtual {
        // Override
    }

}
