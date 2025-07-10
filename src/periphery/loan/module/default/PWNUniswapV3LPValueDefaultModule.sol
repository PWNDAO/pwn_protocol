// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { UniswapV3, INonfungiblePositionManager } from "pwn/periphery/lib/UniswapV3.sol";
import { Chainlink, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike } from "pwn/periphery/lib/Chainlink.sol";
import { encodeChainlinkPriceFeedData, decodeChainlinkPriceFeedData } from "pwn/periphery/utils/chainlinkUtils.sol";

/**
 * @title PWNUniswapV3LPValueDefaultModule
 * @notice Default module for PWN loans using Uniswap V3 LP token value and Chainlink feeds to determine default.
 * @dev Determines default by comparing the value of a Uniswap V3 LP position (converted to the credit asset denomination) to the loan debt, using a liquidation loan-to-value (LLTV) ratio and Chainlink feeds.
 */
contract PWNUniswapV3LPValueDefaultModule is IPWNDefaultModule {
    using Math for uint256;
    using SafeCast for uint256;
    using UniswapV3 for UniswapV3.Config;
    using Chainlink for Chainlink.Config;

    /** @notice Maximum number of intermediary denominations allowed for Chainlink feed conversion.*/
    uint256 public constant MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice Number of decimals for the LLTV ratio (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant LLTV_DECIMALS = 4;

    /** @notice Reference to the PWN Hub contract. */
    PWNHub public immutable hub;

    /** @dev Uniswap V3 configuration struct for LP value operations.*/
    UniswapV3.Config internal _uniswap;
    /** @dev Chainlink configuration struct for price feed operations.*/
    Chainlink.Config internal _chainlink;

    /**
     * @notice Struct containing proposer data for default logic.
     * @param lltv Liquidation loan-to-value ratio (scaled by LLTV_DECIMALS).
     * @param token0Denominator Boolean indicating if token0 is the denominator for LP value.
     * @param feedIntermediaryDenominations Array of intermediary denominations for Chainlink feed conversion.
     * @param feedInvertFlags Array of flags indicating if the feed should be inverted at each step.
     */
    struct ProposerData {
        uint256 lltv;
        bool token0Denominator;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    /**
     * @notice Struct containing default data for a loan.
     * @param lltv Liquidation loan-to-value ratio (scaled by LLTV_DECIMALS).
     * @param token0Denominator Boolean indicating if token0 is the denominator for LP value.
     * @param feedData Custom encoded data required to query the Chainlink price feed. Always encoded as 1 byte of inverted flag and 20 bytes of intermediary denomination address per step.
     */
    struct DefaultData {
        uint248 lltv;
        bool token0Denominator;
        bytes feedData;
    }

    /** @notice Mapping of loan contract and loan id to default data for default logic.*/
    mapping (address => mapping(uint256 => DefaultData)) internal _defaultData;

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
    /** @notice Thrown when the collateral category is not ERC20.*/
    error UnsupportedCollateral();
    /** @notice Thrown when the provided LLTV is invalid (zero or above 1.0).*/
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

    /**
     * @notice Initializes the default module for a loan on creation.
     * @dev Reverts if the caller is not an active loan, if already initialized, or if LLTV is invalid.
     * @param loanId The id of the loan being initialized.
     * @param proposerData ABI-encoded ProposerData struct containing LLTV and feed configuration.
     * @return The expected module initialization hook return value.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (_defaultData[msg.sender][loanId].lltv != 0) revert LoanAlreadyInitialized();

        PWNLoan.LOAN memory loan = PWNLoan(msg.sender).getLOAN(loanId);
        if (loan.collateral.category != MultiToken.Category.ERC721) revert UnsupportedCollateral();
        if (loan.collateral.assetAddress != address(_uniswap.positionManager)) revert UnsupportedCollateral();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        if (proposer.lltv > 10 ** LLTV_DECIMALS || proposer.lltv == 0) revert InvalidLLTV();

        (,, address token0, address token1,,,,,,,,) = _uniswap.positionManager.positions(loan.collateral.id);
        bytes memory encodedPriceFeedData = encodeChainlinkPriceFeedData(
            proposer.feedInvertFlags,
            proposer.feedIntermediaryDenominations,
            MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS
        );
        bool isCreditInPair = token0 == loan.creditAddress || token1 == loan.creditAddress;

        if (isCreditInPair && encodedPriceFeedData.length > 0) {
            revert Chainlink.ChainlinkInvalidInputLenghts();
        }

        _defaultData[msg.sender][loanId] = DefaultData({
            lltv: proposer.lltv.toUint248(),
            token0Denominator: proposer.token0Denominator,
            feedData: encodedPriceFeedData
        });

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Checks if a loan is defaulted based on the value of its Uniswap V3 LP collateral and the LLTV ratio.
     * @dev Uses Uniswap V3 and Chainlink feeds to convert LP value to the credit asset denomination and compares to debt.
     * @param loanContract The address of the loan contract.
     * @param loanId The id of the loan to check.
     * @return True if the loan is defaulted, false otherwise.
     */
    function isDefaulted(address loanContract, uint256 loanId) public view returns (bool) {
        DefaultData storage data = _defaultData[loanContract][loanId];
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        (uint256 lpValue, address denominator) = _uniswap.getLPValue(loan.collateral.id, data.token0Denominator);

        if (loan.creditAddress != denominator) {
            (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations)
                = decodeChainlinkPriceFeedData(data.feedData);

            lpValue = _chainlink.convertDenomination({
                amount: lpValue,
                oldDenomination: denominator,
                newDenomination: loan.creditAddress,
                feedIntermediaryDenominations: feedIntermediaryDenominations,
                feedInvertFlags: feedInvertFlags
            });
        }

        return PWNLoan(loanContract).getLOANDebt(loanId) >= lpValue.mulDiv(data.lltv, 10 ** LLTV_DECIMALS);
    }

    /**
     * @notice Get the default data for a given loan.
     * @param loanContract Address of the loan contract.
     * @param loanId Loan identifier.
     * @return lltv Liquidation loan-to-value ratio.
     * @return token0Denominator Boolean indicating if token0 is the denominator for LP value.
     * @return feedIntermediaryDenominations Intermediary denominations used in the price feed.
     * @return feedInvertFlags Flags indicating whether to invert the price feed for each denomination.
     */
    function defaultData(
        address loanContract,
        uint256 loanId
    ) external view returns (
        uint256 lltv,
        bool token0Denominator,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) {
        DefaultData storage data = _defaultData[loanContract][loanId];
        lltv = data.lltv;
        token0Denominator = data.token0Denominator;
        (feedInvertFlags, feedIntermediaryDenominations) = decodeChainlinkPriceFeedData(data.feedData);
    }

}
