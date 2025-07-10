// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { Chainlink, IChainlinkAggregatorLike, IChainlinkFeedRegistryLike } from "pwn/periphery/lib/Chainlink.sol";
import { encodeChainlinkPriceFeedData, decodeChainlinkPriceFeedData } from "pwn/periphery/utils/chainlinkUtils.sol";

/**
 * @title PWNChainlinkValueDefaultModule
 * @notice Default module for PWN loans that uses Chainlink price feeds to determine loan default based on collateral value.
 * @dev This module checks if a loan is defaulted by comparing the value of the collateral (converted to the credit asset denomination)
 * to the loan debt, using a liquidation loan-to-value (LLTV) ratio and Chainlink feeds.
 */
contract PWNChainlinkValueDefaultModule is IPWNDefaultModule {
    using Math for uint256;
    using Chainlink for Chainlink.Config;

    /** @notice Maximum number of intermediary denominations allowed for Chainlink feed conversion.*/
    uint256 public constant MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice Number of decimals for the LLTV ratio (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant LLTV_DECIMALS = 4;

    /** @notice Reference to the PWN Hub contract.*/
    PWNHub public immutable hub;

    /** @dev Chainlink configuration struct for price feed operations.*/
    Chainlink.Config internal _chainlink;

    /**
     * @notice Struct containing proposer data for default logic.
     * @param lltv Liquidation loan-to-value ratio (scaled by LLTV_DECIMALS).
     * @param feedIntermediaryDenominations Array of intermediary denominations for Chainlink feed conversion.
     * @param feedInvertFlags Array of flags indicating if the feed should be inverted at each step.
     */
    struct ProposerData {
        uint256 lltv;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
    }

    /**
     * @notice Struct containing data required for default logic based on Chainlink value.
     * @param lltv Liquidation loan-to-value ratio (scaled by LLTV_DECIMALS).
     * @param feedData Custom encoded data required to query the Chainlink price feed. Always encoded as 1 byte of inverted flag and 20 bytes of intermediary denomination address per step.
     */
    struct DefaultData {
        uint256 lltv;
        bytes feedData;
    }

    /** @notice Mapping of loan contract and loan id to proposer data for default logic.*/
    mapping (address => mapping(uint256 => DefaultData)) internal _defaultData;

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
    /** @notice Thrown when the provided LLTV is invalid (zero or above 1.0).*/
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

    /**
     * @notice Initializes the default module for a loan on creation.
     * @param loanId The id of the loan being initialized.
     * @param proposerData ABI-encoded ProposerData struct containing LLTV and feed configuration.
     * @return The expected module initialization hook return value.
     */
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();
        if (_defaultData[msg.sender][loanId].lltv != 0) revert LoanAlreadyInitialized();

        PWNLoan.LOAN memory loan = PWNLoan(msg.sender).getLOAN(loanId);
        if (loan.collateral.category != MultiToken.Category.ERC20) revert UnsupportedCollateral();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        if (proposer.lltv > 10 ** LLTV_DECIMALS || proposer.lltv == 0) revert InvalidLLTV();

        _defaultData[msg.sender][loanId] = DefaultData({
            lltv: proposer.lltv,
            feedData: encodeChainlinkPriceFeedData(
                proposer.feedInvertFlags,
                proposer.feedIntermediaryDenominations,
                MAX_CHAINLINK_INTERMEDIARY_DENOMINATIONS
            )
        });

        return DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /**
     * @notice Checks if a loan is defaulted based on the value of its collateral and the LLTV ratio.
     * @dev Uses Chainlink feeds to convert collateral value to the credit asset denomination and compares to debt.
     * @param loanContract The address of the loan contract.
     * @param loanId The id of the loan to check.
     * @return True if the loan is defaulted, false otherwise.
     */
    function isDefaulted(address loanContract, uint256 loanId) public view returns (bool) {
        DefaultData memory data = _defaultData[loanContract][loanId];
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations)
            = decodeChainlinkPriceFeedData(data.feedData);

        uint256 value = _chainlink.convertDenomination({
            amount: PWNLoan(loanContract).getLOANDebt(loanId),
            oldDenomination: loan.creditAddress,
            newDenomination: loan.collateral.assetAddress,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        });

        return loan.collateral.amount.mulDiv(data.lltv, 10 ** LLTV_DECIMALS) <= value;
    }

    /**
     * @notice Get the default data for a given loan.
     * @param loanContract Address of the loan contract.
     * @param loanId Loan identifier.
     * @return lltv Liquidation loan-to-value ratio.
     * @return feedIntermediaryDenominations Intermediary denominations used in the price feed.
     * @return feedInvertFlags Flags indicating whether to invert the price feed for each denomination.
     */
    function defaultData(
        address loanContract,
        uint256 loanId
    ) external view returns (
        uint256 lltv,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) {
        lltv = _defaultData[loanContract][loanId].lltv;
        (feedInvertFlags, feedIntermediaryDenominations) = decodeChainlinkPriceFeedData(_defaultData[loanContract][loanId].feedData);
    }

}
