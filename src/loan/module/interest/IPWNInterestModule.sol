// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNModuleInitializationHook } from "pwn/loan/module/IPWNModuleInitializationHook.sol";


bytes32 constant INTEREST_MODULE_INIT_HOOK_RETURN_VALUE = keccak256("PWNInterestModule.onLoanCreated");


/**
 * @title IPWNInterestModule
 * @notice Interface for PWN interest modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * The PWNLoan contract calls the `interest` function to calculate the interest accrued since the last update.
 * The module must use the `lastUpdateTimestamp` (fetched from the loan contract at the provided address)
 * to ensure only interest accrued since the last update is returned.
 *
 * The module must also implement the `onLoanCreated` initialization hook, which is called by PWNLoan
 * at loan origination to configure the module for the specific loan. The hook must return a
 * keccak256 hash of "PWNInterestModule.onLoanCreated".
 */
interface IPWNInterestModule is IPWNModuleInitializationHook {
    /**
     * @notice Returns the interest accrued for a loan since its last update.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return The amount of interest accrued since the last update timestamp.
     *
     * @dev The implementation must fetch the `lastUpdateTimestamp` from the loan contract
     * and calculate interest only for the period after this timestamp.
     */
    function interest(address loanContract, uint256 loanId) external view returns (uint256);
}
