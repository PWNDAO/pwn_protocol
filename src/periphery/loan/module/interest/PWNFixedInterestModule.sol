// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";

/**
 * @title PWNFixedInterestModule
 * @notice Interest module for PWNLoan contracts with a fixed interest for a set period, then increasing APR after fixation.
 *
 * @dev This module allows each loan to have a fixed interest for a specified fixation period.
 * The interest for this period is determined at origination and does not depend on when the borrower
 * repays the loan. Repaying early or late within the fixation period results in the same interest amount.
 * After the fixation period ends, new interest starts accruing, and the APR increases by 1% every day.
 *
 * Implements the IPWNInterestModule interface and must be initialized via the onLoanCreated hook.
 */
contract PWNFixedInterestModule is IPWNInterestModule {
    using Math for uint256;
    using SafeCast for uint256;

    /** @notice Number of decimals for APR precision (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant APR_DECIMALS = 4;

    uint256 public constant DAILY_APR_INCREASE = 100; // 1%

    /** @notice The PWNHub contract used for access control.*/
    PWNHub public immutable hub;

    /**
     * @notice Struct containing proposer data for loan initialization.
     * @param apr The annual percentage rate (APR) to be set for the loan, with APR_DECIMALS decimals.
     * @param fixationPeriod The duration (in seconds) for which the APR is fixed.
     */
    struct ProposerData {
        uint256 apr;
        uint256 fixationPeriod;
    }

    /**
     * @notice Struct containing interest data for each loan.
     * @param loanStart The timestamp when the loan started.
     * @param fixationDeadline The timestamp when the fixation period ends.
     * @param apr The APR set for the loan, with APR_DECIMALS decimals.
     */
    struct InterestData {
        uint40 loanStart;
        uint40 fixationDeadline;
        uint24 apr;
    }

    /** @notice Mapping of loan contract address and loan ID to the interest data for each loan.*/
    mapping (address => mapping(uint256 => InterestData)) internal _interestData;

    /** @notice Thrown when the provided PWNHub address is zero in the constructor.*/
    error HubZeroAddress();
    /** @notice Thrown when the caller is not an active loan contract registered in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when the loan has already been initialized with an APR.*/
    error LoanAlreadyInitialized();
    /** @notice Thrown when the proposer data length is not equal to encoded ProposerData size.*/
    error InvalidProposerDataLength();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    /**
     * @notice Initializes the interest module for a specific loan at origination.
     * @dev Sets the APR and fixation period for the loan using proposer data. Only callable by an active loan contract registered in the hub.
     * @param loanId The unique identifier of the loan being created.
     * @param proposerData ABI-encoded proposer data containing the APR and fixation period values.
     * @return The keccak256 hash of "PWNInterestModule.onLoanCreated" to confirm successful initialization.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (proposerData.length != 64) revert InvalidProposerDataLength();
        (uint256 apr, uint256 period) = abi.decode(proposerData, (uint256, uint256));

        InterestData storage data = _interestData[msg.sender][loanId];
        if (data.loanStart != 0) revert LoanAlreadyInitialized();

        data.loanStart = block.timestamp.toUint40();
        data.fixationDeadline = (block.timestamp + period).toUint40();
        data.apr = apr.toUint24();

        return INTEREST_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Calculates the interest accrued for a loan since its last update.
     * @dev Uses the stored APR and principal to compute interest linearly per second since the last update timestamp.
     * After the fixation period, APR increases by 1% per day.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return The amount of interest accrued since the last update timestamp.
     */
    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        if (block.timestamp < loan.lastUpdateTimestamp) return 0;

        InterestData memory data = _interestData[loanContract][loanId];

        uint256 interest_;
        if (data.loanStart == loan.lastUpdateTimestamp) {
            interest_ = _interestForDuration(loan.principal, data.apr, data.fixationDeadline - data.loanStart);
        }

        // Increase APR by 1% every overtime day
        if (block.timestamp > data.fixationDeadline) {
            uint256 overtime = block.timestamp - data.fixationDeadline;
            uint256 endIndex = overtime / 1 days;
            for (uint256 i; i <= endIndex; ++i) {
                interest_ += _interestForDuration({
                    principal: loan.principal,
                    apr: data.apr + i * DAILY_APR_INCREASE,
                    duration: i == endIndex ? overtime % 1 days : 1 days
                });
            }
        }
        if (loan.lastUpdateTimestamp > data.fixationDeadline) {
            uint256 beforeUpdate = loan.lastUpdateTimestamp - data.fixationDeadline;
            uint256 endIndex = beforeUpdate / 1 days;
            for (uint256 i; i <= endIndex; ++i) {
                interest_ -= _interestForDuration({
                    principal: loan.principal,
                    apr: data.apr + i * DAILY_APR_INCREASE,
                    duration: i == endIndex ? beforeUpdate % 1 days : 1 days
                });
            }
        }

        return interest_;
    }

    /**
     * @notice Returns the APR and fixation deadline for a given loan.
     * @dev Provides external access to the interest parameters for a specific loan.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return apr The APR value for the specified loan, with APR_DECIMALS decimals.
     * @return fixationDeadline The timestamp when the fixation period ends for the specified loan.
     */
    function interestData(address loanContract, uint256 loanId) external view returns (uint256, uint256) {
        InterestData storage data = _interestData[loanContract][loanId];
        return (data.apr, data.fixationDeadline);
    }


    /**
     * @notice Internal function to calculate interest for a given duration.
     * @param principal The principal amount of the loan.
     * @param apr The APR to use for the calculation.
     * @param duration The duration in seconds for which to calculate interest.
     * @return The interest accrued for the given duration.
     */
    function _interestForDuration(uint256 principal, uint256 apr, uint256 duration) internal pure returns (uint256) {
        return principal.mulDiv(apr * duration, 365 days * 10 ** APR_DECIMALS);
    }

}
