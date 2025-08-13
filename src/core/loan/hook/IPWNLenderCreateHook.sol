// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

bytes32 constant LENDER_CREATE_HOOK_RETURN_VALUE = keccak256("PWNLenderCreateHook.onLoanCreated");

/**
 * @title IPWNLenderCreateHook
 * @notice Interface for lender-side create hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract at loan origination to allow the lender to execute custom logic
 * (e.g., on-deman funds withdrawal, asset swaps) before the loan is finalized. The hook must return
 * the keccak256 hash of "PWNLenderCreateHook.onLoanCreated" to confirm successful execution.
 */
interface IPWNLenderCreateHook {
    /**
     * @notice Called by PWNLoan at loan origination to execute lender-side custom logic.
     * @param loanId The ID of the loan being created.
     * @param lender The address of the lender.
     * @param creditAddress The address of the credit token used for the loan.
     * @param principal The principal amount of the loan.
     * @param lenderData Additional data provided by the lender for custom logic.
     * @return A keccak256 hash of "PWNLenderCreateHook.onLoanCreated".
     */
    function onLoanCreated(
        uint256 loanId,
        address lender,
        address creditAddress,
        uint256 principal,
        bytes calldata lenderData
    ) external returns (bytes32);
}
