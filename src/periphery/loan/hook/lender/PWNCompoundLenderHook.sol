// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderCreateHook.sol";
import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";
import { ICometLike } from "pwn/periphery/interfaces/ICometLike.sol";


/**
 * @title PWNCompoundLenderHook
 * @notice Allows Compound users to commit their funds to PWN loans, enabling on-demand withdrawal and repayment through the protocol's hooks.
 * @dev On loan creation, withdraws principal from Compound to the lender. On repayment, supplies repayment into Compound for the lender.
 */
contract PWNCompoundLenderHook is IPWNLenderCreateHook, IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;
    /** @notice Reference to the Compound lending pool contract.*/
    ICometLike public immutable pool;

    /** @notice Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
    /** @notice Thrown when the provided pool address is zero.*/
    error PoolZeroAddress();
    /** @notice Thrown when the caller does not have the ACTIVE_LOAN tag in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when the lender address is zero.*/
    error LenderZeroAddress();
    /** @notice Thrown when the credit asset address is zero.*/
    error CreditZeroAddress();
    /** @notice Thrown when the principal amount is zero.*/
    error PrincipalZero();
    /** @notice Thrown when the repayment amount is zero.*/
    error RepaymentZero();
    /** @notice Thrown when the lender data is not empty.*/
    error DataNotEmpty();


    constructor(PWNHub _hub, ICometLike _pool) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        if (address(_pool) == address(0)) revert PoolZeroAddress();

        hub = _hub;
        pool = _pool;
    }


    /**
     * @notice Called on loan creation to withdraw principal from Compound to the lender.
     * @dev Withdraws from the pool to the lender.
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

        // Withdraw from the pool to the owner
        pool.withdrawFrom(lender, lender, creditAddress, principal);

        return LENDER_CREATE_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Called on loan repayment to supply repayment into Compound for the lender.
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
        pool.supplyFrom(address(this), lender, creditAddress, repayment);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}
