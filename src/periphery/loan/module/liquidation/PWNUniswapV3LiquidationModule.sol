// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { UniswapV3, INonfungiblePositionManager } from "pwn/periphery/lib/UniswapV3.sol";
import { Chainlink, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike } from "pwn/periphery/lib/Chainlink.sol";
import { encodeChainlinkPriceFeedData, decodeChainlinkPriceFeedData } from "pwn/periphery/utils/chainlinkUtils.sol";


/**
 * @title PWNUniswapV3LiquidationModule
 * @dev This contract facilitates the liquidation process by interacting with Uniswap V3 pools,
 * allowing the conversion of collateral assets to repay outstanding loan amounts.
 */
contract PWNUniswapV3LiquidationModule is IPWNLiquidationModule {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;
    using SafeCast for uint256;
    using Math for uint256;
    using UniswapV3 for UniswapV3.Config;
    using Chainlink for Chainlink.Config;

    /** @notice Maximum number of intermediary denominations allowed for Chainlink feed conversion.*/
    uint256 public constant MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice The maximum allowed liquidation penalty (in basis points, e.g., 3000 = 30%).*/
    uint256 public constant MAX_LIQUIDATION_PENALTY = 3000; // 30% penalty
    /** @notice Number of decimals for the liquidation penalty (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant LIQUIDATION_PENALTY_DECIMALS = 4;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;

    /** @dev Uniswap V3 configuration struct for LP value operations.*/
    UniswapV3.Config internal _uniswap;
    /** @dev Chainlink configuration struct for price feed operations.*/
    Chainlink.Config internal _chainlink;

    /**
     * @notice Struct containing proposer data for liquidation logic.
     * @param liquidationPenalty Liquidation penalty (scaled by LIQUIDATION_PENALTY_DECIMALS).
     * @param token0Denominator Boolean indicating if the LP value should be denominated in token0 or token1.
     * @param feedIntermediaryDenominations Array of intermediary denominations for Chainlink feed conversion.
     * @param feedInvertFlags Array of flags indicating if the feed should be inverted at each step.
     */
    struct ProposerData {
        uint256 liquidationPenalty;
        bool token0Denominator;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    /**
     * @notice Struct containing data required for liquidation logic based on Chainlink value.
     * @param liquidationPenalty Liquidation penalty (scaled by LIQUIDATION_PENALTY_DECIMALS).
     * @param token0Denominator Boolean indicating if the LP value should be denominated in token0 or token1.
     * @param feedData Custom encoded data required to query the Chainlink price feed. Always encoded as 1 byte of inverted flag and 20 bytes of intermediary denomination address per step.
     */
    struct LiquidationData {
        uint248 liquidationPenalty;
        bool token0Denominator;
        bytes feedData;
    }

    /** @notice Mapping of loan contract and loan id to liquidation data for this module. */
    mapping (address => mapping(uint256 => LiquidationData)) internal _liquidationData;

    /** @notice Thrown when the provided hub address is zero.*/
    error HubZeroAddress();
    /** @notice Thrown when the provided Uniswap V3 position manager address is zero.*/
    error UniswapV3PositionManagerZeroAddress();
    /** @notice Thrown when the provided Uniswap V3 factory address is zero.*/
    error UniswapV3FactoryZeroAddress();
    /** @notice Thrown when the provided Chainlink feed registry address is zero.*/
    error ChainlinkFeedRegistryZeroAddress();
    /** @notice Thrown when the provided WETH address is zero.*/
    error WethZeroAddress();
    /** @notice Thrown when the caller does not have the ACTIVE_LOAN tag in the hub.*/
    error CallerNotActiveLoan();
    /** @notice Thrown when a loan is already initialized in this module.*/
    error LoanAlreadyInitialized();
    /** @notice Thrown when the collateral category is not Uniswap V3 LP.*/
    error UnsupportedCollateral();
    /** @notice Thrown when the liquidation data is not empty.*/
    error LiquidationDataNotEmpty();
    /** @notice Thrown when the provided liquidation penalty is invalid (zero or above max).*/
    error InvalidLiquidationPenalty();
    /** @notice Thrown when liquidated loan is not initialized in this module.*/
    error LoanNotInitialized();


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


    /**
     * @notice Initializes the liquidation module for a loan when the loan is created.
     * @dev Stores liquidation parameters for the loan. Only callable by a contract with ACTIVE_LOAN tag.
     * @param loanId The ID of the loan being initialized.
     * @param proposerData ABI-encoded ProposerData struct with liquidation parameters.
     * @return Return value required by the loan contract for module initialization.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (_liquidationData[msg.sender][loanId].liquidationPenalty != 0) revert LoanAlreadyInitialized();

        PWNLoan.LOAN memory loan = PWNLoan(msg.sender).getLOAN(loanId);
        if (loan.collateral.assetAddress != address(_uniswap.positionManager)) revert UnsupportedCollateral();
        if (loan.collateral.category != MultiToken.Category.ERC721) revert UnsupportedCollateral();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        if (proposer.liquidationPenalty == 0 || proposer.liquidationPenalty > MAX_LIQUIDATION_PENALTY)
            revert InvalidLiquidationPenalty();

        _liquidationData[msg.sender][loanId] = LiquidationData({
            liquidationPenalty: proposer.liquidationPenalty.toUint248(),
            token0Denominator: proposer.token0Denominator,
            feedData: encodeChainlinkPriceFeedData(
                proposer.feedInvertFlags,
                proposer.feedIntermediaryDenominations,
                MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS
            )
        });

        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Liquidate a loan by repaying the debt and seizing the Uniswap V3 LP collateral.
     * @dev Transfers collateral to the liquidator and any surplus to the borrower. Only callable by the loan contract.
     * @param loanId The ID of the loan to liquidate.
     * @param liquidator The address performing the liquidation.
     * @param borrower The address of the borrower whose loan is being liquidated.
     * @param debt The amount of debt to be repaid by the liquidator.
     * @param creditAddress The address of the credit token.
     * @param collateral The collateral asset (Uniswap V3 LP NFT).
     * @param data Additional data (must be empty for this module).
     * @return The amount of debt repaid (should equal the input debt).
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
        if (liqData.liquidationPenalty == 0) revert LoanNotInitialized();

        // Cover debt
        MultiToken.Asset memory credit = creditAddress.ERC20(debt);
        credit.transferAssetFrom(liquidator, address(this));
        credit.approveAsset(msg.sender);

        // Transfer surplus to borrower
        (uint256 lpValue, address denominator) = _uniswap.getLPValue(collateral.id, liqData.token0Denominator);
        if (creditAddress != denominator) {
            (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations)
                = decodeChainlinkPriceFeedData(liqData.feedData);

            lpValue = _chainlink.convertDenomination({
                amount: lpValue,
                oldDenomination: denominator,
                newDenomination: creditAddress,
                feedIntermediaryDenominations: feedIntermediaryDenominations,
                feedInvertFlags: feedInvertFlags
            });
        }
        uint256 collateralLiquidationValue = lpValue.mulDiv(
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
