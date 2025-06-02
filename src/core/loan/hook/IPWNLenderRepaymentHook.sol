// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

bytes32 constant LENDER_REPAYMENT_HOOK_RETURN_VALUE = keccak256("PWNLenderRepaymentHook.onLoanRepaid");

interface IPWNLenderRepaymentHook {
    /** @dev Must return keccak of "PWNLenderRepaymentHook.onLoanRepaid"*/
    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32);
}
