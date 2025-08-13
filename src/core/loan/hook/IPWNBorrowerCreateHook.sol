// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

bytes32 constant BORROWER_CREATE_HOOK_RETURN_VALUE = keccak256("PWNBorrowerCreateHook.onLoanCreated");

/**
 * @title IPWNBorrowerCreateHook
 * @notice Interface for borrower-side create hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract at loan origination to allow the borrower to execute custom logic
 * (e.g., collateral management, asset swaps, or additional setup) before the loan is finalized. This hook enables advanced flows
 * such as acquiring or "buying" the collateral with borrowed funds before it is locked as collateral in the loan. The hook must return
 * the keccak256 hash of "PWNBorrowerCreateHook.onLoanCreated" to confirm successful execution.
 */
interface IPWNBorrowerCreateHook {
    /**
     * @notice Called by PWNLoan at loan origination to execute borrower-side custom logic.
     * @param loanId The ID of the loan being created.
     * @param borrower The address of the borrower.
     * @param collateral The collateral asset being provided by the borrower.
     * @param creditAddress The address of the credit token used for the loan.
     * @param principal The principal amount of the loan.
     * @param borrowerData Additional data provided by the borrower for custom logic.
     * @return A keccak256 hash of "PWNBorrowerCreateHook.onLoanCreated".
     */
    function onLoanCreated(
        uint256 loanId,
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 principal,
        bytes calldata borrowerData
    ) external returns (bytes32);
}
