// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNUniswapV3LPIndividualProposal
} from "pwn/periphery/proposal/PWNUniswapV3LPIndividualProposal.sol";


contract PWNUniswapV3LPIndividualProposalHarness is PWNUniswapV3LPIndividualProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule,
        address _liquidationModule,
        address _uniswapV3Factory,
        address _uniswapNFTPositionManager,
        address _chainlinkFeedRegistry,
        address _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNUniswapV3LPIndividualProposal(
        _hub,
        _revokedNonce,
        _config,
        _utilizedCredit,
        _interestModule,
        _defaultModule,
        _liquidationModule,
        _uniswapV3Factory,
        _uniswapNFTPositionManager,
        _chainlinkFeedRegistry,
        _chainlinkL2SequencerUptimeFeed,
        _weth
    ) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
