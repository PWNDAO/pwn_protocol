// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNInstallmentsProduct,
    PWNHub,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/periphery/product/PWNInstallmentsProduct.sol";


contract PWNInstallmentsProductHarness is PWNInstallmentsProduct {

    constructor(
        PWNHub _hub,
        PWNRevokedNonce _revokedNonce,
        PWNUtilizedCredit _utilizedCredit,
        IChainlinkFeedRegistryLike _chainlinkFeedRegistry,
        IChainlinkAggregatorLike _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNInstallmentsProduct(
        _hub,
        _revokedNonce,
        _utilizedCredit,
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

    function workaround_updateDefaultTimestamp(address loanContract, uint256 loanId, uint40 timestamp) external {
        loanData[loanContract][loanId].defaultTimestamp = timestamp;
    }

    function workaround_updateDebtLimitTangent(address loanContract, uint256 loanId, uint176 debtLimitTangent) external {
        loanData[loanContract][loanId].debtLimitTangent = debtLimitTangent;
    }

}
