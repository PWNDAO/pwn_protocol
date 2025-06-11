// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

bytes32 constant BORROWER_REPAYMENT_HOOK_RETURN_VALUE = keccak256("PWNBorrowerCollateralRepaymentHook.onLoanRepaid");

/**
 * @title IPWNBorrowerCollateralRepaymentHook
 * @notice Interface for borrower-side repayment hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract when the borrower decides to repay the full amount of a loan using their collateral.
 * At this point, the collateral is transferred into the hook contract, enabling advanced flows where the collateral itself is used to repay the loan.
 * The hook can implement logic to sell, unwrap, or otherwise utilize the accumulated value of the collateral to cover the outstanding debt.
 *
 * After the hook execution, the loan contract will transfer the full repayment amount from the hook contract. The hook must ensure
 * that the loan contract has the necessary approval to transfer the repayment amount in the credit token.
 *
 * The hook must return the keccak256 hash of "PWNBorrowerCollateralRepaymentHook.onLoanRepaid" to confirm successful execution.
 *
 * Implementing contracts must also implement the ERC721 and ERC1155 receiver interfaces, as the loan contract
 * transfers collateral using safe transfer functions. This ensures the hook can properly receive and handle NFT or multi-token collateral.
 */
interface IPWNBorrowerCollateralRepaymentHook {
    /**
     * @notice Called by PWNLoan when the borrower repays the full amount of a loan using their collateral.
     * @dev The collateral is transferred into the hook contract, enabling custom logic to sell, unwrap, or otherwise utilize
     * the collateral's value to cover the outstanding debt. After execution, the loan contract will transfer the full repayment
     * amount from the hook contract, so the hook must ensure the loan contract has approval for the repayment in the credit token.
     * @param borrower The address of the borrower.
     * @param collateral The collateral asset being received and managed by the hook.
     * @param creditAddress The address of the credit token used for the loan.
     * @param repayment The amount to be repaid by the borrower (must be approved for transfer by the loan contract).
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
