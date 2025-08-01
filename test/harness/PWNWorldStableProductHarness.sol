// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNWorldStableProduct,
    PWNHub,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike,
    IWorldID
} from "pwn/periphery/product/PWNWorldStableProduct.sol";


contract PWNWorldStableProductHarness is PWNWorldStableProduct {

    constructor(
        PWNHub _hub,
        PWNRevokedNonce _revokedNonce,
        PWNUtilizedCredit _utilizedCredit,
        IChainlinkFeedRegistryLike _chainlinkFeedRegistry,
        IChainlinkAggregatorLike _chainlinkL2SequencerUptimeFeed,
        address _weth,
        IWorldID _worldId,
        string memory _appId,
        string memory _actionId
    ) PWNWorldStableProduct(
        _hub,
        _revokedNonce,
        _utilizedCredit,
        _chainlinkFeedRegistry,
        _chainlinkL2SequencerUptimeFeed,
        _weth,
        _worldId,
        _appId,
        _actionId
    ) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

    function workaround_updateApr(address loanContract, uint256 loanId, uint24 apr) external {
        loanData[loanContract][loanId].apr = apr;
    }

}
