// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { LoanTerms } from "pwn/core/loan/LoanTerms.sol";

/**
 * @title IPWNProposalModule
 * @dev Interface for the Proposal Module within the PWN Protocol's loan core system.
 * This module is responsible for handling proposals related to loan agreements,
 * such as creating, managing, and validating loan proposals between parties.
 * It defines the essential functions that must be implemented to facilitate
 * secure and flexible negotiation of loan terms, ensuring that proposals
 * adhere to protocol standards and can be integrated with other modules.
 * The Proposal Module serves as a key component in the workflow of decentralized
 * lending, enabling users to interact with loan offers and requests in a trustless manner.
 */
interface IPWNProposalModule {

    /**
     * @notice Returns the name and version of the proposal module.
     * @dev This function provides metadata about the module for identification and compatibility purposes.
     * @return name The name of the proposal module.
     * @return version The version of the proposal module.
     */
    function nameAndVersion() external view returns (string memory name, string memory version);

    /**
     * @notice Hashes typed proposal data.
     * @param proposalData Encoded proposal data.
     * @return The hash of the proposal data.
     */
    function hashProposalTypedData(bytes calldata proposalData) external view returns (bytes32);

    /**
     * @notice Accept a loan proposal and return the agreed loan terms.
     * @param loanId Unique identifier for the loan created from the proposal.
     * @param acceptor Address accepting the proposal.
     * @param proposer Address of the proposer who created the proposal.
     * @param proposalData Encoded proposal data.
     * @return loanTerms LoanTerms struct containing the agreed loan parameters.
     */
    function acceptProposal(
        uint256 loanId,
        address acceptor,
        address proposer,
        bytes calldata proposalData
    ) external returns (LoanTerms memory loanTerms);

}
