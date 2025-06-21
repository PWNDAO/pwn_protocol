// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IERC721Receiver } from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver, IERC165 } from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";

import {
    IPWNLiquidationModule,
    IPWNModuleInitializationHook,
    LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE
} from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


/**
 * @title PWNOpenLiquidationModule
 * @notice Liquidation module allowing anyone to liquidate a defaulted loan by repaying the full debt.
 * @dev The liquidator repays the full debt in the credit asset and receives the collateral. No extra data is allowed.
 */
contract PWNOpenLiquidationModule is IPWNLiquidationModule, IERC721Receiver, IERC1155Receiver {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    /** @notice Thrown when the liquidation data is not empty.*/
    error LiquidationDataNotEmpty();

    /**
     * @notice Initialization hook for the liquidation module, called on loan creation.
     * @dev Always returns the expected hook return value. No initialization logic is required.
     * @inheritdoc IPWNModuleInitializationHook
     */
    function onLoanCreated(uint256 /* loanId */, bytes calldata /* proposerData */) external pure returns (bytes32) {
        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Allows anyone to liquidate a defaulted loan by repaying the full debt and claiming the collateral.
     * @dev The liquidator must repay the full debt in the credit asset. The liquidation data must be empty.
     * @inheritdoc IPWNLiquidationModule
     */
    function liquidate(
        uint256 /* loanId */,
        address liquidator,
        uint256 debt,
        address creditAddress,
        MultiToken.Asset calldata collateral,
        bytes calldata data
    ) external returns (uint256) {
        if (data.length != 0) revert LiquidationDataNotEmpty();

        MultiToken.Asset memory credit = creditAddress.ERC20(debt);
        credit.transferAssetFrom(liquidator, address(this));
        credit.approveAsset(msg.sender); // Note: approve loan contract

        collateral.transferAssetFrom(address(this), liquidator);

        return debt;
    }


    /*----------------------------------------------------------*|
    |*  # ERC721/1155 RECEIVED HOOKS                            *|
    |*----------------------------------------------------------*/

    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * @return `IERC721Receiver.onERC721Received.selector` if transfer is allowed
     */
    function onERC721Received(
        address /* operator */,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) override external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     * To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address /* operator */,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    ) override external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated. To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata /*ids*/,
        uint256[] calldata /*values*/,
        bytes calldata /*data*/
    ) override external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }


    /*----------------------------------------------------------*|
    |*  # SUPPORTED INTERFACES                                  *|
    |*----------------------------------------------------------*/

    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external pure virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IPWNLiquidationModule).interfaceId;
    }

}
