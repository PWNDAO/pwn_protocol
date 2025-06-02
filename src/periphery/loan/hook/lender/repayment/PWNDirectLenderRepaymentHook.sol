// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";


contract PWNDirectLenderRepaymentHook is IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    error LenderZeroAddress();
    error CreditZeroAddress();
    error RepaymentZero();
    error DataNotEmpty();

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
