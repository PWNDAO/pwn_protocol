// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderCreateHook.sol";
import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";
import { IERC4626Like } from "pwn/periphery/interfaces/IERC4626Like.sol";


/**
 * @title PWN4626VaultLenderHook
 * @notice Lender hook for integrating ERC4626 vaults with PWN loans.
 * @dev On loan creation, withdraws principal from the vault to the lender. On repayment, deposits repayment into the vault for the lender.
 */
contract PWN4626VaultLenderHook is IPWNLenderCreateHook, IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;

    /**
     * @notice Struct containing the vault address for the hook.
     * @param vault The ERC4626 vault address.
     */
    struct HookData {
        address vault;
    }

    /** @notice Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
    /** @notice Thrown when the caller does not have the ACTIVE_LOAN tag in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when the lender address is zero.*/
    error LenderZeroAddress();
    /** @notice Thrown when the credit asset address is zero.*/
    error CreditZeroAddress();
    /** @notice Thrown when the principal amount is zero.*/
    error PrincipalZero();
    /** @notice Thrown when the repayment amount is zero.*/
    error RepaymentZero();
    /** @notice Thrown when the vault asset does not match the credit asset.*/
    error InvalidVaultAsset(address creditAsset, address vaultAsset);
    /** @notice Thrown when the lender data length is invalid.*/
    error InvalidLenderDataLength();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }

    /**
     * @notice Called on loan creation to withdraw principal from the vault to the lender.
     * @dev Checks for valid input and vault asset. Performs an optimistic withdraw from the vault.
     * @inheritdoc IPWNLenderCreateHook
     */
    function onLoanCreated(
        address lender,
        address creditAddress,
        uint256 principal,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (principal == 0) revert PrincipalZero();
        if (lenderData.length != 32) revert InvalidLenderDataLength();
        address vault = abi.decode(lenderData, (address));

        // Check the asset of the vault
        address vaultAsset = IERC4626Like(vault).asset();
        if (creditAddress != vaultAsset) revert InvalidVaultAsset(creditAddress, vaultAsset);

        // Note: Performing optimistic withdraw, assuming that the vault will revert if the amount is not available
        // Withdraw from the vault to the owner
        IERC4626Like(vault).withdraw(principal, lender, lender);

        return LENDER_CREATE_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Called on loan repayment to deposit repayment into the vault for the lender.
     * @dev Checks for valid input and vault asset. Performs an optimistic deposit into the vault.
     * @inheritdoc IPWNLenderRepaymentHook
     */
    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (repayment == 0) revert RepaymentZero();
        if (lenderData.length != 32) revert InvalidLenderDataLength();
        address vault = abi.decode(lenderData, (address));

        // Check the asset of the vault
        address vaultAsset = IERC4626Like(vault).asset();
        if (creditAddress != vaultAsset) revert InvalidVaultAsset(creditAddress, vaultAsset);

        // Note: Performing optimistic deposit, assuming that the vault will revert if the amount exceeds the max deposit.
        // Supply to the vault on behalf of the lender.
        creditAddress.ERC20(repayment).approveAsset(vault);
        IERC4626Like(vault).deposit(repayment, lender);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}
