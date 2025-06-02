// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IERC721Receiver } from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver, IERC165 } from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";


/**
 * @title PWN Vault
 * @notice Base contract for transferring and managing collateral and loan assets in PWN protocol.
 * @dev Loan contracts inherits PWN Vault to act as a Vault for its loan type.
 */
abstract contract PWNVault is IERC721Receiver, IERC1155Receiver {
    using MultiToken for MultiToken.Asset;

    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when asset transfer happens from an `origin` address to a vault.*/
    event VaultPull(MultiToken.Asset asset, address indexed origin);
    /** @notice Emitted when asset transfer happens from a vault to a `beneficiary` address.*/
    event VaultPush(MultiToken.Asset asset, address indexed beneficiary);
    /** @notice Emitted when asset transfer happens from an `origin` address to a `beneficiary` address.*/
    event VaultPushFrom(MultiToken.Asset asset, address indexed origin, address indexed beneficiary);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when the Vault receives an asset that is not transferred by the Vault itself.*/
    error UnsupportedTransferFunction();
    /** @notice Thrown when an asset transfer is incomplete.*/
    error IncompleteTransfer();
    /** @notice Thrown when an asset transfer source and destination address are the same.*/
    error VaultTransferSameSourceAndDestination(address addr);


    /*----------------------------------------------------------*|
    |*  # TRANSFER FUNCTIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Function pulling an asset into a vault.
     * @dev The function assumes a prior token approval to a vault address.
     * @param asset An asset construct - for a definition see { MultiToken dependency lib }.
     * @param origin Borrower address that is transferring collateral to Vault or repaying a loan.
     */
    function _pull(MultiToken.Asset memory asset, address origin) internal {
        uint256 originalBalance = asset.balanceOf(address(this));

        asset.transferAssetFrom(origin, address(this));
        _checkTransfer({
            asset: asset,
            originalBalance: originalBalance,
            checkedAddress: address(this),
            counterPartyAddress: origin
        });

        emit VaultPull(asset, origin);
    }

    /**
     * @notice Function pushing an asset from a vault to a recipient.
     * @dev This is used for claiming a paid back loan or a defaulted collateral, or returning collateral to a borrower.
     * @param asset An asset construct - for a definition see { MultiToken dependency lib }.
     * @param beneficiary An address of a recipient of an asset.
     */
    function _push(MultiToken.Asset memory asset, address beneficiary) internal {
        uint256 originalBalance = asset.balanceOf(beneficiary);

        asset.safeTransferAssetFrom(address(this), beneficiary);
        _checkTransfer({
            asset: asset,
            originalBalance: originalBalance,
            checkedAddress: beneficiary,
            counterPartyAddress: address(this)
        });

        emit VaultPush(asset, beneficiary);
    }

    /**
     * @notice Function pushing an asset from an origin address to a beneficiary address.
     * @dev The function assumes a prior token approval to a vault address.
     * @param asset An asset construct - for a definition see { MultiToken dependency lib }.
     * @param origin An address of a lender who is providing a loan asset.
     * @param beneficiary An address of the recipient of an asset.
     */
    function _pushFrom(MultiToken.Asset memory asset, address origin, address beneficiary) internal {
        uint256 originalBalance = asset.balanceOf(beneficiary);

        asset.safeTransferAssetFrom(origin, beneficiary);
        _checkTransfer({
            asset: asset,
            originalBalance: originalBalance,
            checkedAddress: beneficiary,
            counterPartyAddress: origin
        });

        emit VaultPushFrom(asset, origin, beneficiary);
    }

    function _checkTransfer(
        MultiToken.Asset memory asset,
        uint256 originalBalance,
        address checkedAddress,
        address counterPartyAddress
    ) private view {
        if (checkedAddress == counterPartyAddress) {
            revert VaultTransferSameSourceAndDestination({ addr: checkedAddress });
        }

        uint256 expectedBalance = originalBalance + asset.getTransferAmount();
        if (expectedBalance != asset.balanceOf(checkedAddress)) {
            revert IncompleteTransfer();
        }
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
        address operator,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) override external view returns (bytes4) {
        if (operator != address(this))
            revert UnsupportedTransferFunction();

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
        address operator,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    ) override external view returns (bytes4) {
        if (operator != address(this))
            revert UnsupportedTransferFunction();

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
        revert UnsupportedTransferFunction();
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
            interfaceId == type(IERC1155Receiver).interfaceId;
    }

}
