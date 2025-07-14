// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { LoanTerms as Terms } from "pwn/core/loan/LoanTerms.sol";
import { IPWNProduct } from "pwn/core/product/IPWNProduct.sol";
import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/periphery/lib/Chainlink.sol";
import { encodeChainlinkPriceFeedData, decodeChainlinkPriceFeedData, flipFeeds } from "pwn/periphery/utils/chainlinkUtils.sol";
import { PWNRevokedNonce } from "pwn/periphery/auxiliary/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/periphery/auxiliary/PWNUtilizedCredit.sol";


contract PWNFixedProduct is IPWNProduct {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;
    using Math for uint256;
    using SafeCast for uint256;
    using Chainlink for Chainlink.Config;

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    string public constant NAME = "PWN Fixed Product";
    string public constant VERSION = "1.5";

    /** @notice The minimum allowed duration (in seconds) for the default period.*/
    uint256 public constant MIN_DURATION = 10 minutes;
    /** @notice Maximum number of intermediary denominations for price conversion.*/
    uint256 public constant MAX_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice Loan to value decimals (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant LOAN_TO_VALUE_DECIMALS = 4;
    /** @notice Number of decimals for APR precision (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant APR_DECIMALS = 4;

    /** @notice PWN Hub contract.*/
    PWNHub public immutable hub;
    /** @notice PWN Revoked Nonce contract.*/
    PWNRevokedNonce public immutable revokedNonce;
    /** @notice PWN Utilized Credit contract.*/
    PWNUtilizedCredit public immutable utilizedCredit;

    /** @dev Chainlink configuration struct for price feed operations.*/
    Chainlink.Config internal _chainlink;

    /** @dev EIP-712 domain separator for proposal contracts.*/
    bytes32 public immutable DOMAIN_SEPARATOR;
    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address collateralAddress,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 acceptableLoanToValue,uint256 interestAPR,uint256 duration,uint256 liquidationLoanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"
    );

    /**
     * @notice Struct representing a fixed interest loan proposal.
     * @dev Contains all parameters required to define a loan proposal, including collateral, credit, interest, and proposal metadata.
     * @param collateralAddress The address of the collateral asset.
     * @param creditAddress The address of the credit asset (loan currency).
     * @param feedIntermediaryDenominations Array of intermediary denominations for price feed routing.
     * @param feedInvertFlags Array of flags indicating if the price feed should be inverted for each denomination.
     * @param acceptableLoanToValue The acceptable loan-to-value ratio (LTV), expressed in basis points (1e4 = 100%). For lender, it's the maxium acceptable LTV, for borrower it's the LTV they are willing to accept.
     * @param interestAPR The annual percentage rate (APR) for the loan interest, expressed in basis points (1e4 = 100%).
     * @param duration The duration of the loan in seconds, after which it is considered defaulted if not repaid.
     * @param liquidationLoanToValue The liquidation loan-to-value threshold, expressed in basis points (1e4 = 100%).
     * @param minCreditAmount The minimum amount of credit (loan) that can be drawn.
     * @param availableCreditLimit The total available credit limit for the proposal.
     * @param utilizedCreditId Identifier for utilized credit, if any.
     * @param nonceSpace Nonce space for replay protection.
     * @param nonce Nonce for replay protection.
     * @param expiration Expiration timestamp of the proposal.
     * @param proposerSpecHash Hash of proposer-specific data.
     * @param isProposerLender Boolean indicating if the proposer is the lender.
     * @param loanContract The address of the loan contract to be used.
     */
    struct Proposal {
        // Collateral
        address collateralAddress;
        // Credit
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 acceptableLoanToValue;
        // Interest
        uint256 interestAPR;
        // Default
        uint256 duration;
        // Liquidation
        uint256 liquidationLoanToValue;
        // Proposal validity
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        // General proposal
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    /**
     * @notice Construct defining values provided by an acceptor.
     * @param creditAmount Amount of credit to be borrowed.
     * @param loanToValue Loan-to-value ratio, scaled by LOAN_TO_VALUE_DECIMALS. The collateral amount required for the loan is computed based on this ratio.
     */
    struct AcceptorValues {
        uint256 creditAmount;
        uint256 loanToValue;
    }

    /**
     * @notice Struct containing loan data for interest, default, and liquidation logic.
     * @param apr Annual Percentage Rate (APR) for interest calculation, scaled by APR_DECIMALS.
     * @param defaultTimestamp Timestamp when the loan is considered defaulted.
     * @param lltv Liquidation loan-to-value ratio, scaled by LOAN_TO_VALUE_DECIMALS.
     * @param feedData Encoded Chainlink feed data for price conversion.
     */
    struct LoanData {
        uint40 apr;
        uint40 loanStart;
        uint40 defaultTimestamp;
        uint16 lltv;
        bytes feedData;
    }

    /** @notice Mapping of loan contract and loan id to loan data for interest, default, and liquidation logic.*/
    mapping (address => mapping(uint256 => LoanData)) public loanData;


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when a proposal is expired.*/
    error Expired(uint256 current, uint256 expiration);
    /** @notice Thrown when a caller is missing a required hub tag.*/
    error CallerNotLoanContract(address caller, address loanContract);
    /** @notice Thrown when proposal has no minimum credit amount set.*/
    error MinCreditAmountNotSet();
    /** @notice Thrown when proposal credit amount is insufficient.*/
    error InsufficientCreditAmount(uint256 current, uint256 limit);
    /** @notice Thrown when the provided LLTV is invalid (zero or above 1.0).*/
    error InvalidLiquidationLoanToValue();
    /** @notice Thrown when the liquidation data is not empty.*/
    error LiquidationDataNotEmpty();
    /** @notice Thrown when liquidated loan is not initialized in this module.*/
    error LoanNotInitialized();
    /** @notice Thrown when the duration is less than the minimum allowed duration.*/
    error DurationTooShort();
    /** @notice Thrown when loan to value is zero.*/
    error LoanToValueZero();
    /** @notice Thrown when the loan to value is outside of acceptable limits for the proposal.*/
    error InvalidLoanToValue();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        PWNHub _hub,
        PWNRevokedNonce _revokedNonce,
        PWNUtilizedCredit _utilizedCredit,
        IChainlinkFeedRegistryLike _chainlinkFeedRegistry,
        IChainlinkAggregatorLike _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) {
        hub = PWNHub(_hub);
        revokedNonce = PWNRevokedNonce(_revokedNonce);
        utilizedCredit = PWNUtilizedCredit(_utilizedCredit);
        _chainlink.l2SequencerUptimeFeed = _chainlinkL2SequencerUptimeFeed;
        _chainlink.feedRegistry = _chainlinkFeedRegistry;
        _chainlink.maxIntermediaryDenominations = MAX_INTERMEDIARY_DENOMINATIONS;
        _chainlink.weth = _weth;

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(abi.encodePacked(NAME)),
            keccak256(abi.encodePacked(VERSION)),
            block.chainid,
            address(this)
        ));
    }


    /*----------------------------------------------------------*|
    |*  # EXTERNALS                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Calculates the required collateral amount for a given position.
     * @dev This function determines how much collateral is needed based on the product's parameters.
     * @param creditAddress The address of the credit token.
     * @param creditAmount The amount of credit to be used in the calculation.
     * @param collateralAddress The address of the collateral token.
     * @param feedIntermediaryDenominations An array of intermediary token addresses used for multi-hop price feed conversions.
     * @param feedInvertFlags An array of boolean flags indicating if each corresponding price feed should be inverted.
     * @param loanToValue The loan-to-value ratio, scaled by LOAN_TO_VALUE_DECIMALS. This is the ratio of the loan amount to the collateral value.
     * @return The amount of collateral required.
     */
    function getCollateralAmount(
        address creditAddress,
        uint256 creditAmount,
        address collateralAddress,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags,
        uint256 loanToValue
    ) public view returns (uint256) {
        if (loanToValue == 0) revert LoanToValueZero();
        return _chainlink.convertDenomination({
            amount: creditAmount,
            oldDenomination: creditAddress,
            newDenomination: collateralAddress,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        }).mulDiv(10 ** LOAN_TO_VALUE_DECIMALS, loanToValue);
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL                                              *|
    |*----------------------------------------------------------*/

    function acceptProposal(
        uint256 loanId,
        address /* acceptor */,
        address proposer,
        bytes calldata proposalData
    ) external returns (Terms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, AcceptorValues memory acceptorValues) = decodeProposalData(proposalData);

        // Check loan contract
        if (msg.sender != proposal.loanContract) {
            revert CallerNotLoanContract({ caller: msg.sender, loanContract: proposal.loanContract });
        }
        if (!hub.hasTag(proposal.loanContract, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: proposal.loanContract, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Check proposal is not expired
        if (block.timestamp >= proposal.expiration) {
            revert Expired({ current: block.timestamp, expiration: proposal.expiration });
        }

        // Check proposal is not revoked
        if (!revokedNonce.isNonceUsable(proposer, proposal.nonceSpace, proposal.nonce)) {
            revert PWNRevokedNonce.NonceNotUsable({
                addr: proposer,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce
            });
        }

        // Check liquidation ltv
        if (proposal.liquidationLoanToValue == 0) {
            // If LLTV is zero, it is invalid
            revert InvalidLiquidationLoanToValue();
        } else if (proposal.liquidationLoanToValue > 10 ** LOAN_TO_VALUE_DECIMALS) {
            // If LLTV is above 1.0, it is invalid
            revert InvalidLiquidationLoanToValue();
        } else if (proposal.liquidationLoanToValue < proposal.acceptableLoanToValue) {
            // If LLTV is less than max acceptable LTV, it is invalid
            revert InvalidLiquidationLoanToValue();
        }

        // Check duration
        if (proposal.duration < MIN_DURATION) {
            revert DurationTooShort();
        }

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        // Check sufficient credit amount
        if (acceptorValues.creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: acceptorValues.creditAmount, limit: proposal.minCreditAmount });
        }

        // Check if LTV is within acceptable limits
        if (proposal.isProposerLender && acceptorValues.loanToValue > proposal.acceptableLoanToValue) {
            // For lender, check if the LTV is below the maximum acceptable LTV
            revert InvalidLoanToValue();
        } else if (!proposal.isProposerLender && acceptorValues.loanToValue != proposal.acceptableLoanToValue) {
            // For borrower, check if the LTV is equal to the acceptable LTV
            revert InvalidLoanToValue();
        }

        // Compute collateral amount required for the loan
        uint256 collateralAmount = getCollateralAmount(
            proposal.creditAddress,
            acceptorValues.creditAmount,
            proposal.collateralAddress,
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags,
            acceptorValues.loanToValue
        );

        if (proposal.availableCreditLimit == 0) {
            // Revoke nonce if credit limit is 0, proposal can be accepted only once
            revokedNonce.revokeNonce(proposer, proposal.nonceSpace, proposal.nonce);
        } else {
            // Update utilized credit
            // Note: This will revert if utilized credit would exceed the available credit limit
            utilizedCredit.utilizeCredit(proposer, proposal.utilizedCreditId, acceptorValues.creditAmount, proposal.availableCreditLimit);
        }

        // Store data for the loan interest, default, and liquidation modules
        loanData[msg.sender][loanId] = LoanData({
            apr: proposal.interestAPR.toUint40(),
            loanStart: block.timestamp.toUint40(),
            defaultTimestamp: (block.timestamp + proposal.duration).toUint40(),
            lltv: proposal.liquidationLoanToValue.toUint16(),
            feedData: encodeChainlinkPriceFeedData(
                proposal.feedInvertFlags,
                proposal.feedIntermediaryDenominations,
                MAX_INTERMEDIARY_DENOMINATIONS
            )
        });

        // Create loan terms object
        return Terms({
            isProposerLender: proposal.isProposerLender,
            proposerSpecHash: proposal.proposerSpecHash,
            collateral: proposal.collateralAddress.ERC20(collateralAmount),
            creditAddress: proposal.creditAddress,
            principal: acceptorValues.creditAmount
        });
    }

    function nameAndVersion() external pure returns (string memory name, string memory version) {
        return (NAME, VERSION);
    }

    function hashProposalTypedData(bytes calldata proposalData) external pure returns (bytes32) {
        (Proposal memory proposal, ) = decodeProposalData(proposalData);
        return keccak256(abi.encodePacked(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal)));
    }


    /*----------------------------------------------------------*|
    |*  # INTEREST                                              *|
    |*----------------------------------------------------------*/

    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        if (block.timestamp < loan.lastUpdateTimestamp) return 0;

        LoanData storage data = loanData[loanContract][loanId];
        return data.loanStart == loan.lastUpdateTimestamp
            ? loan.principal.mulDiv(uint256(data.apr) * (data.defaultTimestamp - data.loanStart), 365 days * 10 ** APR_DECIMALS)
            : 0;
    }


    /*----------------------------------------------------------*|
    |*  # DEFAULT                                               *|
    |*----------------------------------------------------------*/

    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool) {
        LoanData storage data = loanData[loanContract][loanId];

        if (data.defaultTimestamp <= block.timestamp) {
            return true;
        }

        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations)
            = decodeChainlinkPriceFeedData(data.feedData);

        uint256 minCollateralAmount = getCollateralAmount(
            loan.creditAddress,
            PWNLoan(loanContract).getLOANDebt(loanId),
            loan.collateral.assetAddress,
            feedIntermediaryDenominations,
            feedInvertFlags,
            data.lltv
        );

        return loan.collateral.amount <= minCollateralAmount;
    }


    /*----------------------------------------------------------*|
    |*  # LIQUIDATION                                           *|
    |*----------------------------------------------------------*/

    function liquidate(
        uint256 loanId,
        address liquidator,
        address borrower,
        uint256 debt,
        address creditAddress,
        MultiToken.Asset calldata collateral,
        bytes calldata liquidationData
    ) external returns (uint256 liquidationAmount) {
        if (liquidationData.length != 0) revert LiquidationDataNotEmpty();

        LoanData memory data = loanData[msg.sender][loanId];
        if (data.lltv == 0) revert LoanNotInitialized();

        // Cover debt
        MultiToken.Asset memory credit = creditAddress.ERC20(debt);
        credit.transferAssetFrom(liquidator, address(this));
        credit.approveAsset(msg.sender);

        // Transfer surplus between LP value and debt to borrower
        (bool[] memory feedInvertFlags, address[] memory feedIntermediaryDenominations)
            = decodeChainlinkPriceFeedData(data.feedData);

        // Note: need to flip feeds direction to get from collateral to credit
        (feedInvertFlags, feedIntermediaryDenominations)
            = flipFeeds(feedInvertFlags, feedIntermediaryDenominations);

        uint256 collateralLiquidationValue = _chainlink.convertDenomination({
            amount: collateral.amount,
            oldDenomination: collateral.assetAddress,
            newDenomination: creditAddress,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        }).mulDiv(data.lltv, 10 ** LOAN_TO_VALUE_DECIMALS);

        if (collateralLiquidationValue > debt) {
            credit.amount = collateralLiquidationValue - debt;
            credit.transferAssetFrom(liquidator, borrower);
        }

        // Transfer collateral to liquidator
        collateral.transferAssetFrom(address(this), liquidator);

        return debt;
    }


    /*----------------------------------------------------------*|
    |*  # EN/DECODE                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Encode proposal data.
     * @param proposal Proposal struct to be encoded.
     * @param acceptorValues Acceptor values struct to be encoded.
     * @return Encoded proposal data.
     */
    function encodeProposalData(
        Proposal memory proposal,
        AcceptorValues memory acceptorValues
    ) external pure returns (bytes memory) {
        return abi.encode(proposal, acceptorValues);
    }

    /**
     * @notice Decode proposal data.
     * @param proposalData Encoded proposal data.
     * @return Decoded proposal struct.
     * @return Decoded acceptor values struct.
     */
    function decodeProposalData(bytes memory proposalData) public pure returns (Proposal memory, AcceptorValues memory) {
        return abi.decode(proposalData, (Proposal, AcceptorValues));
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /** @notice Proposal struct that is typecasting dynamic values to bytes32 to enable easy EIP-712 encoding.*/
    struct ERC712Proposal {
        address collateralAddress;
        address creditAddress;
        bytes32 feedIntermediaryDenominationsHash;
        bytes32 feedInvertFlagsHash;
        uint256 acceptableLoanToValue;
        uint256 interestAPR;
        uint256 duration;
        uint256 liquidationLoanToValue;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            collateralAddress: proposal.collateralAddress,
            creditAddress: proposal.creditAddress,
            feedIntermediaryDenominationsHash: keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            feedInvertFlagsHash: keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            acceptableLoanToValue: proposal.acceptableLoanToValue,
            interestAPR: proposal.interestAPR,
            duration: proposal.duration,
            liquidationLoanToValue: proposal.liquidationLoanToValue,
            minCreditAmount: proposal.minCreditAmount,
            availableCreditLimit: proposal.availableCreditLimit,
            utilizedCreditId: proposal.utilizedCreditId,
            nonceSpace: proposal.nonceSpace,
            nonce: proposal.nonce,
            expiration: proposal.expiration,
            proposerSpecHash: proposal.proposerSpecHash,
            isProposerLender: proposal.isProposerLender,
            loanContract: proposal.loanContract
        });
        return abi.encode(erc712Proposal);
    }

}
