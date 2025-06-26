// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/periphery/lib/Chainlink.sol";
import { PWNStableInterestModule, IPWNInterestModule } from "pwn/periphery/loan/module/interest/PWNStableInterestModule.sol";
import { PWNDurationDefaultModule, IPWNDefaultModule } from "pwn/periphery/loan/module/default/PWNDurationDefaultModule.sol";
import { PWNClaimLiquidationModule, IPWNLiquidationModule } from "pwn/periphery/loan/module/liquidation/PWNClaimLiquidationModule.sol";
import { PWNBaseProposal, Terms } from "pwn/periphery/proposal/PWNBaseProposal.sol";


/**
 * @title PWN Elastic Chainlink Proposal
 * @notice Contract for creating and accepting elastic loan proposals using Chainlink oracles.
 * Proposals are elastic, which means that they are not tied to a specific collateral or credit amount.
 * The amount of collateral and credit is specified during the proposal acceptance.
 */
contract PWNElasticChainlinkProposal is PWNBaseProposal {
    using Math for uint256;
    using Chainlink for Chainlink.Config;

    string public constant VERSION = "1.5";

    /** @notice Maximum number of intermediary denominations for price conversion.*/
    uint256 public constant MAX_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice Loan to value decimals. It is used to calculate collateral amount from credit amount.*/
    uint256 public constant LOAN_TO_VALUE_DECIMALS = 4;

    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 interestAPR,uint256 duration,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"
    );

    /** @notice Stable interest module used in the proposal.*/
    PWNStableInterestModule public immutable interestModule;
    /** @notice Duration based default module used in the proposal.*/
    PWNDurationDefaultModule public immutable defaultModule;
    /** @notice LOAN owner claim liquidation module used in the proposal.*/
    PWNClaimLiquidationModule public immutable liquidationModule;
    /** @notice Chainlink feed registry contract.*/
    IChainlinkFeedRegistryLike public immutable chainlinkFeedRegistry;
    /** @notice Chainlink feed for L2 Sequencer uptime. Must be address(0) for L1s.*/
    IChainlinkAggregatorLike public immutable chainlinkL2SequencerUptimeFeed;
    /** @notice WETH address. ETH price feed is used for WETH price.*/
    address public immutable WETH;

    /**
     * @notice Construct defining an elastic chainlink proposal.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param creditAddress Address of an asset which is lended to a borrower.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the collateral asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param loanToValue Loan to value ratio with 4 decimals. E.g., 6231 == 0.6231 == 62.31%.
     * @param interestAPR Accruing interest APR with 2 decimals.
     * @param duration Duration of a loan in seconds.
     * @param minCreditAmount Minimum amount of tokens which can be borrowed using the proposal.
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
        // Credit
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 loanToValue;
        // Interest
        uint256 interestAPR;
        // Default
        uint256 duration;
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
     * @notice Construct defining values provided by an acceptor.
     * @param creditAmount Amount of credit to be borrowed.
     */
    struct AcceptorValues {
        uint256 creditAmount;
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
        address _interestModule,
        address _defaultModule,
        address _liquidationModule,
        address _chainlinkFeedRegistry,
        address _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNBaseProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNElasticChainlinkProposal", VERSION) {
        interestModule = PWNStableInterestModule(_interestModule);
        defaultModule = PWNDurationDefaultModule(_defaultModule);
        liquidationModule = PWNClaimLiquidationModule(_liquidationModule);
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
        }).mulDiv(10 ** LOAN_TO_VALUE_DECIMALS, loanToValue);
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

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        // Check sufficient credit amount
        if (acceptorValues.creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: acceptorValues.creditAmount, limit: proposal.minCreditAmount });
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
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: proposal.collateralId,
                amount: getCollateralAmount(
                    proposal.creditAddress,
                    acceptorValues.creditAmount,
                    proposal.collateralAddress,
                    proposal.feedIntermediaryDenominations,
                    proposal.feedInvertFlags,
                    proposal.loanToValue
                )
            }),
            creditAddress: proposal.creditAddress,
            principal: acceptorValues.creditAmount,
            interestModule: IPWNInterestModule(interestModule),
            interestModuleProposerData: abi.encode(PWNStableInterestModule.ProposerData(proposal.interestAPR)),
            defaultModule: IPWNDefaultModule(defaultModule),
            defaultModuleProposerData: abi.encode(PWNDurationDefaultModule.ProposerData(proposal.duration)),
            liquidationModule: IPWNLiquidationModule(liquidationModule),
            liquidationModuleProposerData: ""
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
        address creditAddress;
        bytes32 feedIntermediaryDenominationsHash;
        bytes32 feedInvertFlagsHash;
        uint256 loanToValue;
        uint256 interestAPR;
        uint256 duration;
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
            collateralCategory: uint8(proposal.collateralCategory),
            collateralAddress: proposal.collateralAddress,
            collateralId: proposal.collateralId,
            creditAddress: proposal.creditAddress,
            feedIntermediaryDenominationsHash: keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            feedInvertFlagsHash: keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            loanToValue: proposal.loanToValue,
            interestAPR: proposal.interestAPR,
            duration: proposal.duration,
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
