// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";
import { IERC4626Like } from "pwn/periphery/interfaces/IERC4626Like.sol";


contract PWN4626VaultLenderRepaymentHook is IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    struct HookData {
        address vault;
    }

    error LenderZeroAddress();
    error CreditZeroAddress();
    error RepaymentZero();
    error InvalidVaultAsset(address creditAsset, address vaultAsset);


    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (repayment == 0) revert RepaymentZero();
        HookData memory data = abi.decode(lenderData, (HookData));

        // Check the asset of the vault
        address vaultAsset = IERC4626Like(data.vault).asset();
        if (creditAddress != vaultAsset) {
            revert InvalidVaultAsset(creditAddress, vaultAsset);
        }

        // Note: Performing optimistic deposit, assuming that the vault will revert if the amount exceeds the max deposit.
        // Supply to the vault on behalf of the lender.
        creditAddress.ERC20(repayment).approveAsset(data.vault);
        IERC4626Like(data.vault).deposit(repayment, lender);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}
