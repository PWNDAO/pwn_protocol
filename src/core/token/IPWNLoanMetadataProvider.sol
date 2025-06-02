// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNLoanMetadataProvider
 * @notice Interface for a provider of a LOAN token metadata.
 * @dev Loan contracts should implement this interface.
 */
interface IPWNLoanMetadataProvider {

    /**
     * @notice Get a loan metadata uri for a LOAN token minted by this contract.
     * @return LOAN token metadata uri.
     */
    function loanMetadataUri() external view returns (string memory);

}
