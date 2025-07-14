// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { Chainlink, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike } from "pwn/periphery/lib/Chainlink.sol";
import { encodeChainlinkPriceFeedData, decodeChainlinkPriceFeedData } from "pwn/periphery/utils/chainlinkUtils.sol";


/**
 * @title PWNOpenLiquidationModule
 * @notice Liquidation module allowing anyone to liquidate a defaulted loan by repaying the full debt.
 * @dev The liquidator repays the full debt in the credit asset and receives the collateral. No extra data is allowed.
 */
contract PWNOpenLiquidationModule is IPWNLiquidationModule {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;
    using Math for uint256;
    using Chainlink for Chainlink.Config;

    /** @notice Maximum number of intermediary denominations allowed for Chainlink feed conversion.*/
    uint256 public constant MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice The maximum allowed liquidation penalty (in basis points, e.g., 3000 = 30%).*/
    uint256 public constant MAX_LIQUIDATION_PENALTY = 3000; // 30% penalty
    /** @notice Number of decimals for the liquidation penalty (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant LIQUIDATION_PENALTY_DECIMALS = 4;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;

    /** @dev Chainlink configuration struct for price feed operations.*/
    Chainlink.Config internal _chainlink;

    /**
     * @notice Struct containing proposer data for liquidation logic.
     * @param liquidationPenalty Liquidation penalty (scaled by LIQUIDATION_PENALTY_DECIMALS).
     * @param feedIntermediaryDenominations Array of intermediary denominations for Chainlink feed conversion.
     * @param feedInvertFlags Array of flags indicating if the feed should be inverted at each step.
     */
    struct ProposerData {
        uint256 liquidationPenalty;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    /**
     * @notice Struct containing data required for liquidation logic based on Chainlink value.
     * @param liquidationPenalty Liquidation penalty (scaled by LIQUIDATION_PENALTY_DECIMALS).
     * @param feedData Custom encoded data required to query the Chainlink price feed. Always encoded as 1 byte of inverted flag and 20 bytes of intermediary denomination address per step.
     */
    struct LiquidationData {
        uint256 liquidationPenalty;
        bytes feedData;
    }

    /** @notice Mapping of loan contract and loan id to proposer data for liquidation logic.*/
    mapping (address => mapping(uint256 => LiquidationData)) internal _liquidationData;

    /** @notice Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
    /** @notice Thrown when the provided Chainlink feed registry address is zero.*/
    error ChainlinkFeedRegistryZeroAddress();
    /** @notice Thrown when the provided WETH address is zero.*/
    error WethZeroAddress();
    /** @notice Thrown when the caller does not have the ACTIVE_LOAN tag in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when a loan is already initialized in this module.*/
    error LoanAlreadyInitialized();
    /** @notice Thrown when the collateral category is not ERC20.*/
    error UnsupportedCollateral();
    /** @notice Thrown when the liquidation data is not empty.*/
    error LiquidationDataNotEmpty();
    /** @notice Thrown when the provided liquidation penalty is invalid (zero or above max).*/
    error InvalidLiquidationPenalty();
    /** @notice Thrown when liquidated loan is not initialized in this module.*/
    error LoanNotInitialized();


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


    /**
     * @notice Initialization hook for the liquidation module, called on loan creation.
     * @dev Always returns the expected hook return value. No initialization logic is required.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (_liquidationData[msg.sender][loanId].feedData.length != 0) revert LoanAlreadyInitialized();

        PWNLoan.LOAN memory loan = PWNLoan(msg.sender).getLOAN(loanId);
        if (loan.collateral.category != MultiToken.Category.ERC20) revert UnsupportedCollateral();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        if (proposer.liquidationPenalty == 0 || proposer.liquidationPenalty > MAX_LIQUIDATION_PENALTY)
            revert InvalidLiquidationPenalty();

        _liquidationData[msg.sender][loanId] = LiquidationData({
            liquidationPenalty: proposer.liquidationPenalty,
            feedData: encodeChainlinkPriceFeedData(
                proposer.feedInvertFlags,
                proposer.feedIntermediaryDenominations,
                MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS
            )
        });

        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Allows anyone to liquidate a defaulted loan by repaying the full debt and claiming the collateral.
     * @dev The liquidator must repay the full debt in the credit asset. The liquidation data must be empty.
     * @inheritdoc IPWNLiquidationModule
     */
    function liquidate(
        uint256 loanId,
        address liquidator,
        address borrower,
        uint256 debt,
        address creditAddress,
        MultiToken.Asset calldata collateral,
        bytes calldata data
    ) external returns (uint256) {
        if (data.length != 0) revert LiquidationDataNotEmpty();

        LiquidationData memory liqData = _liquidationData[msg.sender][loanId];
        if (liqData.feedData.length == 0) revert LoanNotInitialized();

        (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations)
            = decodeChainlinkPriceFeedData(liqData.feedData);

        // Cover debt
        MultiToken.Asset memory credit = creditAddress.ERC20(debt);
        credit.transferAssetFrom(liquidator, address(this));
        credit.approveAsset(msg.sender);

        // Transfer surplus to borrower
        uint256 collateralLiquidationValue = _chainlink.convertDenomination({
            amount: collateral.amount,
            oldDenomination: collateral.assetAddress,
            newDenomination: creditAddress,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        }).mulDiv(
            10 ** LIQUIDATION_PENALTY_DECIMALS - liqData.liquidationPenalty,
            10 ** LIQUIDATION_PENALTY_DECIMALS
        );
        if (collateralLiquidationValue > debt) {
            credit.amount = collateralLiquidationValue - debt;
            credit.transferAssetFrom(liquidator, borrower);
        }

        // Transfer collateral to liquidator
        collateral.transferAssetFrom(address(this), liquidator);

        return debt;
    }

}
