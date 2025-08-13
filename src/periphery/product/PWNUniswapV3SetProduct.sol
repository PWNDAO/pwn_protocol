// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IERC721Receiver } from "openzeppelin/token/ERC721/IERC721Receiver.sol";
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
import {
    UniswapV3,
    INonfungiblePositionManager
} from "pwn/periphery/lib/UniswapV3.sol";
import { encodeChainlinkPriceFeedData, decodeChainlinkPriceFeedData } from "pwn/periphery/utils/chainlinkUtils.sol";
import { PWNRevokedNonce } from "pwn/periphery/auxiliary/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/periphery/auxiliary/PWNUtilizedCredit.sol";


/**
 * @title PWNUniswapV3SetProduct
 * @dev Implements logic for using Uniswap V3 LP tokens as collateral in lending protocols.
 * Handles price and duration-based defaults and liquidation processes.
 * In case of liquidation, any value surplus after debt repayment is returned to the borrower.
 */
contract PWNUniswapV3SetProduct is IPWNProduct, IERC721Receiver {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;
    using Math for uint256;
    using SafeCast for uint256;
    using UniswapV3 for UniswapV3.Config;
    using Chainlink for Chainlink.Config;

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    string public constant NAME = "PWN Uniswap V3 Set Product";
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

    /** @dev Uniswap V3 configuration struct for LP value operations.*/
    UniswapV3.Config internal _uniswap;
    /** @dev Chainlink configuration struct for price feed operations.*/
    Chainlink.Config internal _chainlink;

    /** @dev EIP-712 domain separator for proposal contracts.*/
    bytes32 public immutable DOMAIN_SEPARATOR;
    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address[] tokenAAllowlist,address[] tokenBAllowlist,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 acceptableLoanToValue,uint256 interestAPR,uint256 duration,uint256 liquidationLoanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,bytes32 proposerSpecHash,address loanContract)"
    );

    /**
     * @notice Construct defining a Uniswap LP proposal.
     * @param tokenAAllowlist List of tokenA addresses that are allowed in the LP token pair.
     * @param tokenBAllowlist List of tokenB addresses that are allowed in the LP token pair.
     * @param creditAddress Address of an asset which is lended to a borrower.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the collateral asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param acceptableLoanToValue The acceptable loan-to-value ratio (LTV) with LOAN_TO_VALUE_DECIMALS decimals. For lender, it's the maxium acceptable LTV, for borrower it's the LTV they are willing to accept.
     * @param interestAPR Accruing interest APR with APR_DECIMALS decimals.
     * @param duration Duration of a loan in seconds.
     * @param liquidationLoanToValue Liquidation loan to value ratio with LOAN_TO_VALUE_DECIMALS decimals. It is used to calculate liquidation value of a loan.
     * @param minCreditAmount Minimum amount of tokens which can be borrowed using the proposal.
     * @param availableCreditLimit Available credit limit for the proposal. It is the maximum amount of tokens which can be borrowed using the proposal. If non-zero, proposal can be accepted more than once, until the credit limit is reached.
     * @param utilizedCreditId Id of utilized credit. Can be shared between multiple proposals.
     * @param nonceSpace Nonce space of a proposal nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical proposals in time. Without it, it would be impossible to make again proposal, which was once revoked. Can be used to create a group of proposals, where accepting one proposal will make other proposals in the group revoked.
     * @param expiration Proposal expiration timestamp in seconds.
     * @param proposerSpecHash Hash of a proposer specific data, which must be provided during a loan creation.
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
        address loanContract;
    }

    /**
     * @notice Construct defining values provided by an acceptor.
     * @param collateralId Uniswap LP token ID.
     * @param tokenAIndex Index of tokenA in tokenAAllowlist.
     * @param tokenBIndex Index of tokenB in tokenBAllowlist.
     * @param creditAmount Amount of credit that will be borrowed.
     */
    struct AcceptorValues {
        uint256 collateralId;
        uint256 tokenAIndex;
        uint256 tokenBIndex;
        uint256 creditAmount;
    }

    /**
     * @notice Struct containing loan data for interest, default, and liquidation logic.
     * @param apr Annual Percentage Rate (APR) for interest calculation, scaled by APR_DECIMALS.
     * @param defaultTimestamp Timestamp when the loan is considered defaulted.
     * @param lltv Liquidation loan-to-value ratio, scaled by LOAN_TO_VALUE_DECIMALS.
     * @param token0Denominator Flag indicating if token0 is used as LP value denominator.
     * @param feedData Encoded Chainlink feed data for price conversion.
     */
    struct LoanData {
        uint40 apr;
        uint40 defaultTimestamp;
        uint16 lltv;
        bool token0Denominator;
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
    /** @notice Thrown when LP token pair is not part of the proposal.*/
    error InvalidLPTokenPair();
    /** @notice Thrown when the provided LLTV is invalid.*/
    error InvalidLiquidationLoanToValue();
    /** @notice Thrown when the acceptable loan to value is above 1.0.*/
    error InvalidAcceptableLoanToValue();
    /** @notice Thrown when the liquidation data is not empty.*/
    error LiquidationDataNotEmpty();
    /** @notice Thrown when liquidated loan is not initialized in this module.*/
    error LoanNotInitialized();
    /** @notice Thrown when the duration is less than the minimum allowed duration.*/
    error DurationTooShort();
    /** @notice Thrown when the loan to value is outside of acceptable limits for the proposal.*/
    error InvalidLoanToValue(uint256 current, uint256 limit);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        PWNHub _hub,
        PWNRevokedNonce _revokedNonce,
        PWNUtilizedCredit _utilizedCredit,
        address _uniswapV3Factory,
        INonfungiblePositionManager _uniswapNFTPositionManager,
        IChainlinkFeedRegistryLike _chainlinkFeedRegistry,
        IChainlinkAggregatorLike _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) {
        hub = PWNHub(_hub);
        revokedNonce = PWNRevokedNonce(_revokedNonce);
        utilizedCredit = PWNUtilizedCredit(_utilizedCredit);
        _uniswap.positionManager = _uniswapNFTPositionManager;
        _uniswap.factory = _uniswapV3Factory;
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
    |*  # LP VALUE                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get the LP value of a Uniswap V3 position in credit asset.
     * @dev Feed direction is from LP denominator to credit denominator.
     * @param creditAddress Credit token address.
     * @param collateralId LP token ID.
     * @param token0Denominator Flag indicating if token0 should be used as LP value denominator.
     * @param feedIntermediaryDenominations List of intermediary price assets that will be used to fetch prices to get to the correct asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @return Amount of credit.
     */
    function getLPValue(
        address creditAddress,
        uint256 collateralId,
        bool token0Denominator,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) public view returns (uint256) {
        (uint256 lpValue, address denominator) = _uniswap.getLPValue(collateralId, token0Denominator);

        if (creditAddress != denominator) {
            lpValue = _chainlink.convertDenomination({
                amount: lpValue,
                oldDenomination: denominator,
                newDenomination: creditAddress,
                feedIntermediaryDenominations: feedIntermediaryDenominations,
                feedInvertFlags: feedInvertFlags
            });
        }

        return lpValue;
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL                                              *|
    |*----------------------------------------------------------*/

    function acceptProposal(
        uint256 loanId,
        address /* acceptor */,
        address proposer,
        bytes calldata proposalData
    ) override external returns (Terms memory loanTerms) {
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

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        // Check sufficient credit amount
        if (acceptorValues.creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: acceptorValues.creditAmount, limit: proposal.minCreditAmount });
        }

        if (proposal.acceptableLoanToValue == 0) {
            // If acceptable LTV is zero, it is invalid
            revert InvalidAcceptableLoanToValue();
        } else if (proposal.acceptableLoanToValue > 10 ** LOAN_TO_VALUE_DECIMALS) {
            // If acceptable LTV is above 1.0, it is invalid
            revert InvalidAcceptableLoanToValue();
        }

        if (proposal.liquidationLoanToValue < proposal.acceptableLoanToValue) {
            // If LLTV is less than acceptable LTV, it is invalid
            revert InvalidLiquidationLoanToValue();
        } else if (proposal.liquidationLoanToValue > 10 ** LOAN_TO_VALUE_DECIMALS) {
            // If LLTV is above 1.0, it is invalid
            revert InvalidLiquidationLoanToValue();
        }

        // Check duration
        if (proposal.duration < MIN_DURATION) {
            revert DurationTooShort();
        }

        // Check proposal is not revoked
        if (!revokedNonce.isNonceUsable(proposer, proposal.nonceSpace, proposal.nonce)) {
            revert PWNRevokedNonce.NonceNotUsable({
                addr: proposer,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce
            });
        }

        if (proposal.availableCreditLimit == 0) {
            // Revoke nonce if credit limit is 0, proposal can be accepted only once
            revokedNonce.revokeNonce(proposer, proposal.nonceSpace, proposal.nonce);
        } else {
            // Update utilized credit
            // Note: This will revert if utilized credit would exceed the available credit limit
            utilizedCredit.utilizeCredit(proposer, proposal.utilizedCreditId, acceptorValues.creditAmount, proposal.availableCreditLimit);
        }

        bool token0Denominator = _checkLPTokenPair(proposal, acceptorValues);

        // Calculate credit amount
        uint256 lpValue = getLPValue(
            proposal.creditAddress,
            acceptorValues.collateralId,
            token0Denominator,
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags
        );

        // Check if the LTV is below the maximum acceptable LTV
        uint256 ltv = acceptorValues.creditAmount.mulDiv(10 ** LOAN_TO_VALUE_DECIMALS, lpValue);
        if (ltv > proposal.acceptableLoanToValue) {
            revert InvalidLoanToValue(ltv, proposal.acceptableLoanToValue);
        }

        // Store data for the loan interest, default, and liquidation modules
        loanData[msg.sender][loanId] = LoanData({
            apr: proposal.interestAPR.toUint40(),
            defaultTimestamp: (block.timestamp + proposal.duration).toUint40(),
            lltv: proposal.liquidationLoanToValue.toUint16(),
            token0Denominator: token0Denominator,
            feedData: encodeChainlinkPriceFeedData(
                proposal.feedInvertFlags,
                proposal.feedIntermediaryDenominations,
                MAX_INTERMEDIARY_DENOMINATIONS
            )
        });

        // Create loan terms object
        return Terms({
            isProposerLender: true,
            proposerSpecHash: proposal.proposerSpecHash,
            collateral: address(_uniswap.positionManager).ERC721(acceptorValues.collateralId),
            creditAddress: proposal.creditAddress,
            principal: acceptorValues.creditAmount
        });
    }

    function nameAndVersion() external pure returns (string memory name, string memory version) {
        return (NAME, VERSION);
    }

    function hashProposalTypedData(bytes calldata proposalData) external pure returns (bytes32) {
        Proposal memory proposal = abi.decode(proposalData, (Proposal));
        return keccak256(abi.encodePacked(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal)));
    }


    /*----------------------------------------------------------*|
    |*  # INTEREST                                              *|
    |*----------------------------------------------------------*/

    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        if (block.timestamp < loan.lastUpdateTimestamp) return 0;

        return loan.principal.mulDiv(
            uint256(loanData[loanContract][loanId].apr).mulDiv(block.timestamp - loan.lastUpdateTimestamp, 365 days),
            10 ** APR_DECIMALS
        );
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

        uint256 defaultValue = getLPValue(
            loan.creditAddress,
            loan.collateral.id,
            data.token0Denominator,
            feedIntermediaryDenominations,
            feedInvertFlags
        ).mulDiv(data.lltv, 10 ** LOAN_TO_VALUE_DECIMALS);

        return PWNLoan(loanContract).getLOANDebt(loanId) >= defaultValue;
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

        uint256 lpLiquidationValue = getLPValue(
            creditAddress,
            collateral.id,
            data.token0Denominator,
            feedIntermediaryDenominations,
            feedInvertFlags
        ).mulDiv(data.lltv, 10 ** LOAN_TO_VALUE_DECIMALS);

        if (lpLiquidationValue > debt) {
            credit.amount = lpLiquidationValue - debt;
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
    |*  # ERC721 RECEIVED HOOK                                  *|
    |*----------------------------------------------------------*/

    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * @return `IERC721Receiver.onERC721Received.selector` if transfer is allowed
     */
    function onERC721Received(
        address /* operator */,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) override external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /** @dev Returns if token0 should be used as LP denominator.*/
    function _checkLPTokenPair(Proposal memory proposal, AcceptorValues memory acceptorValues) internal view returns (bool) {
        (,,address token0, address token1,,,,,,,,) = _uniswap.positionManager.positions(acceptorValues.collateralId);
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
        uint256 acceptableLoanToValue;
        uint256 interestAPR;
        uint256 duration;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        bytes32 proposerSpecHash;
        address loanContract;
    }

    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            tokenAAllowlistHash: keccak256(abi.encodePacked(proposal.tokenAAllowlist)),
            tokenBAllowlistHash: keccak256(abi.encodePacked(proposal.tokenBAllowlist)),
            creditAddress: proposal.creditAddress,
            feedIntermediaryDenominationsHash: keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            feedInvertFlagsHash: keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            acceptableLoanToValue: proposal.acceptableLoanToValue,
            interestAPR: proposal.interestAPR,
            duration: proposal.duration,
            minCreditAmount: proposal.minCreditAmount,
            availableCreditLimit: proposal.availableCreditLimit,
            utilizedCreditId: proposal.utilizedCreditId,
            nonceSpace: proposal.nonceSpace,
            nonce: proposal.nonce,
            expiration: proposal.expiration,
            proposerSpecHash: proposal.proposerSpecHash,
            loanContract: proposal.loanContract
        });
        return abi.encode(erc712Proposal);
    }

}
