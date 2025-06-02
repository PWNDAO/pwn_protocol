// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNFixedPeriodInterestModule is IPWNInterestModule {
    using Math for uint256;
    using SafeCast for uint256;

    uint256 public constant APR_DECIMALS = 4; // 6231 = 0.6231 = 62.31%

    PWNHub public immutable hub;

    struct ProposerData {
        uint256 apr;
        uint256 fixationPeriod;
    }

    struct InterestData {
        uint152 fixedInterest;
        uint40 loanStart;
        uint40 fixationDeadline;
        uint24 apr;
    }

    mapping (address => mapping(uint256 => InterestData)) internal _interestData;

    error HubZeroAddress();
    error CallerNotActiveLoan();
    error InvalidLastUpdateTimestamp();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        PWNLoan.LOAN memory loan = PWNLoan(msg.sender).getLOAN(loanId);

        _interestData[msg.sender][loanId] = InterestData({
            fixedInterest: _interestForDuration(loan.principal, proposer.apr, proposer.fixationPeriod).toUint152(),
            loanStart: block.timestamp.toUint40(),
            fixationDeadline: (block.timestamp + proposer.fixationPeriod).toUint40(),
            apr: proposer.apr.toUint24()
        });

        return INTEREST_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);
        InterestData storage interestData = _interestData[loanContract][loanId];

        if (block.timestamp < loan.lastUpdateTimestamp) revert InvalidLastUpdateTimestamp();

        uint256 interest_;
        if (interestData.loanStart == loan.lastUpdateTimestamp) {
            interest_ = interestData.fixedInterest;
        }

        // Increase APR by 1% every overtime day
        if (block.timestamp > interestData.fixationDeadline) {
            uint256 apr = interestData.apr;
            uint256 aprIncrease = 10 ** (APR_DECIMALS / 2); // 1%
            uint256 overtime = block.timestamp - interestData.fixationDeadline;
            uint256 overtimeDays = overtime / 1 days;
            for (uint256 i; i < overtimeDays; ++i) {
                interest_ += _interestForDuration(loan.principal, apr + i * aprIncrease, 1 days);
            }
            uint256 overtimeLast = overtime % 1 days;
            interest_ += _interestForDuration(loan.principal, apr + overtimeDays * aprIncrease, overtimeLast);
        }

        return interest_;
    }


    function _interestForDuration(uint256 principal, uint256 apr, uint256 duration) internal pure returns (uint256) {
        uint256 accruingMinutes = duration / 1 minutes;
        return principal.mulDiv(apr * accruingMinutes, 10 ** APR_DECIMALS) - principal;
    }

}
