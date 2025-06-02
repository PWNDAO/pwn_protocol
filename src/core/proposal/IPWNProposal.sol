// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { LoanTerms } from "pwn/core/loan/LoanTerms.sol";


interface IPWNProposal {
    function acceptProposal(
        address acceptor,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) external returns (LoanTerms memory loanTerms);
}
