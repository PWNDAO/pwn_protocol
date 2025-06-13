// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


/**
 * @title PWNStableInterestModule
 * @notice Stable interest module for PWNLoan contracts.
 *
 * @dev This module allows each loan to have a stable APR (annual percentage rate) set at origination.
 * Interest is accrued linearly over time based on the principal and the APR, and is calculated per minute.
 * The module stores the APR for each loan and calculates interest only for the period since the last update.
 * Implements the IPWNInterestModule interface and must be initialized via the onLoanCreated hook.
 */
contract PWNStableInterestModule is IPWNInterestModule {
    using Math for uint256;

    uint256 public constant APR_DECIMALS = 4; // 6231 = 0.6231 = 62.31%

    PWNHub public immutable hub;

    /**
     * @notice Struct containing proposer data for loan initialization.
     * @param apr The annual percentage rate (APR) to be set for the loan, with APR_DECIMALS precision.
     */
    struct ProposerData {
        uint256 apr;
    }

    /** @notice Mapping of loan contract address and loan ID to the APR value for each loan*/
    mapping (address => mapping(uint256 => uint256)) public apr;

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
     * @dev Sets the APR for the loan using proposer data. Only callable by an active loan contract registered in the hub.
     * @param loanId The unique identifier of the loan being created.
     * @param proposerData ABI-encoded proposer data containing the APR value.
     * @return The keccak256 hash of "PWNInterestModule.onLoanCreated" to confirm successful initialization.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (proposerData.length != 32) revert InvalidProposerDataLength();

        if (apr[msg.sender][loanId] != 0) revert LoanAlreadyInitialized();
        apr[msg.sender][loanId] = abi.decode(proposerData, (uint256));

        return INTEREST_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Calculates the interest accrued for a loan since its last update.
     * @dev Uses the stored APR and principal to compute interest linearly per minute since the last update timestamp.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return The amount of interest accrued since the last update timestamp.
     */
    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        if (block.timestamp < loan.lastUpdateTimestamp) return 0;

        return loan.principal.mulDiv(
            apr[loanContract][loanId].mulDiv(block.timestamp - loan.lastUpdateTimestamp, 365 days),
            10 ** APR_DECIMALS
        );
    }

}
