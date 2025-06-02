// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";


contract PWNDateDefaultModule is IPWNDefaultModule {

    uint256 public constant MIN_DURATION = 10 minutes;

    PWNHub public immutable hub;

    struct ProposerData {
        uint256 defaultTimestamp;
    }

    mapping (address => mapping(uint256 => uint256)) public defaultTimestamp;

    error HubZeroAddress();
    error CallerNotActiveLoan();
    error PastDefaultTimestamp();
    error DurationTooShort();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        if (proposer.defaultTimestamp < block.timestamp) revert PastDefaultTimestamp();
        if (proposer.defaultTimestamp - block.timestamp < MIN_DURATION) revert DurationTooShort();

        defaultTimestamp[msg.sender][loanId] = proposer.defaultTimestamp;

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool) {
        return defaultTimestamp[loanContract][loanId] >= block.timestamp;
    }

}
