// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Ownable2Step } from "openzeppelin/access/Ownable2Step.sol";

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
contract PWNCompoundLenderHook is Ownable2Step, IPWNLenderCreateHook, IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;

    /**
     * @notice Struct containing the pool address for the hook.
     * @param pool The Compound pool address.
     */
    struct HookData {
        address pool;
    }

    /** @notice Mapping to track if an address is a valid Compound pool.*/
    mapping (address => bool) public isPool;

    /** @notice Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
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
    /** @notice Thrown when the lender data length is invalid.*/
    error InvalidLenderDataLength();
    /** @notice Thrown when the pool address is invalid.*/
    error InvalidPoolAddress();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
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
        if (lenderData.length != 32) revert InvalidLenderDataLength();
        address pool = abi.decode(lenderData, (address));

        if (!isPool[pool]) revert InvalidPoolAddress();

        // Withdraw from the pool to the owner
        ICometLike(pool).withdrawFrom(lender, lender, creditAddress, principal);

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
        if (lenderData.length != 32) revert InvalidLenderDataLength();
        address pool = abi.decode(lenderData, (address));

        if (!isPool[pool]) revert InvalidPoolAddress();

        // Supply to the pool on behalf of the owner
        creditAddress.ERC20(repayment).approveAsset(pool);
        ICometLike(pool).supplyFrom(address(this), lender, creditAddress, repayment);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Sets if an address is a Compound pool address.
     * @param pool The Compound pool address to set.
     * @param _isPool Whether the address is pool or not.
     */
    function setIsPool(address pool, bool _isPool) external onlyOwner {
        isPool[pool] = _isPool;
    }

}
