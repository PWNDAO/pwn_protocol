// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNModuleInitializationHook } from "pwn/core/loan/module/IPWNModuleInitializationHook.sol";


bytes32 constant LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE = keccak256("PWNLiquidationModule.onLoanCreated");


/**
 * @title IPWNLiquidationModule
 * @notice Interface for PWN liquidation modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * When a loan is in default, as determined by the default module, the Loan contract calls the liquidation module
 * to execute the liquidation process. The collateral is transferred to the liquidation module, which is then responsible
 * for handling the liquidation (e.g., auction, direct sale, or other custom logic).
 *
 * The liquidation module can return any amount as the liquidation amount, including values less than or greater than the total debt.
 * This means liquidations can result in a loss or extra profit for lenders, making this module a critical part of the protocol's security.
 * Careful review and testing of custom liquidation modules is strongly recommended.
 *
 * The `debt` argument passed to the `liquidate` function should be used as the outstanding loan debt.
 * Do not fetch the debt from the loan contract, as the debt is removed from the loan contract state
 * prior to calling the liquidation module. Always rely on the provided argument for the correct value.
 *
 * The module must implement the `onLoanCreated` initialization hook, which is called by PWNLoan
 * at loan origination to configure the module for the specific loan. The hook must return a keccak256 hash
 * of "PWNLiquidationModule.onLoanCreated".
 *
 * The caller of the `liquidate` function is always expected to be the Loan contract. However, modules should implement
 * additional access control checks to ensure that only the authorized Loan contract can call this function and prevent
 * unauthorized access or misuse.
 */
interface IPWNLiquidationModule is IPWNModuleInitializationHook {
    /**
     * @notice Executes the liquidation process for a loan.
     * @dev This function is called by PWNLoan to perform the liquidation process.
     * Collateral is transferred to the liquidation module before this function is called.
     * Liquidation amount is transferred by the PWNLoan contract at the end of the liquidation process.
     * @param loanId The unique identifier of the loan.
     * @param liquidator The address of the entity initiating the liquidation.
     * @param debt The total outstanding debt of the loan at the time of liquidation.
     * @param creditAddress The address of the credit token used for the loan.
     * @param collateral The collateral asset being liquidated, represented as a MultiToken.Asset struct.
     * @param data Additional data that may be required for custom liquidation logic.
     * @return liquidationAmount The amount of collateral liquidated, which can be less than, greater than, or equal to the debt.
     */
    function liquidate(
        uint256 loanId,
        address liquidator,
        uint256 debt,
        address creditAddress,
        MultiToken.Asset calldata collateral,
        bytes calldata data
    ) external returns (uint256 liquidationAmount);
}
