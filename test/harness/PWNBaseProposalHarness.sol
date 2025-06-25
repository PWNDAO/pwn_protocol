// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNBaseProposal, Terms } from "pwn/periphery/proposal/PWNBaseProposal.sol";


contract PWNBaseProposalHarness is PWNBaseProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        string memory name,
        string memory version
    ) PWNBaseProposal(_hub, _revokedNonce, _config, _utilizedCredit, name, version) {}


    function exposed_getProposalHash(
        bytes32 proposalTypehash,
        bytes memory encodedProposal
    ) external view returns (bytes32) {
        return _getProposalHash(proposalTypehash, encodedProposal);
    }

    function exposed_makeProposal(bytes32 proposalHash, address proposer) external {
        _makeProposal(proposalHash, proposer);
    }

    function exposed_checkProposal(
        CheckInputs memory inputs,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) external {
        _checkProposal(inputs, proposalInclusionProof, signature);
    }

    function acceptProposal(
        address, bytes calldata, bytes32[] calldata, bytes calldata
    ) external pure returns (Terms memory) {
        revert("This function is not implemented in the harness.");
    }

}
