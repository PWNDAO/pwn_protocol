// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNStableInterestModule is IPWNInterestModule {
    using Math for uint256;

    uint256 public constant APR_DECIMALS = 4; // 6231 = 0.6231 = 62.31%

    PWNHub public immutable hub;

    struct ProposerData {
        uint256 apr;
    }

    mapping (address => mapping(uint256 => uint256)) public apr;

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
        apr[msg.sender][loanId] = proposer.apr;

        return INTEREST_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        if (block.timestamp < loan.lastUpdateTimestamp) revert InvalidLastUpdateTimestamp();

        uint256 accruingMinutes = (block.timestamp - loan.lastUpdateTimestamp) / 1 minutes;
        return loan.principal.mulDiv(apr[loanContract][loanId] * accruingMinutes, 10 ** APR_DECIMALS);
    }

}
