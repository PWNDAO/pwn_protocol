// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNModuleInitializationHook
 * @notice Interface for module initialization hooks used by PWNLoan modules.
 *
 * @dev This interface defines a hook that is called by the PWNLoan contract at loan origination
 * to initialize and configure a module (such as interest, default, or liquidation modules) for a specific loan.
 * The hook must return a keccak256 hash of the module name followed by ".onLoanCreated" to confirm successful initialization.
 */
interface IPWNModuleInitializationHook {
    /**
     * @notice Hook called by PWNLoan at loan origination to initialize the module.
     * @dev This hook is used to configure the module for the specific loan. The return value
     * must be a keccak256 hash of the module name followed by ".onLoanCreated".
     * @param loanId The unique identifier of the loan being created.
     * @param proposerData Additional data provided by the proposer at loan creation.
     * @return A keccak256 hash of the module name + ".onLoanCreated", e.g., "PWNDefaultModule.onLoanCreated".
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32);
}
