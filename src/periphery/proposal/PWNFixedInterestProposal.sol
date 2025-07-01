// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/periphery/lib/Chainlink.sol";
import { PWNFixedPeriodInterestModule, IPWNInterestModule } from "pwn/periphery/loan/module/interest/PWNFixedPeriodInterestModule.sol";
import { PWNChainlinkValueDefaultModule, IPWNDefaultModule } from "pwn/periphery/loan/module/default/PWNChainlinkValueDefaultModule.sol";
import { PWNOpenLiquidationModule, IPWNLiquidationModule } from "pwn/periphery/loan/module/liquidation/PWNOpenLiquidationModule.sol";
import { PWNBaseProposal, Terms, IPWNProposal } from "pwn/periphery/proposal/PWNBaseProposal.sol";


/**
 * @title PWNFixedInterestProposal
 * @dev This contract is designed to facilitate the creation and management of proposals
 * that have predetermined, immutable terms. It extends the base proposal functionality
 * by enforcing fixed parameters, ensuring consistency and reliability in proposal agreements.
 */
contract PWNFixedInterestProposal is PWNBaseProposal {
    using Math for uint256;
    using Chainlink for Chainlink.Config;
    using MultiToken for address;

    string public constant VERSION = "1.5";

    /** @notice Maximum number of intermediary denominations for price conversion.*/
    uint256 public constant MAX_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice Loan to value decimals. It is used to calculate collateral amount from credit amount.*/
    uint256 public constant LOAN_TO_VALUE_DECIMALS = 4;

    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address collateralAddress,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 maxAcceptableLTV,uint256 interestAPR,uint256 fixationPeriod,uint256 LLTV,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"
    );

    /** @notice Fixed period interest module used in the proposal.*/
    PWNFixedPeriodInterestModule public immutable interestModule;
    /** @notice Chainlink value default module used in the proposal.*/
    PWNChainlinkValueDefaultModule public immutable defaultModule;
    /** @notice Open liquidation module used in the proposal.*/
    PWNOpenLiquidationModule public immutable liquidationModule;
    /** @notice Chainlink feed registry contract.*/
    IChainlinkFeedRegistryLike public immutable chainlinkFeedRegistry;
    /** @notice Chainlink feed for L2 Sequencer uptime. Must be address(0) for L1s.*/
    IChainlinkAggregatorLike public immutable chainlinkL2SequencerUptimeFeed;
    /** @notice WETH address. ETH price feed is used for WETH price.*/
    address public immutable WETH;

    /**
     * @notice Represents the terms and parameters of a fixed-term lending proposal.
     * @dev This struct encapsulates all necessary information for a lending proposal, including collateral, credit, interest, and proposal metadata.
     * @param collateralAddress The address of the collateral asset.
     * @param creditAddress The address of the credit asset.
     * @param feedIntermediaryDenominations Array of intermediary denominations for price Chainlink feeds.
     * @param feedInvertFlags Array of flags indicating whether to invert the price feed for each denomination.
     * @param maxAcceptableLTV The maximum acceptable loan-to-value ratio (LTV) for the proposal.
     * @param interestAPR The annual percentage rate (APR) of interest for the loan.
     * @param fixationPeriod The period (in seconds) for which the interest rate is fixed.
     * @param LLTV The liquidation loan-to-value ratio (LLTV) at which collateral may be liquidated.
     * @param minCreditAmount The minimum amount of credit that can be drawn from this proposal.
     * @param availableCreditLimit The total available credit limit for this proposal.
     * @param utilizedCreditId The identifier for the utilized credit portion.
     * @param nonceSpace The space identifier for the nonce, used to prevent replay attacks.
     * @param nonce The unique nonce for this proposal, used to ensure uniqueness.
     * @param expiration The timestamp at which this proposal expires.
     * @param proposer The address of the entity proposing the terms.
     * @param proposerSpecHash The hash of the proposer's specific terms or metadata.
     * @param isProposerLender Boolean indicating if the proposer is the lender (true) or borrower (false).
     * @param loanContract The address of the loan contract associated with this proposal.
     */
    struct Proposal {
        // Collateral
        address collateralAddress;
        // Credit
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 maxAcceptableLTV;
        // Interest
        uint256 interestAPR;
        uint256 fixationPeriod;
        // Default
        uint256 LLTV;
        // Proposal validity
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        // General proposal
        address proposer;
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    /**
     * @dev Represents the values provided by the acceptor in a proposal.
     * @param collateralAmount The amount of collateral to be provided by the acceptor.
     * @param creditAmount The amount of credit to be received by the acceptor.
     */
    struct AcceptorValues {
        uint256 collateralAmount;
        uint256 creditAmount;
    }

    /** @notice Emitted when a proposal is made via an on-chain transaction.*/
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    /** @notice Thrown when proposal has no minimum credit amount set.*/
    error MinCreditAmountNotSet();
    /** @notice Thrown when proposal credit amount is insufficient.*/
    error InsufficientCreditAmount(uint256 current, uint256 limit);
    /** @notice Thrown when loan to value ratio is too high.*/
    error LoanToValueTooHigh(uint256 current, uint256 limit);
    /** @notice Thrown when liquidation loan to value ratio is invalid.*/
    error InvalidLiquidationLoanToValue();
    /** @notice Thrown when collateral amount is zero.*/
    error CollateralAmountZero();


    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule,
        address _liquidationModule,
        address _chainlinkFeedRegistry,
        address _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNBaseProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNFixedInterestProposal", VERSION) {
        interestModule = PWNFixedPeriodInterestModule(_interestModule);
        defaultModule = PWNChainlinkValueDefaultModule(_defaultModule);
        liquidationModule = PWNOpenLiquidationModule(_liquidationModule);
        chainlinkFeedRegistry = IChainlinkFeedRegistryLike(_chainlinkFeedRegistry);
        chainlinkL2SequencerUptimeFeed = IChainlinkAggregatorLike(_chainlinkL2SequencerUptimeFeed);
        WETH = _weth;
    }


    /**
     * @notice Get an proposal hash according to EIP-712
     * @param proposal Proposal struct to be hashed.
     * @return Proposal struct hash.
     */
    function getProposalHash(Proposal calldata proposal) public view returns (bytes32) {
        return _getProposalHash(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));
    }

    /**
     * @notice Make an on-chain proposal.
     * @dev Function will mark a proposal hash as proposed.
     * @param proposal Proposal struct containing all needed proposal data.
     * @return proposalHash Proposal hash.
     */
    function makeProposal(Proposal calldata proposal) external returns (bytes32 proposalHash) {
        proposalHash = getProposalHash(proposal);
        _makeProposal(proposalHash, proposal.proposer);
        emit ProposalMade(proposalHash, proposal.proposer, proposal);
    }

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

    /**
     * @notice Compute collateral amount from credit amount, LTV, and Chainlink price feeds.
     * @param creditAddress Address of credit token.
     * @param creditAmount Amount of credit.
     * @param collateralAddress Address of collateral token.
     * @param collateralAmount Amount of collateral.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the collateral asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @return Loan to value ratio in percentage with LOAN_TO_VALUE_DECIMALS decimals.
     */
    function getLoanToValue(
        address creditAddress,
        uint256 creditAmount,
        address collateralAddress,
        uint256 collateralAmount,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) public view returns (uint256) {
        if (collateralAmount == 0) revert CollateralAmountZero();
        return chainlink().convertDenomination({
            amount: creditAmount,
            oldDenomination: creditAddress,
            newDenomination: collateralAddress,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        }).mulDiv(10 ** LOAN_TO_VALUE_DECIMALS, collateralAmount);
    }

    /** @inheritdoc IPWNProposal*/
    function acceptProposal(
        address acceptor,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) override external returns (Terms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, AcceptorValues memory acceptorValues) = decodeProposalData(proposalData);

        // Make proposal hash
        bytes32 proposalHash = _getProposalHash(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));

        if (proposal.LLTV > 10 ** LOAN_TO_VALUE_DECIMALS) {
            // If LLTV is greater than 100%, it is invalid
            revert InvalidLiquidationLoanToValue();
        } else if (proposal.LLTV <= proposal.maxAcceptableLTV) {
            // If LLTV is less than max acceptable LTV, it is invalid
            revert InvalidLiquidationLoanToValue();
        }

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        // Check sufficient credit amount
        if (acceptorValues.creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: acceptorValues.creditAmount, limit: proposal.minCreditAmount });
        }

        uint256 ltv = getLoanToValue(
            proposal.creditAddress,
            acceptorValues.creditAmount,
            proposal.collateralAddress,
            acceptorValues.collateralAmount,
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags
        );

        // Check if LTV is within acceptable limits
        if (ltv > proposal.maxAcceptableLTV) {
            revert LoanToValueTooHigh(ltv, proposal.maxAcceptableLTV);
        }

        // Check if proposal is valid
        _checkProposal(
            CheckInputs({
                proposalHash: proposalHash,
                acceptor: acceptor,
                creditAmount: acceptorValues.creditAmount,
                availableCreditLimit: proposal.availableCreditLimit,
                utilizedCreditId: proposal.utilizedCreditId,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce,
                expiration: proposal.expiration,
                proposer: proposal.proposer,
                loanContract: proposal.loanContract
            }),
            proposalInclusionProof,
            signature
        );

        // Create loan terms object
        return Terms({
            proposalHash: proposalHash,
            lender: proposal.isProposerLender ? proposal.proposer : acceptor,
            borrower: proposal.isProposerLender ? acceptor : proposal.proposer,
            proposerSpecHash: proposal.proposerSpecHash,
            collateral: proposal.collateralAddress.ERC20(acceptorValues.collateralAmount),
            creditAddress: proposal.creditAddress,
            principal: acceptorValues.creditAmount,
            interestModule: IPWNInterestModule(interestModule),
            interestModuleProposerData: abi.encode(
                PWNFixedPeriodInterestModule.ProposerData(
                    proposal.interestAPR, proposal.fixationPeriod
                )
            ),
            defaultModule: IPWNDefaultModule(defaultModule),
            defaultModuleProposerData: abi.encode(
                PWNChainlinkValueDefaultModule.ProposerData(
                    proposal.LLTV, proposal.feedIntermediaryDenominations, proposal.feedInvertFlags
                )
            ),
            liquidationModule: IPWNLiquidationModule(liquidationModule),
            liquidationModuleProposerData: ""
        });
    }

    /**
     * @notice Proposal struct that can be encoded for EIP-712.
     * @dev Is typecasting dynamic values to bytes32 to allow EIP-712 encoding.
     */
    struct ERC712Proposal {
        address collateralAddress;
        address creditAddress;
        bytes32 feedIntermediaryDenominationsHash;
        bytes32 feedInvertFlagsHash;
        uint256 maxAcceptableLTV;
        uint256 interestAPR;
        uint256 fixationPeriod;
        uint256 LLTV;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        address proposer;
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    /**
     * @notice Encode proposal data for EIP-712.
     * @param proposal Proposal struct to be encoded.
     * @return Encoded proposal data.
     */
    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            collateralAddress: proposal.collateralAddress,
            creditAddress: proposal.creditAddress,
            feedIntermediaryDenominationsHash: keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            feedInvertFlagsHash: keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            maxAcceptableLTV: proposal.maxAcceptableLTV,
            interestAPR: proposal.interestAPR,
            fixationPeriod: proposal.fixationPeriod,
            LLTV: proposal.LLTV,
            minCreditAmount: proposal.minCreditAmount,
            availableCreditLimit: proposal.availableCreditLimit,
            utilizedCreditId: proposal.utilizedCreditId,
            nonceSpace: proposal.nonceSpace,
            nonce: proposal.nonce,
            expiration: proposal.expiration,
            proposer: proposal.proposer,
            proposerSpecHash: proposal.proposerSpecHash,
            isProposerLender: proposal.isProposerLender,
            loanContract: proposal.loanContract
        });
        return abi.encode(erc712Proposal);
    }

    function chainlink() internal view returns (Chainlink.Config memory) {
        return Chainlink.Config({
            l2SequencerUptimeFeed: chainlinkL2SequencerUptimeFeed,
            feedRegistry: chainlinkFeedRegistry,
            maxIntermediaryDenominations: MAX_INTERMEDIARY_DENOMINATIONS,
            weth: WETH
        });
    }

}
