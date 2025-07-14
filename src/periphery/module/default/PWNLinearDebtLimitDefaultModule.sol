// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";

/**
 * @title PWNLinearDebtLimitDefaultModule
 * @notice Default module for PWNLoan contracts that marks a loan as defaulted if the debt exceeds a linearly decreasing limit.
 *
 * @dev This module allows each loan to have a custom default duration and postponement set at origination. The loan is considered in default
 * if the current debt exceeds a linearly decreasing debt limit. The debt limit decreases from the initial debt to zero over the duration
 * minus postponement. Implements the IPWNDefaultModule interface and must be initialized via the onLoanCreated hook.
 */
contract PWNLinearDebtLimitDefaultModule is IPWNDefaultModule {
    using Math for uint256;
    using SafeCast for uint256;

    /** @notice The minimum allowed duration (in seconds) for the default period.*/
    uint256 public constant MIN_DURATION = 10 minutes;
    /** @notice Number of decimals for the debt limit tangent precision.*/
    uint256 public constant DEBT_LIMIT_TANGENT_DECIMALS = 8;

    /** @notice The PWNHub contract used for access control.*/
    PWNHub public immutable hub;

    /**
     * @notice Struct containing proposer data for loan initialization.
     * @param postponement The period (in seconds) before the debt limit starts decreasing.
     * @param duration The total duration (in seconds) until the loan is considered in default.
     */
    struct ProposerData {
        uint256 postponement;
        uint256 duration;
    }

    /**
     * @notice Struct containing default data for each loan.
     * @param defaultTimestamp The timestamp when the loan is considered in default due to time.
     * @param debtLimitTangent The tangent (slope) of the linearly decreasing debt limit.
     */
    struct DefaultData {
        uint40 defaultTimestamp;
        uint216 debtLimitTangent;
    }

    /** @notice Mapping of loan contract address and loan ID to the default data for each loan.*/
    mapping (address => mapping(uint256 => DefaultData)) public defaultData;

    /** @notice Thrown when the provided PWNHub address is zero in the constructor.*/
    error HubZeroAddress();
    /** @notice Thrown when the caller is not an active loan contract registered in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when the loan has already been initialized.*/
    error LoanAlreadyInitialized();
    /** @notice Thrown when the proposer data length is not equal to encoded ProposerData size.*/
    error InvalidProposerDataLength();
    /** @notice Thrown when the duration is less than the minimum allowed duration.*/
    error DurationTooShort();
    /** @notice Thrown when the postponement is greater than the duration.*/
    error PostponementBiggerThanDuration();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    /**
     * @notice Initializes the default module for a specific loan at origination.
     * @dev Sets the default timestamp and debt limit tangent for the loan using proposer data. Only callable by an active loan contract registered in the hub.
     * @param loanId The unique identifier of the loan being created.
     * @param proposerData ABI-encoded proposer data containing the postponement and duration values.
     * @return The keccak256 hash of "PWNDefaultModule.onLoanCreated" to confirm successful initialization.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (proposerData.length != 64) revert InvalidProposerDataLength();
        if (defaultData[msg.sender][loanId].defaultTimestamp != 0) revert LoanAlreadyInitialized();

        (uint256 postponement, uint256 duration) = abi.decode(proposerData, (uint256, uint256));
        if (duration < MIN_DURATION) revert DurationTooShort();
        if (duration <= postponement) revert PostponementBiggerThanDuration();

        uint256 debt = PWNLoan(msg.sender).getLOANDebt(loanId);
        defaultData[msg.sender][loanId] = DefaultData({
            defaultTimestamp: (block.timestamp + duration).toUint40(),
            debtLimitTangent: debt.mulDiv(10 ** DEBT_LIMIT_TANGENT_DECIMALS, duration - postponement).toUint216()
        });

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Returns whether the loan is currently in default.
     * @dev The loan is considered in default if the current debt exceeds the linearly decreasing debt limit.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return True if the loan is in default, false otherwise.
     */
    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool) {
        uint256 _debtLimit = debtLimit(loanContract, loanId);
        if (_debtLimit == 0) return true;

        return PWNLoan(loanContract).getLOANDebt(loanId) >= _debtLimit;
    }

    /**
     * @notice Returns the current debt limit for a loan.
     * @dev The debt limit decreases linearly from the initial debt to zero over the duration minus postponement.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return The current debt limit for the loan.
     */
    function debtLimit(address loanContract, uint256 loanId) public view returns (uint256) {
        DefaultData memory _defaultData = defaultData[loanContract][loanId];

        if (block.timestamp >= _defaultData.defaultTimestamp)
            return 0;

        return uint256(_defaultData.debtLimitTangent).mulDiv(
            uint256(_defaultData.defaultTimestamp) - block.timestamp, 10 ** DEBT_LIMIT_TANGENT_DECIMALS
        );
    }

}
