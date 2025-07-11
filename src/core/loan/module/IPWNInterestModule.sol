// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNInterestModule
 * @notice Interface for PWN interest modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * The PWNLoan contract calls the `interest` function to calculate the interest accrued since the last update.
 * The module must use the `lastUpdateTimestamp` (fetched from the loan contract at the provided address)
 * to ensure only interest accrued since the last update is returned.
 *
 * Implementations do not have to account for unpaid accrued interest before the last update, as it is added to the total debt
 * by the loan contract. If the implementation computes interest only from the principal amount, it can safely ignore previously accrued interest.
 * Only if the module's logic requires it for its own computation should it consider previously accrued interest.
 *
 * The `interest` function MUST NOT revert. If the call to this function reverts, it will be interpreted
 * by the loan contract as returning zero interest accrued. Always return a value.
 */
interface IPWNInterestModule {
    /**
     * @notice Returns the interest accrued for a loan since its last update.
     * @dev The implementation must fetch the `lastUpdateTimestamp` from the loan contract
     * and calculate interest only for the period after this timestamp.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return The amount of interest accrued since the last update timestamp.
     */
    function interest(address loanContract, uint256 loanId) external view returns (uint256);
}
