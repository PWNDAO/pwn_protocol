// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, Asset } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNBorrowerCreateHook, BORROWER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNBorrowerCreateHook.sol";
import { PWNLoan, LOANStatus } from "pwn/core/loan/PWNLoan.sol";


/**
 * @title PWNRefinanceBorrowerCreateHook
 * @notice Borrower create hook for refinancing an existing PWN loan. Ensures the new loan repays the old one and validates collateral and credit consistency.
 */
contract PWNRefinanceBorrowerCreateHook is IPWNBorrowerCreateHook {
    using MultiToken for Asset;
    using MultiToken for address;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;

    /**
     * @notice Struct containing data required for refinancing logic.
     * @param refinanceLoanId The ID of the loan to be refinanced and repaid.
     */
    struct HookData {
        uint256 refinanceLoanId;
    }

    /** @notice Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
    /** @notice Thrown when the caller does not have the ACTIVE_LOAN tag in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when the borrower address is zero.*/
    error BorrowerZeroAddress();
    /** @notice Thrown when the credit address is zero.*/
    error CreditZeroAddress();
    /** @notice Thrown when the principal amount is zero.*/
    error PrincipalZero();
    /** @notice Thrown when the borrower does not match the refinanced loan.*/
    error BorrowerMismatch();
    /** @notice Thrown when the credit asset does not match the refinanced loan.*/
    error CreditMismatch();
    /** @notice Thrown when the collateral does not match the refinanced loan.*/
    error CollateralMismatch();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    /**
     * @notice Called when a new loan is created to perform refinancing logic.
     * @dev Validates the refinancing parameters, repays the old loan, and transfers the required credit from the borrower.
     * @inheritdoc IPWNBorrowerCreateHook
     */
    function onLoanCreated(
        address borrower,
        Asset calldata collateral,
        address creditAddress,
        uint256 principal,
        bytes calldata borrowerData
    ) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        if (borrower == address(0)) revert BorrowerZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (principal == 0) revert PrincipalZero();
        HookData memory data = abi.decode(borrowerData, (HookData));

        PWNLoan.LOAN memory loan = PWNLoan(msg.sender).getLOAN(data.refinanceLoanId);
        if (loan.borrower != borrower) revert BorrowerMismatch();
        if (loan.creditAddress != creditAddress) revert CreditMismatch();
        if (!loan.collateral.isSameAs(collateral)) revert CollateralMismatch();

        // Note: loan creation will revert if collateral amount is insufficient

        uint256 debt = PWNLoan(msg.sender).getLOANDebt(data.refinanceLoanId);
        Asset memory credit = creditAddress.ERC20(debt);
        credit.transferAssetFrom(borrower, address(this));
        credit.approveAsset(msg.sender);
        PWNLoan(msg.sender).repay(data.refinanceLoanId, 0);

        // Note: repay will revert if loan not RUNNING

        return BORROWER_CREATE_HOOK_RETURN_VALUE;
    }

}
