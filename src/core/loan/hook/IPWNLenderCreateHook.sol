// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

bytes32 constant LENDER_CREATE_HOOK_RETURN_VALUE = keccak256("PWNLenderCreateHook.onLoanCreated");

interface IPWNLenderCreateHook {
    /** @dev Must return keccak of "PWNLenderCreateHook.onLoanCreated"*/
    function onLoanCreated(
        address lender,
        address creditAddress,
        uint256 principal,
        bytes calldata lenderData
    ) external returns (bytes32);
}
