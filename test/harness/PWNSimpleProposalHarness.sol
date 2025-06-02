// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNSimpleProposal
} from "pwn/periphery/proposal/PWNSimpleProposal.sol";


contract PWNSimpleProposalHarness is PWNSimpleProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule
    ) PWNSimpleProposal(_hub, _revokedNonce, _config, _utilizedCredit, _interestModule, _defaultModule) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
