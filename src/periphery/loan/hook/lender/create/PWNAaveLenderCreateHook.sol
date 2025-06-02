// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderCreateHook.sol";
import { IAaveLike } from "pwn/periphery/interfaces/IAaveLike.sol";


contract PWNAaveLenderCreateHook is IPWNLenderCreateHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    uint256 public constant MIN_HEALTH_FACTOR = 1.2e18;

    PWNHub public immutable hub;
    IAaveLike public immutable pool;

    error HubZeroAddress();
    error PoolZeroAddress();
    error CallerNotActiveLoan();
    error LenderZeroAddress();
    error CreditZeroAddress();
    error PrincipalZero();
    error DataNotEmpty();
    error HealthFactorBelowMin(uint256 healthFactor, uint256 minHealthFactor);


    constructor(PWNHub _hub, IAaveLike _pool) {
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

        // Transfer aTokens to this contract
        pool
            .getReserveData(creditAddress).aTokenAddress
            .ERC20(principal) // Note: Assuming aToken is minted in 1:1 ratio to the underlying asset
            .transferAssetFrom(lender, address(this));

        // Check owner health factor
        (,,,,, uint256 healthFactor) = pool.getUserAccountData(lender);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert HealthFactorBelowMin(healthFactor, MIN_HEALTH_FACTOR);
        }

        // Withdraw from the pool to the owner
        pool.withdraw(creditAddress, principal, lender);

        return LENDER_CREATE_HOOK_RETURN_VALUE;
    }

}
