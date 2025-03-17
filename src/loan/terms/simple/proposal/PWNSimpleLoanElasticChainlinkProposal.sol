// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/loan/lib/Chainlink.sol";
import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";


/**
 * @title PWN Simple Loan Elastic Chainlink Proposal
 * @notice Contract for creating and accepting elastic loan proposals using Chainlink oracles.
 * Proposals are elastic, which means that they are not tied to a specific collateral or credit amount.
 * The amount of collateral and credit is specified during the proposal acceptance.
 */
contract PWNSimpleLoanElasticChainlinkProposal is PWNSimpleLoanProposal {
    using Math for uint256;
    using Chainlink for Chainlink.Config;

    string public constant VERSION = "1.1";

    /** @notice Maximum number of intermediary denominations for price conversion.*/
    uint256 public constant MAX_INTERMEDIARY_DENOMINATIONS = 2;
    /** @notice Loan to value denominator. It is used to calculate collateral amount from credit amount.*/
    uint256 public constant LOAN_TO_VALUE_DENOMINATOR = 1e4;

    /** @notice Chainlink feed registry contract.*/
    IChainlinkFeedRegistryLike public immutable chainlinkFeedRegistry;
    /** @notice Chainlink feed for L2 Sequencer uptime. Must be address(0) for L1s.*/
    IChainlinkAggregatorLike public immutable chainlinkL2SequencerUptimeFeed;
    /** @notice WETH address. ETH price feed is used for WETH price.*/
    address public immutable WETH;

    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint24 accruingInterestAPR,uint32 durationOrDate,uint40 expiration,address acceptorController,bytes acceptorControllerData,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining an elastic chainlink proposal.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param checkCollateralStateFingerprint If true, the collateral state fingerprint will be checked during proposal acceptance.
     * @param collateralStateFingerprint Fingerprint of a collateral state. It is used to check if a collateral is in a valid state.
     * @param creditAddress Address of an asset which is lended to a borrower.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the collateral asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param loanToValue Loan to value ratio with 4 decimals. E.g., 6231 == 0.6231 == 62.31%.
     * @param minCreditAmount Minimum amount of tokens which can be borrowed using the proposal.
     * @param availableCreditLimit Available credit limit for the proposal. It is the maximum amount of tokens which can be borrowed using the proposal. If non-zero, proposal can be accepted more than once, until the credit limit is reached.
     * @param utilizedCreditId Id of utilized credit. Can be shared between multiple proposals.
     * @param fixedInterestAmount Fixed interest amount in credit tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR with 2 decimals.
     * @param durationOrDate Duration of a loan in seconds. If the value is greater than 10^9, it is treated as a timestamp of a loan end.
     * @param expiration Proposal expiration timestamp in seconds.
     * @param acceptorController Address of an acceptor controller contract. It is used to check if an address can accept the proposal.
     * @param acceptorControllerData Proposer data for an acceptor controller contract.
     * @param proposer Address of a proposal signer. If `isOffer` is true, the proposer is the lender. If `isOffer` is false, the proposer is the borrower.
     * @param proposerSpecHash Hash of a proposer specific data, which must be provided during a loan creation.
     * @param isOffer If true, the proposal is an offer. If false, the proposal is a request.
     * @param refinancingLoanId Id of a loan which is refinanced by this proposal. If the id is 0 and `isOffer` is true, the proposal can refinance any loan.
     * @param nonceSpace Nonce space of a proposal nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical proposals in time. Without it, it would be impossible to make again proposal, which was once revoked. Can be used to create a group of proposals, where accepting one will make others in the group invalid.
     * @param loanContract Address of a loan contract that will create a loan from the proposal.
     */
    struct Proposal {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 loanToValue;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 fixedInterestAmount;
        uint24 accruingInterestAPR;
        uint32 durationOrDate;
        uint40 expiration;
        address acceptorController;
        bytes acceptorControllerData;
        address proposer;
        bytes32 proposerSpecHash;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    /**
     * @notice Construct defining proposal concrete values.
     * @param creditAmount Amount of credit to be borrowed.
     * @param acceptorControllerData Acceptor data for an acceptor controller contract.
     */
    struct ProposalValues {
        uint256 creditAmount;
        bytes acceptorControllerData;
    }

    /** @notice Emitted when a proposal is made via an on-chain transaction.*/
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    /** @notice Thrown when proposal has no minimum credit amount set.*/
    error MinCreditAmountNotSet();
    /** @notice Thrown when proposal credit amount is insufficient.*/
    error InsufficientCreditAmount(uint256 current, uint256 limit);


    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _chainlinkFeedRegistry,
        address _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNSimpleLoanProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNSimpleLoanElasticChainlinkProposal", VERSION) {
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
     * @param proposalValues ProposalValues struct to be encoded.
     * @return Encoded proposal data.
     */
    function encodeProposalData(
        Proposal memory proposal,
        ProposalValues memory proposalValues
    ) external pure returns (bytes memory) {
        return abi.encode(proposal, proposalValues);
    }

    /**
     * @notice Decode proposal data.
     * @param proposalData Encoded proposal data.
     * @return Decoded proposal struct.
     * @return Decoded proposal values struct.
     */
    function decodeProposalData(bytes memory proposalData) public pure returns (Proposal memory, ProposalValues memory) {
        return abi.decode(proposalData, (Proposal, ProposalValues));
    }

    /**
     * @notice Compute collateral amount from credit amount, LTV, and Chainlink price feeds.
     * @param creditAddress Address of credit token.
     * @param creditAmount Amount of credit.
     * @param collateralAddress Address of collateral token.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the collateral asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param loanToValue Loan to value ratio with 4 decimals. E.g., 6231 == 0.6231 == 62.31%.
     * @return Amount of collateral.
     */
    function getCollateralAmount(
        address creditAddress,
        uint256 creditAmount,
        address collateralAddress,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags,
        uint256 loanToValue
    ) public view returns (uint256) {
        return chainlink().convertDenomination({
            amount: creditAmount,
            oldDenomination: creditAddress,
            newDenomination: collateralAddress,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        }).mulDiv(LOAN_TO_VALUE_DENOMINATOR, loanToValue);
    }

    /** @inheritdoc PWNSimpleLoanProposal*/
    function acceptProposal(
        address acceptor,
        uint256 refinancingLoanId,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) override external returns (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, ProposalValues memory proposalValues) = decodeProposalData(proposalData);

        // Make proposal hash
        proposalHash = _getProposalHash(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        // Check sufficient credit amount
        if (proposalValues.creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: proposalValues.creditAmount, limit: proposal.minCreditAmount });
        }

        // Calculate collateral amount
        uint256 collateralAmount = getCollateralAmount(
            proposal.creditAddress,
            proposalValues.creditAmount,
            proposal.collateralAddress,
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags,
            proposal.loanToValue
        );

        ProposalValuesBase memory proposalValuesBase = ProposalValuesBase({
            refinancingLoanId: refinancingLoanId,
            acceptor: acceptor,
            acceptorControllerData: proposalValues.acceptorControllerData
        });

        // Try to accept proposal
        _acceptProposal(
            proposalHash,
            proposalInclusionProof,
            signature,
            ProposalBase({
                collateralAddress: proposal.collateralAddress,
                collateralId: proposal.collateralId,
                checkCollateralStateFingerprint: proposal.checkCollateralStateFingerprint,
                collateralStateFingerprint: proposal.collateralStateFingerprint,
                creditAmount: proposalValues.creditAmount,
                availableCreditLimit: proposal.availableCreditLimit,
                utilizedCreditId: proposal.utilizedCreditId,
                expiration: proposal.expiration,
                acceptorController: proposal.acceptorController,
                acceptorControllerData: proposal.acceptorControllerData,
                proposer: proposal.proposer,
                isOffer: proposal.isOffer,
                refinancingLoanId: proposal.refinancingLoanId,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce,
                loanContract: proposal.loanContract
            }),
            proposalValuesBase
        );

        // Create loan terms object
        loanTerms = PWNSimpleLoan.Terms({
            lender: proposal.isOffer ? proposal.proposer : acceptor,
            borrower: proposal.isOffer ? acceptor : proposal.proposer,
            duration: _getLoanDuration(proposal.durationOrDate),
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: proposal.collateralId,
                amount: collateralAmount
            }),
            credit: MultiToken.ERC20({
                assetAddress: proposal.creditAddress,
                amount: proposalValues.creditAmount
            }),
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR,
            lenderSpecHash: proposal.isOffer ? proposal.proposerSpecHash : bytes32(0),
            borrowerSpecHash: proposal.isOffer ? bytes32(0) : proposal.proposerSpecHash
        });
    }

    /**
     * @notice Proposal struct that can be encoded for EIP-712.
     * @dev Is typecasting dynamic values to bytes32 to allow EIP-712 encoding.
     */
    struct ERC712Proposal {
        uint8 collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address creditAddress;
        bytes32 feedIntermediaryDenominationsHash;
        bytes32 feedInvertFlagsHash;
        uint256 loanToValue;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 fixedInterestAmount;
        uint24 accruingInterestAPR;
        uint32 durationOrDate;
        uint40 expiration;
        address acceptorController;
        bytes32 acceptorControllerDataHash;
        address proposer;
        bytes32 proposerSpecHash;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    /**
     * @notice Encode proposal data for EIP-712.
     * @param proposal Proposal struct to be encoded.
     * @return Encoded proposal data.
     */
    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            collateralCategory: uint8(proposal.collateralCategory),
            collateralAddress: proposal.collateralAddress,
            collateralId: proposal.collateralId,
            checkCollateralStateFingerprint: proposal.checkCollateralStateFingerprint,
            collateralStateFingerprint: proposal.collateralStateFingerprint,
            creditAddress: proposal.creditAddress,
            feedIntermediaryDenominationsHash: keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            feedInvertFlagsHash: keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            loanToValue: proposal.loanToValue,
            minCreditAmount: proposal.minCreditAmount,
            availableCreditLimit: proposal.availableCreditLimit,
            utilizedCreditId: proposal.utilizedCreditId,
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR,
            durationOrDate: proposal.durationOrDate,
            expiration: proposal.expiration,
            acceptorController: proposal.acceptorController,
            acceptorControllerDataHash: keccak256(proposal.acceptorControllerData),
            proposer: proposal.proposer,
            proposerSpecHash: proposal.proposerSpecHash,
            isOffer: proposal.isOffer,
            refinancingLoanId: proposal.refinancingLoanId,
            nonceSpace: proposal.nonceSpace,
            nonce: proposal.nonce,
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
