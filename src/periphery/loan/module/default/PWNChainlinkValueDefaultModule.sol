// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { Chainlink, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike } from "pwn/periphery/lib/Chainlink.sol";


contract PWNChainlinkValueDefaultModule is IPWNDefaultModule {
    using Math for uint256;
    using SafeCast for uint256;
    using Chainlink for Chainlink.Config;

    uint256 public constant MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS = 4;
    uint256 public constant LLTV_DECIMALS = 4; // 6231 = 0.6231 = 62.31%

    PWNHub public immutable hub;

    Chainlink.Config internal _chainlink;

    struct ProposerData {
        uint256 lltv;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    struct DefaultData {
        uint256 lltv;
        // todo: optimize storage
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    mapping (address => mapping(uint256 => DefaultData)) internal _defaultData;

    error HubZeroAddress();
    error ChainlinkFeedRegistryZeroAddress();
    error WethZeroAddress();
    error CallerNotActiveLoan();
    error InvalidLLTV();


    constructor(
        PWNHub _hub,
        IChainlinkAggregatorLike chainlinkL2SequencerUptimeFeed,
        IChainlinkFeedRegistryLike chainlinkFeedRegistry,
        address weth
    ) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        if (address(chainlinkFeedRegistry) == address(0)) revert ChainlinkFeedRegistryZeroAddress();
        if (address(weth) == address(0)) revert WethZeroAddress();

        hub = _hub;
        _chainlink.l2SequencerUptimeFeed = chainlinkL2SequencerUptimeFeed;
        _chainlink.feedRegistry = chainlinkFeedRegistry;
        _chainlink.maxIntermediaryDenominations = MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS;
        _chainlink.weth = weth;
    }


    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));

        if (proposer.lltv > 10 ** LLTV_DECIMALS) revert InvalidLLTV();

        _defaultData[msg.sender][loanId] = DefaultData({
            lltv: proposer.lltv.toUint248(),
            feedIntermediaryDenominations: proposer.feedIntermediaryDenominations,
            feedInvertFlags: proposer.feedInvertFlags
        });

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    function isDefaulted(address loanContract, uint256 loanId) public view returns (bool) {
        DefaultData storage defaultData = _defaultData[loanContract][loanId];
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        uint256 value = _chainlink.convertDenomination({
            amount: loan.collateral.amount,
            oldDenomination: loan.collateral.assetAddress,
            newDenomination: loan.creditAddress,
            feedIntermediaryDenominations: defaultData.feedIntermediaryDenominations,
            feedInvertFlags: defaultData.feedInvertFlags
        });

        return PWNLoan(loanContract).getLOANDebt(loanId) >= value.mulDiv(defaultData.lltv, 10 ** LLTV_DECIMALS);
    }

}
