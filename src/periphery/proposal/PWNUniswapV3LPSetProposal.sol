// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/periphery/lib/Chainlink.sol";
import {
    UniswapV3,
    INonfungiblePositionManager
} from "pwn/periphery/lib/UniswapV3.sol";
import { PWNStableInterestModule } from "pwn/periphery/loan/module/interest/PWNStableInterestModule.sol";
import { PWNDurationDefaultModule } from "pwn/periphery/loan/module/default/PWNDurationDefaultModule.sol";
import { PWNBaseProposal, Terms } from "pwn/periphery/proposal/PWNBaseProposal.sol";


/**
 * @title PWN Uniswap V3 LP Set Proposal
 * @notice Proposal contract for a set of Uniswap V3 LP tokens.
 * Proposal uses Chainlink price feeds to get LP token value in credit token.
 */
contract PWNUniswapV3LPSetProposal is PWNBaseProposal {
    using MultiToken for address;
    using Math for uint256;
    using UniswapV3 for UniswapV3.Config;
    using Chainlink for Chainlink.Config;

    string public constant VERSION = "1.5";

    /** @notice Maximum number of intermediary denominations for price conversion.*/
    uint256 public constant MAX_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice Loan to value decimals.*/
    uint256 public constant LOAN_TO_VALUE_DECIMALS = 4;

    /** @notice Stable interest module used in the proposal.*/
    PWNStableInterestModule public immutable interestModule;
    /** @notice Duration based default module used in the proposal.*/
    PWNDurationDefaultModule public immutable defaultModule;
    /** @notice Uniswap V3 factory contract.*/
    address public immutable uniswapV3Factory;
    /** @notice Uniswap V3 NFT position manager contract.*/
    INonfungiblePositionManager public immutable uniswapNFTPositionManager;
    /** @notice Chainlink feed registry contract.*/
    IChainlinkFeedRegistryLike public immutable chainlinkFeedRegistry;
    /** @notice Chainlink feed for L2 Sequencer uptime. Must be address(0) for L1s.*/
    IChainlinkAggregatorLike public immutable chainlinkL2SequencerUptimeFeed;
    /** @notice WETH address. ETH price feed is used for WETH price.*/
    address public immutable WETH;

    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address[] tokenAAllowlist,address[] tokenBAllowlist,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 interestAPR,uint256 duration,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"
    );

    /**
     * @notice Construct defining a Uniswap LP proposal.
     * @param tokenAAllowlist List of tokenA addresses that are allowed in the LP token pair.
     * @param tokenBAllowlist List of tokenB addresses that are allowed in the LP token pair.
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
        address[] tokenAAllowlist;
        address[] tokenBAllowlist;
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
     * @param collateralId Uniswap LP token ID.
     * @param tokenAIndex Index of tokenA in tokenAAllowlist.
     * @param tokenBIndex Index of tokenB in tokenBAllowlist.
     */
    struct AcceptorValues {
        uint256 collateralId;
        uint256 tokenAIndex;
        uint256 tokenBIndex;
    }

    /** @notice Emitted when a proposal is made via an on-chain transaction.*/
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    /** @notice Thrown when proposal has no minimum credit amount set.*/
    error MinCreditAmountNotSet();
    /** @notice Thrown when proposal credit amount is insufficient.*/
    error InsufficientCreditAmount(uint256 current, uint256 limit);
    /** @notice Thrown when LP token pair is not part of the proposal.*/
    error InvalidLPTokenPair();


    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule,
        address _uniswapV3Factory,
        address _uniswapNFTPositionManager,
        address _chainlinkFeedRegistry,
        address _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNBaseProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNSimpleLoanUniswapV3LPSetProposal", VERSION) {
        interestModule = PWNStableInterestModule(_interestModule);
        defaultModule = PWNDurationDefaultModule(_defaultModule);
        uniswapV3Factory = _uniswapV3Factory;
        uniswapNFTPositionManager = INonfungiblePositionManager(_uniswapNFTPositionManager);
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
     * @notice Get credit amount for a given LP token and loan to value.
     * @param creditAddress Credit token address.
     * @param collateralId LP token ID.
     * @param token0Denominator Flag indicating if token0 should be used as LP value denominator.
     * @param feedIntermediaryDenominations List of intermediary price assets that will be used to fetch prices to get to the correct asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param loanToValue Loan to value ratio with 4 decimals. E.g., 6231 == 0.6231 == 62.31%.
     * @return Amount of credit.
     */
    function getCreditAmount(
        address creditAddress,
        uint256 collateralId,
        bool token0Denominator,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags,
        uint256 loanToValue
    ) public view returns (uint256) {
        (uint256 lpValue, address denominator) = uniswap().getLPValue({
            tokenId: collateralId,
            token0Denominator: token0Denominator
        });

        if (creditAddress != denominator) {
            lpValue = chainlink().convertDenomination({
                amount: lpValue,
                oldDenomination: denominator,
                newDenomination: creditAddress,
                feedIntermediaryDenominations: feedIntermediaryDenominations,
                feedInvertFlags: feedInvertFlags
            });
        }

        return lpValue.mulDiv(loanToValue, 10 ** LOAN_TO_VALUE_DECIMALS);
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

        // Calculate credit amount
        uint256 creditAmount = getCreditAmount(
            proposal.creditAddress,
            acceptorValues.collateralId,
            _checkLPTokenPair(proposal, acceptorValues),
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags,
            proposal.loanToValue
        );

        // Check sufficient credit amount
        if (creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: creditAmount, limit: proposal.minCreditAmount });
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
            collateral: address(uniswapNFTPositionManager).ERC721(acceptorValues.collateralId),
            creditAddress: proposal.creditAddress,
            principal: creditAmount,
            interestModule: address(interestModule),
            interestModuleProposerData: abi.encode(PWNStableInterestModule.ProposerData(proposal.interestAPR)),
            defaultModule: address(defaultModule),
            defaultModuleProposerData: abi.encode(PWNDurationDefaultModule.ProposerData(proposal.duration)),
            liquidationModule: address(0),
            liquidationModuleProposerData: ""
        });
    }

    /** @dev Returns if token0 should be used as LP denominator.*/
    function _checkLPTokenPair(Proposal memory proposal, AcceptorValues memory acceptorValues) internal view returns (bool) {
        (,,address token0, address token1,,,,,,,,) = uniswapNFTPositionManager.positions(acceptorValues.collateralId);
        address tokenA = proposal.tokenAAllowlist[acceptorValues.tokenAIndex];
        address tokenB = proposal.tokenBAllowlist[acceptorValues.tokenBIndex];
        if (token0 == tokenA) {
            if (token1 != tokenB) {
                revert InvalidLPTokenPair();
            }
        } else if (token1 == tokenA) {
            if (token0 != tokenB) {
                revert InvalidLPTokenPair();
            }
        } else {
            revert InvalidLPTokenPair();
        }

        return token0 == tokenA;
    }

    /** @notice Proposal struct that is typecasting dynamic values to bytes32 to enable easy EIP-712 encoding.*/
    struct ERC712Proposal {
        bytes32 tokenAAllowlistHash;
        bytes32 tokenBAllowlistHash;
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

    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            tokenAAllowlistHash: keccak256(abi.encodePacked(proposal.tokenAAllowlist)),
            tokenBAllowlistHash: keccak256(abi.encodePacked(proposal.tokenBAllowlist)),
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

    function uniswap() internal view returns (UniswapV3.Config memory) {
        return UniswapV3.Config({
            positionManager: uniswapNFTPositionManager,
            factory: uniswapV3Factory
        });
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
