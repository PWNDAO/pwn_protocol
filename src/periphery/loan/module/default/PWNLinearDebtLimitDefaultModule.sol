// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNLinearDebtLimitDefaultModule is IPWNDefaultModule {
    using Math for uint256;
    using SafeCast for uint256;

    uint256 public constant MIN_DURATION = 10 minutes;
    uint256 public constant DEBT_LIMIT_TANGENT_DECIMALS = 8;

    PWNHub public immutable hub;

    struct ProposerData {
        uint256 postponement;
        uint256 duration;
    }

    struct DefaultData {
        uint40 defaultTimestamp;
        uint216 debtLimitTangent;
    }

    mapping (address => mapping(uint256 => DefaultData)) internal _defaultData;

    error HubZeroAddress();
    error CallerNotActiveLoan();
    error DurationTooShort();
    error PostponementBiggerThanDuration();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        if (proposer.duration < MIN_DURATION) revert DurationTooShort();
        if (proposer.duration < proposer.postponement) revert PostponementBiggerThanDuration();

        uint256 debt = PWNLoan(msg.sender).getLOANDebt(loanId);
        _defaultData[msg.sender][loanId] = DefaultData({
            defaultTimestamp: (block.timestamp + proposer.duration).toUint40(),
            debtLimitTangent: debt.mulDiv(10 ** DEBT_LIMIT_TANGENT_DECIMALS, proposer.duration - proposer.postponement).toUint216()
        });

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool) {
        DefaultData memory defaultData = _defaultData[loanContract][loanId];

        if (block.timestamp >= defaultData.defaultTimestamp) return true;

        uint256 debtLimit = uint256(defaultData.debtLimitTangent).mulDiv(
            uint256(defaultData.defaultTimestamp) - block.timestamp, 10 ** DEBT_LIMIT_TANGENT_DECIMALS
        );
        return PWNLoan(loanContract).getLOANDebt(loanId) >= debtLimit;
    }

}
