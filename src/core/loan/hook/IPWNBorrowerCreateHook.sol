// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";


bytes32 constant BORROWER_CREATE_HOOK_RETURN_VALUE = keccak256("PWNBorrowerCreateHook.onLoanCreated");

interface IPWNBorrowerCreateHook {
    /** @dev Must return keccak of "PWNBorrowerCreateHook.onLoanCreated"*/
    function onLoanCreated(
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 principal,
        bytes calldata borrowerData
    ) external returns (bytes32);
}
