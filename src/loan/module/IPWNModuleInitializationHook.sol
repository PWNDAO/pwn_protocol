// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface IPWNModuleInitializationHook {
    /**
     * @notice Hook called by PWNLoan at loan origination to initialize the module.
     * @param loanId The unique identifier of the loan being created.
     * @param proposerData Additional data provided by the proposer at loan creation.
     * @return A keccak256 hash of the module name + ".onLoanCreated", e.g., "PWNDefaultModule.onLoanCreated".
     *
     * @dev This hook is used to configure the module for the specific loan. The return value
     * must be a keccak256 hash of the module name followed by ".onLoanCreated".
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32);
}
