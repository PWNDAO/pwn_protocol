// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNProposalManager } from "pwn/core/loan/PWNProposalManager.sol";


contract PWNProposalManagerHarness is PWNProposalManager {

    function exposed_checkProposalSignature(
        address proposer,
        bytes32 proposalHash,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) external view {
        return _checkProposalSignature(proposer, proposalHash, proposalInclusionProof, signature);
    }

}
