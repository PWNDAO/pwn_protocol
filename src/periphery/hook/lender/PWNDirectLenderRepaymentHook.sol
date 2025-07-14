// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";


/**
 * @title PWNDirectLenderRepaymentHook
 * @notice Lender repayment hook that directly transfers the repayment to the lender.
 * @dev This hook is used to forward the repayment amount to the lender's address without any additional logic.
 */
contract PWNDirectLenderRepaymentHook is IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    /** @notice Thrown when the lender address is zero.*/
    error LenderZeroAddress();
    /** @notice Thrown when the credit asset address is zero.*/
    error CreditZeroAddress();
    /** @notice Thrown when the repayment amount is zero.*/
    error RepaymentZero();
    /** @notice Thrown when the lender data is not empty.*/
    error DataNotEmpty();

    /**
     * @notice Called on loan repayment to transfer repayment directly to the lender.
     * @inheritdoc IPWNLenderRepaymentHook
     */
    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (repayment == 0) revert RepaymentZero();
        if (lenderData.length != 0) revert DataNotEmpty();

        creditAddress.ERC20(repayment).transferAssetFrom(address(this), lender);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}
