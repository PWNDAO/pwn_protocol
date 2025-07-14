// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IERC721Receiver } from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver, IERC165 } from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


/**
 * @title PWNClaimLiquidationModule
 * @notice Liquidation module allowing the LOAN token owner to claim collateral of a defaulted loan.
 * @dev Only the LOAN token owner can call liquidate to claim the collateral. No repayment is required.
 */
contract PWNClaimLiquidationModule is IPWNLiquidationModule, IERC721Receiver, IERC1155Receiver {
    using MultiToken for MultiToken.Asset;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;

    /** @notice Mapping from loan ID to the address of the loan contract can liquidate the loan.*/
    mapping (uint256 => address) internal _loanContracts;

    /** @notice Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
    /** @notice Thrown when the caller does not have the ACTIVE_LOAN tag in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when a loan is already initialized in this module.*/
    error LoanAlreadyInitialized();
    /** @notice Thrown when the liquidator is not the LOAN token owner.*/
    error LiquidatorNotLoanOwner(address owner, address liquidator, address loanContract, uint256 loanId);
    /** @notice Thrown when the liquidation data is not empty.*/
    error LiquidationDataNotEmpty();
    /** @notice Thrown when the liquidation caller is not a loan contract.*/
    error CallerNotLoanContract();

    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }

    /**
     * @notice Initialization hook for the liquidation module, called on loan creation.
     * @dev Always returns the expected hook return value. No initialization logic is required.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (_loanContracts[loanId] != address(0)) revert LoanAlreadyInitialized();
        if (proposerData.length != 0) revert LiquidationDataNotEmpty();

        _loanContracts[loanId] = msg.sender;

        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Allows the LOAN token owner to claim the collateral of a defaulted loan.
     * @dev Only callable by the LOAN token owner. The liquidation data must be empty. No repayment is required.
     * @inheritdoc IPWNLiquidationModule
     */
    function liquidate(
        uint256 loanId,
        address liquidator,
        address /* borrower */,
        uint256 /* debt */,
        address /* creditAddress */,
        MultiToken.Asset calldata collateral,
        bytes calldata data
    ) external returns (uint256) {
        address loanContract = msg.sender;
        if (_loanContracts[loanId] != loanContract) revert CallerNotLoanContract();
        if (data.length != 0) revert LiquidationDataNotEmpty();

        address loanOwner = PWNLoan(loanContract).loanToken().ownerOf(loanId);
        if (loanOwner != liquidator) revert LiquidatorNotLoanOwner(loanOwner, liquidator, loanContract, loanId);

        collateral.transferAssetFrom(address(this), loanOwner);

        return 0;
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
