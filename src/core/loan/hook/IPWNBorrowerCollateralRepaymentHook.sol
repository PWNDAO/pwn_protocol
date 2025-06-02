// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";


bytes32 constant BORROWER_REPAYMENT_HOOK_RETURN_VALUE = keccak256("PWNBorrowerCollateralRepaymentHook.onLoanRepaid");

interface IPWNBorrowerCollateralRepaymentHook {
    /** @dev Must return keccak of "PWNBorrowerCollateralRepaymentHook.onLoanRepaid"*/
    function onLoanRepaid(
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 repayment,
        bytes calldata borrowerData
    ) external returns (bytes32);
}
