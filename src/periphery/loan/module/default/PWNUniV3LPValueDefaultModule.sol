// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { UniswapV3, INonfungiblePositionManager } from "pwn/periphery/lib/UniswapV3.sol";
import { Chainlink, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike } from "pwn/periphery/lib/Chainlink.sol";


contract PWNUniV3LPValueDefaultModule is IPWNDefaultModule {
    using Math for uint256;
    using SafeCast for uint256;
    using UniswapV3 for UniswapV3.Config;
    using Chainlink for Chainlink.Config;

    uint256 public constant MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS = 4;
    uint256 public constant LLTV_DECIMALS = 4; // 6231 = 0.6231 = 62.31%

    PWNHub public immutable hub;

    UniswapV3.Config internal _uniswap;
    Chainlink.Config internal _chainlink;

    struct ProposerData {
        uint256 lltv;
        bool token0Denominator;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    struct DefaultData {
        uint248 lltv;
        bool token0Denominator;
        // todo: optimize storage
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    mapping (address => mapping(uint256 => DefaultData)) internal _defaultData;

    error HubZeroAddress();
    error UniswapV3PositionManagerZeroAddress();
    error UniswapV3FactoryZeroAddress();
    error ChainlinkFeedRegistryZeroAddress();
    error WethZeroAddress();
    error CallerNotActiveLoan();
    error InvalidLLTV();


    constructor(
        PWNHub _hub,
        INonfungiblePositionManager uniswapV3PositionManager,
        address uniswapV3Factory,
        IChainlinkAggregatorLike chainlinkL2SequencerUptimeFeed,
        IChainlinkFeedRegistryLike chainlinkFeedRegistry,
        address weth
    ) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        if (address(uniswapV3PositionManager) == address(0)) revert UniswapV3PositionManagerZeroAddress();
        if (address(uniswapV3Factory) == address(0)) revert UniswapV3FactoryZeroAddress();
        if (address(chainlinkFeedRegistry) == address(0)) revert ChainlinkFeedRegistryZeroAddress();
        if (address(weth) == address(0)) revert WethZeroAddress();

        hub = _hub;
        _uniswap.positionManager = uniswapV3PositionManager;
        _uniswap.factory = uniswapV3Factory;
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
            token0Denominator: proposer.token0Denominator,
            feedIntermediaryDenominations: proposer.feedIntermediaryDenominations,
            feedInvertFlags: proposer.feedInvertFlags
        });

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    function isDefaulted(address loanContract, uint256 loanId) public view returns (bool) {
        DefaultData storage defaultData = _defaultData[loanContract][loanId];
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);
        (uint256 lpValue, address denominator) = _uniswap.getLPValue(loanId, defaultData.token0Denominator);

        if (loan.creditAddress != denominator) {
            lpValue = _chainlink.convertDenomination({
                amount: lpValue,
                oldDenomination: denominator,
                newDenomination: loan.creditAddress,
                feedIntermediaryDenominations: defaultData.feedIntermediaryDenominations,
                feedInvertFlags: defaultData.feedInvertFlags
            });
        }

        return PWNLoan(loanContract).getLOANDebt(loanId) >= lpValue.mulDiv(defaultData.lltv, 10 ** LLTV_DECIMALS);
    }

}
