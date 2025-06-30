// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNFixedTermsProposal } from "pwn/periphery/proposal/PWNFixedTermsProposal.sol";


contract PWNFixedTermsProposalHarness is PWNFixedTermsProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule,
        address _liquidationModule,
        address _chainlinkFeedRegistry,
        address _l2SequencerUptimeFeed,
        address _weth
    ) PWNFixedTermsProposal(
        _hub,
        _revokedNonce,
        _config,
        _utilizedCredit,
        _interestModule,
        _defaultModule,
        _liquidationModule,
        _chainlinkFeedRegistry,
        _l2SequencerUptimeFeed,
        _weth
    ) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
