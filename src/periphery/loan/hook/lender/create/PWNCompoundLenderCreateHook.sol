// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderCreateHook.sol";
import { ICometLike } from "pwn/periphery/interfaces/ICometLike.sol";


contract PWNCompoundLenderCreateHook is IPWNLenderCreateHook {

    PWNHub public immutable hub;
    ICometLike public immutable pool;

    error HubZeroAddress();
    error PoolZeroAddress();
    error CallerNotActiveLoan();
    error LenderZeroAddress();
    error CreditZeroAddress();
    error PrincipalZero();
    error DataNotEmpty();
    error HealthFactorBelowMin(uint256 healthFactor, uint256 minHealthFactor);


    constructor(PWNHub _hub, ICometLike _pool) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        if (address(_pool) == address(0)) revert PoolZeroAddress();

        hub = _hub;
        pool = _pool;
    }


    function onLoanCreated(
        address lender,
        address creditAddress,
        uint256 principal,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (principal == 0) revert PrincipalZero();
        if (lenderData.length == 0) revert DataNotEmpty();

        // Withdraw from the pool to the owner
        pool.withdrawFrom(lender, lender, creditAddress, principal);

        return LENDER_CREATE_HOOK_RETURN_VALUE;
    }

}
