// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNStableInterestModule, IPWNInterestModule } from "pwn/periphery/loan/module/interest/PWNStableInterestModule.sol";
import { PWNDurationDefaultModule, IPWNDefaultModule } from "pwn/periphery/loan/module/default/PWNDurationDefaultModule.sol";
import { PWNClaimLiquidationModule, IPWNLiquidationModule } from "pwn/periphery/loan/module/liquidation/PWNClaimLiquidationModule.sol";
import { PWNBaseProposal, Terms } from "pwn/periphery/proposal/PWNBaseProposal.sol";


/**
 * @title PWN Dutch Auction Proposal
 * @notice Contract for creating and accepting dutch auction loan proposals.
 */
contract PWNDutchAuctionProposal is PWNBaseProposal {

    string public constant VERSION = "1.5";

    /** @dev EIP-712 simple proposal struct type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address creditAddress,uint256 minCreditAmount,uint256 maxCreditAmount,uint256 auctionStart,uint256 auctionDuration,uint256 interestAPR,uint256 duration,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"
    );

    /** @notice Stable interest module used in the proposal.*/
    PWNStableInterestModule public immutable interestModule;
    /** @notice Duration based default module used in the proposal.*/
    PWNDurationDefaultModule public immutable defaultModule;
    /** @notice LOAN owner claim liquidation module used in the proposal.*/
    PWNClaimLiquidationModule public immutable liquidationModule;

    /**
     * @notice Construct defining a simple proposal.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 0.
     * @param creditAddress Address of an asset which is lended to a borrower.
     * @param minCreditAmount Minimum amount of tokens which is proposed as a loan to a borrower. If `isOffer` is true, auction will start with this amount, otherwise it will end with this amount.
     * @param maxCreditAmount Maximum amount of tokens which is proposed as a loan to a borrower. If `isOffer` is true, auction will end with this amount, otherwise it will start with this amount.
     * @param auctionStart Auction start timestamp in seconds.
     * @param auctionDuration Auction duration in seconds.
     * @param interestAPR Accruing interest APR with 2 decimals.
     * @param duration Duration of a loan in seconds.
     * @param availableCreditLimit Available credit limit for the proposal. It is the maximum amount of tokens which can be borrowed using the proposal. If non-zero, proposal can be accepted more than once, until the credit limit is reached.
     * @param utilizedCreditId Id of utilized credit. Can be shared between multiple proposals.
     * @param nonceSpace Nonce space of a proposal nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical proposals in time. Without it, it would be impossible to make again proposal, which was once revoked. Can be used to create a group of proposals, where accepting one proposal will make other proposals in the group revoked.
     * @param expiration Proposal expiration timestamp in seconds.
     * @param proposer Address of a proposal signer.
     * @param proposerSpecHash Hash of a proposer specific data, which must be provided during a loan creation.
     * @param isProposerLender If true, the proposer is a lender. If false, the proposer is a borrower.
     * @param loanContract Address of a loan contract that will create a loan from the proposal.
     */
    struct Proposal {
        // Collateral
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        uint256 collateralAmount;
        // Credit
        address creditAddress;
        uint256 minCreditAmount;
        uint256 maxCreditAmount;
        uint256 auctionStart;
        uint256 auctionDuration;
        // Interest
        uint256 interestAPR;
        // Default
        uint256 duration;
        // Proposal validity
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
     * @notice Construct defining proposal concrete values.
     * @dev At the time of execution, current auction credit amount must be in the range of `creditAmount` and `creditAmount` + `slippage`.
     * @param intendedCreditAmount Amount of tokens which acceptor intends to borrow.
     * @param slippage Slippage value that is acceptor willing to accept from the intended `creditAmount`.
     * If proposal is an offer, slippage is added to the `creditAmount`, otherwise it is subtracted.
     */
    struct AcceptorValues {
        uint256 intendedCreditAmount;
        uint256 slippage;
    }

    /** @notice Emitted when a proposal is made via an on-chain transaction.*/
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    /** @notice Thrown when auction duration is less than min auction duration.*/
    error InvalidAuctionDuration(uint256 current, uint256 limit);
    /** @notice Thrown when auction duration is not in full minutes.*/
    error AuctionDurationNotInFullMinutes(uint256 current);
    /** @notice Thrown when min credit amount is greater than max credit amount.*/
    error InvalidCreditAmountRange(uint256 minCreditAmount, uint256 maxCreditAmount);
    /** @notice Thrown when current auction credit amount is not in the range of intended credit amount and slippage.*/
    error InvalidCreditAmount(uint256 auctionCreditAmount, uint256 intendedCreditAmount, uint256 slippage);
    /** @notice Thrown when auction has not started yet or has already ended.*/
    error AuctionNotInProgress(uint256 currentTimestamp, uint256 auctionStart);

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule,
        address _liquidationModule
    ) PWNBaseProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNDutchAuctionProposal", VERSION) {
        interestModule = PWNStableInterestModule(_interestModule);
        defaultModule = PWNDurationDefaultModule(_defaultModule);
        liquidationModule = PWNClaimLiquidationModule(_liquidationModule);
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
     * @notice Get credit amount for an auction in a specific timestamp.
     * @dev Auction runs one minute longer than `auctionDuration` to have `maxCreditAmount` value in the last minute.
     * @param proposal Proposal struct containing all proposal data.
     * @param timestamp Timestamp to calculate auction credit amount for.
     * @return Credit amount in the auction for provided timestamp.
     */
    function getCreditAmount(Proposal memory proposal, uint256 timestamp) public pure returns (uint256) {
        // Check proposal
        if (proposal.auctionDuration < 1 minutes) {
            revert InvalidAuctionDuration({
                current: proposal.auctionDuration,
                limit: 1 minutes
            });
        }
        if (proposal.auctionDuration % 1 minutes > 0) {
            revert AuctionDurationNotInFullMinutes({
                current: proposal.auctionDuration
            });
        }
        if (proposal.maxCreditAmount <= proposal.minCreditAmount) {
            revert InvalidCreditAmountRange({
                minCreditAmount: proposal.minCreditAmount,
                maxCreditAmount: proposal.maxCreditAmount
            });
        }

        // Check auction is in progress
        if (timestamp < proposal.auctionStart) {
            revert AuctionNotInProgress({
                currentTimestamp: timestamp,
                auctionStart: proposal.auctionStart
            });
        }
        if (proposal.auctionStart + proposal.auctionDuration + 1 minutes <= timestamp) {
            revert Expired({
                current: timestamp,
                expiration: proposal.auctionStart + proposal.auctionDuration + 1 minutes
            });
        }

        // Note: Auction duration is increased by 1 minute to have
        // `maxCreditAmount` value in the last minutes of the auction.

        uint256 creditAmountDelta = Math.mulDiv(
            proposal.maxCreditAmount - proposal.minCreditAmount, // Max credit amount difference
            (timestamp - proposal.auctionStart) / 1 minutes, // Time passed since auction start
            proposal.auctionDuration / 1 minutes // Auction duration
        );

        // Note: Request auction is decreasing credit amount (dutch auction).
        // Offer auction is increasing credit amount (reverse dutch auction).

        // Return credit amount
        return proposal.isProposerLender
            ? proposal.minCreditAmount + creditAmountDelta
            : proposal.maxCreditAmount - creditAmountDelta;
    }

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

        // Calculate current credit amount
        uint256 creditAmount = getCreditAmount(proposal, block.timestamp);

        // Check acceptor values
        if (proposal.isProposerLender) {
            if (
                creditAmount < acceptorValues.intendedCreditAmount ||
                acceptorValues.intendedCreditAmount + acceptorValues.slippage < creditAmount
            ) {
                revert InvalidCreditAmount({
                    auctionCreditAmount: creditAmount,
                    intendedCreditAmount: acceptorValues.intendedCreditAmount,
                    slippage: acceptorValues.slippage
                });
            }
        } else {
            if (
                creditAmount > acceptorValues.intendedCreditAmount ||
                acceptorValues.intendedCreditAmount - acceptorValues.slippage > creditAmount
            ) {
                revert InvalidCreditAmount({
                    auctionCreditAmount: creditAmount,
                    intendedCreditAmount: acceptorValues.intendedCreditAmount,
                    slippage: acceptorValues.slippage
                });
            }
        }

        // Check if proposal is valid
        _checkProposal(
            CheckInputs({
                proposalHash: proposalHash,
                acceptor: acceptor,
                creditAmount: creditAmount,
                availableCreditLimit: proposal.availableCreditLimit,
                utilizedCreditId: proposal.utilizedCreditId,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce,
                expiration: proposal.auctionStart + proposal.auctionDuration + 1 minutes,
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
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: proposal.collateralId,
                amount: proposal.collateralAmount
            }),
            creditAddress: proposal.creditAddress,
            principal: creditAmount,
            interestModule: IPWNInterestModule(interestModule),
            interestModuleProposerData: abi.encode(PWNStableInterestModule.ProposerData(proposal.interestAPR)),
            defaultModule: IPWNDefaultModule(defaultModule),
            defaultModuleProposerData: abi.encode(PWNDurationDefaultModule.ProposerData(proposal.duration)),
            liquidationModule: IPWNLiquidationModule(liquidationModule),
            liquidationModuleProposerData: ""
        });
    }

    /**
     * @notice Encode proposal data for EIP-712.
     * @param proposal Proposal struct to be encoded.
     * @return Encoded proposal data.
     */
    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        return abi.encode(proposal);
    }

}
