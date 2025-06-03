// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

bytes32 constant LENDER_REPAYMENT_HOOK_RETURN_VALUE = keccak256("PWNLenderRepaymentHook.onLoanRepaid");

/**
 * @title IPWNLenderRepaymentHook
 * @notice Interface for lender-side repayment hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract when a lender receives a repayment, allowing the lender to execute
 * custom logic (e.g., claim to lender address, deposit to external vault) upon repayment. The hook must return
 * the keccak256 hash of "PWNLenderRepaymentHook.onLoanRepaid" to confirm successful execution.
 */
interface IPWNLenderRepaymentHook {
    /**
     * @notice Called by PWNLoan when a lender receives a repayment to execute lender-side custom logic.
     * @param lender The address of the lender.
     * @param creditAddress The address of the credit token used for the loan.
     * @param repayment The amount repaid to the lender.
     * @param lenderData Additional data provided by the lender for custom logic.
     * @return A keccak256 hash of "PWNLenderRepaymentHook.onLoanRepaid".
     */
    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32);
}
