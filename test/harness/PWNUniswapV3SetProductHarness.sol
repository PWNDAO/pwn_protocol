// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNUniswapV3SetProduct,
    PWNHub,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    INonfungiblePositionManager,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/periphery/product/PWNUniswapV3SetProduct.sol";


contract PWNUniswapV3SetProductHarness is PWNUniswapV3SetProduct {

    constructor(
        PWNHub _hub,
        PWNRevokedNonce _revokedNonce,
        PWNUtilizedCredit _utilizedCredit,
        address _uniswapV3Factory,
        INonfungiblePositionManager _uniswapNFTPositionManager,
        IChainlinkFeedRegistryLike _chainlinkFeedRegistry,
        IChainlinkAggregatorLike _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNUniswapV3SetProduct(
        _hub,
        _revokedNonce,
        _utilizedCredit,
        _uniswapV3Factory,
        _uniswapNFTPositionManager,
        _chainlinkFeedRegistry,
        _chainlinkL2SequencerUptimeFeed,
        _weth
    ) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

    function workaround_updateApr(address loanContract, uint256 loanId, uint24 apr) external {
        loanData[loanContract][loanId].apr = apr;
    }

}
