// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";

/**
 * @title PWNDurationDefaultModule
 * @notice Default module for PWNLoan contracts that marks a loan as defaulted after a specified duration from origination.
 *
 * @dev This module allows each loan to have a custom default duration set at origination. The loan is considered in default
 * if the current block timestamp is greater than or equal to the calculated default timestamp (origination + duration).
 * The module enforces a minimum duration for the default period and validates proposer data. Implements the IPWNDefaultModule interface
 * and must be initialized via the onLoanCreated hook.
 */
contract PWNDurationDefaultModule is IPWNDefaultModule {

    /** @notice The minimum allowed duration (in seconds) for the default period.*/
    uint256 public constant MIN_DURATION = 10 minutes;

    /** @notice The PWNHub contract used for access control.*/
    PWNHub public immutable hub;

    /**
     * @notice Struct containing proposer data for loan initialization.
     * @param duration The duration (in seconds) after origination until the loan is considered in default.
     */
    struct ProposerData {
        uint256 duration;
    }

    /** @notice Mapping of loan contract address and loan ID to the default timestamp for each loan.*/
    mapping (address => mapping(uint256 => uint256)) public defaultTimestamp;

    /** @notice Thrown when the provided PWNHub address is zero in the constructor.*/
    error HubZeroAddress();
    /** @notice Thrown when the caller is not an active loan contract registered in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when the loan has already been initialized with a default timestamp.*/
    error LoanAlreadyInitialized();
    /** @notice Thrown when the proposer data length is not equal to encoded ProposerData size.*/
    error InvalidProposerDataLength();
    /** @notice Thrown when the duration is less than the minimum allowed duration.*/
    error DurationTooShort();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    /**
     * @notice Initializes the default module for a specific loan at origination.
     * @dev Sets the default timestamp for the loan using proposer data. Only callable by an active loan contract registered in the hub.
     * @param loanId The unique identifier of the loan being created.
     * @param proposerData ABI-encoded proposer data containing the duration value.
     * @return The keccak256 hash of "PWNDefaultModule.onLoanCreated" to confirm successful initialization.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (proposerData.length != 32) revert InvalidProposerDataLength();
        if (defaultTimestamp[msg.sender][loanId] != 0) revert LoanAlreadyInitialized();

        uint256 duration = abi.decode(proposerData, (uint256));
        if (duration < MIN_DURATION) revert DurationTooShort();

        defaultTimestamp[msg.sender][loanId] = block.timestamp + duration;

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Returns whether the loan is currently in default.
     * @dev The loan is considered in default if the current block timestamp is greater than or equal to the default timestamp.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return True if the loan is in default, false otherwise.
     */
    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool) {
        return defaultTimestamp[loanContract][loanId] <= block.timestamp;
    }

}
