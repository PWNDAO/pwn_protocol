// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, Asset } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderCreateHook.sol";
import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";
import { IAaveLike } from "pwn/periphery/interfaces/IAaveLike.sol";


/**
 * @title PWNAaveLenderHook
 * @notice Enables PWN users to commit their Aave deposits, allowing them to be utilized on-demand for loan principal and repayment flows.
 * @dev On loan creation, withdraws principal from Aave to the lender. On repayment, supplies repayment into Aave for the lender.
 */
contract PWNAaveLenderHook is IPWNLenderCreateHook, IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for Asset;

    /** @notice Minimum health factor required for the lender after withdrawal (scaled by 1e18).*/
    uint256 public constant MIN_HEALTH_FACTOR = 1.2e18;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;
    /** @notice Reference to the Aave lending pool contract.*/
    IAaveLike public immutable pool;

    /** @dev Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
    /** @dev Thrown when the provided pool address is zero.*/
    error PoolZeroAddress();
    /** @dev Thrown when the caller does not have the ACTIVE_LOAN tag in the hub.*/
    error CallerNotActiveLoan();
    /** @dev Thrown when the lender address is zero.*/
    error LenderZeroAddress();
    /** @dev Thrown when the credit asset address is zero.*/
    error CreditZeroAddress();
    /** @dev Thrown when the principal amount is zero.*/
    error PrincipalZero();
    /** @dev Thrown when the repayment amount is zero.*/
    error RepaymentZero();
    /** @dev Thrown when the lender data is empty.*/
    error DataNotEmpty();
    /** @dev Thrown when the lender's health factor is below the minimum required after withdrawal.*/
    error HealthFactorBelowMin(uint256 healthFactor, uint256 minHealthFactor);


    constructor(PWNHub _hub, IAaveLike _pool) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        if (address(_pool) == address(0)) revert PoolZeroAddress();

        hub = _hub;
        pool = _pool;
    }

    /**
     * @notice Called on loan creation to withdraw principal from Aave to the lender.
     * @dev Checks minimum health factor. Transfers aTokens from lender, checks health, and withdraws from pool.
     * @inheritdoc IPWNLenderCreateHook
     */
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
        if (lenderData.length != 0) revert DataNotEmpty();

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

    /**
     * @notice Called on loan repayment to supply repayment into Aave for the lender.
     * @dev Supplies repayment to the pool on behalf of the lender.
     * @inheritdoc IPWNLenderRepaymentHook
     */
    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (repayment == 0) revert RepaymentZero();
        if (lenderData.length != 0) revert DataNotEmpty();

        // Supply to the pool on behalf of the owner
        creditAddress.ERC20(repayment).approveAsset(address(pool));
        pool.supply(creditAddress, repayment, lender, 0);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}
