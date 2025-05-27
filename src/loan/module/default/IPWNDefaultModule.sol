// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNModuleInitializationHook } from "pwn/loan/module/IPWNModuleInitializationHook.sol";


bytes32 constant DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE = keccak256("PWNDefaultModule.onLoanCreated");


/**
 * @title IPWNDefaultModule
 * @notice Interface for PWN default modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * The PWNLoan contract calls the `isDefaulted` function to determine if a loan is in default.
 * The module must use the loan's state (fetched from the loan contract at the provided address)
 * to evaluate whether default conditions are met (e.g., time-based, debt limit, or other criteria).
 *
 * The module must also implement the `onLoanCreated` initialization hook, which is called by PWNLoan
 * at loan origination to configure the module for the specific loan. The hook must return a
 * keccak256 hash of "PWNDefaultModule.onLoanCreated".
 */
interface IPWNDefaultModule is IPWNModuleInitializationHook {
    /**
     * @notice Returns whether the loan is currently in default.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return True if the loan is in default, false otherwise.
     *
     * @dev The implementation must fetch relevant loan state from the loan contract
     * and evaluate default conditions according to the module's logic.
     */
    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool);
}
