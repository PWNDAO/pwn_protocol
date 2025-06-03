// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

bytes32 constant BORROWER_REPAYMENT_HOOK_RETURN_VALUE = keccak256("PWNBorrowerCollateralRepaymentHook.onLoanRepaid");

/**
 * @title IPWNBorrowerCollateralRepaymentHook
 * @notice Interface for borrower-side repayment hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract when a borrower repays a loan. This hook can be used
 * to enable advanced repayment flows, such as allowing the borrower to use their collateral to repay the full loan debt
 * instead of (or in addition to) making a standard repayment in the credit token. The hook must return
 * the keccak256 hash of "PWNBorrowerCollateralRepaymentHook.onLoanRepaid" to confirm successful execution.
 */
interface IPWNBorrowerCollateralRepaymentHook {
    /**
     * @notice Called by PWNLoan when a borrower repays a loan to execute borrower-side custom logic.
     * @param borrower The address of the borrower.
     * @param collateral The collateral asset being returned or managed.
     * @param creditAddress The address of the credit token used for the loan.
     * @param repayment The amount repaid by the borrower.
     * @param borrowerData Additional data provided by the borrower for custom logic.
     * @return A keccak256 hash of "PWNBorrowerCollateralRepaymentHook.onLoanRepaid".
     */
    function onLoanRepaid(
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 repayment,
        bytes calldata borrowerData
    ) external returns (bytes32);
}
