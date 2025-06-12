// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IMultiTokenCategoryRegistry } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNConfig } from "pwn/core/config/PWNConfig.sol";
import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNBorrowerCreateHook, BORROWER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNBorrowerCreateHook.sol";
import { IPWNBorrowerCollateralRepaymentHook, BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNBorrowerCollateralRepaymentHook.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderCreateHook.sol";
import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";
import { IPWNModuleInitializationHook } from "pwn/core/loan/module/IPWNModuleInitializationHook.sol";
import { IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { LOANStatus } from "pwn/core/loan/LOANStatus.sol";
import { LoanTerms as Terms } from "pwn/core/loan/LoanTerms.sol";
import { PWNVault } from "pwn/core/loan/PWNVault.sol";
import { IPWNProposal } from "pwn/core/proposal/IPWNProposal.sol";
import { IERC5646 } from "pwn/core/token/IERC5646.sol";
import { IPWNLoanMetadataProvider } from "pwn/core/token/IPWNLoanMetadataProvider.sol";
import { PWNLOAN } from "pwn/core/token/PWNLOAN.sol";

/**
 * @title PWN Loan
 * @notice Contract managing loans in PWN protocol.
 * @dev Acts as a vault for every loan created by this contract.
 */
contract PWNLoan is PWNVault, IERC5646, IPWNLoanMetadataProvider {
    using MultiToken for address;

    string public constant VERSION = "1.5";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 internal constant _EMPTY_LENDER_SPEC_HASH = keccak256(abi.encode(LenderSpec(IPWNLenderCreateHook(address(0)), "", IPWNLenderRepaymentHook(address(0)), "")));
    bytes32 internal constant _EMPTY_BORROWER_SPEC_HASH = keccak256(abi.encode(BorrowerSpec(IPWNBorrowerCreateHook(address(0)), "")));

    PWNHub public immutable hub;
    PWNLOAN public immutable loanToken;
    PWNConfig public immutable config;
    IMultiTokenCategoryRegistry public immutable categoryRegistry;

    /**
     * @notice Loan proposal specification during loan creation.
     * @param proposalContract Address of a loan proposal contract.
     * @param proposalData Encoded proposal data that is passed to the loan proposal contract.
     * @param proposalInclusionProof Inclusion proof of the proposal in the proposal contract.
     * @param signature Signature of the proposal.
     */
    struct ProposalSpec {
        address proposalContract;
        bytes proposalData;
        bytes32[] proposalInclusionProof;
        bytes signature;
    }

    /**
     * @notice Struct defining a lender specification.
     * @param createHook Lender create hook that is called during loan creation.
     * @param createHookData Data passed to the lender create hook.
     * @param repaymentHook Lender repayment hook that is called during loan repayment.
     * @param repaymentHookData Data passed to the lender repayment hook.
     */
    struct LenderSpec {
        IPWNLenderCreateHook createHook;
        bytes createHookData;
        IPWNLenderRepaymentHook repaymentHook;
        bytes repaymentHookData;
    }

    /**
     * @notice Struct defining a borrower specification.
     * @param createHook Borrower create hook that is called during loan creation.
     * @param createHookData Data passed to the borrower create hook.
     */
    struct BorrowerSpec {
        IPWNBorrowerCreateHook createHook;
        bytes createHookData;
    }

    /**
     * @notice Struct defining a loan.
     * @param borrower Address of a borrower.
     * @param lastUpdateTimestamp Unix timestamp (in seconds) of the last loan update.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     * @param creditAddress Address of an asset used as a loan credit.
     * @param principal Principal amount in credit asset tokens.
     * @param pastAccruedInterest Accrued interest amount in credit asset tokens before `lastUpdateTimestamp`.
     * @param unclaimedRepayment Amount of the credit asset that can be claimed by loan owner.
     * @param interestModule Address of an interest module. It is a contract which defines the interest conditions.
     * @param defaultModule Address of a default module. It is a contract which defines the default conditions.
     * @param liquidationModule Address that can call liquidation for defaulted loans.
     */
    struct LOAN {
        address borrower;
        uint40 lastUpdateTimestamp;
        MultiToken.Asset collateral;
        address creditAddress;
        uint256 principal;
        uint256 pastAccruedInterest;
        uint256 unclaimedRepayment;
        IPWNInterestModule interestModule;
        IPWNDefaultModule defaultModule;
        IPWNLiquidationModule liquidationModule;
    }

    /** Mapping of all LOAN data by loan id.*/
    mapping (uint256 => LOAN) private LOANs;

    struct LenderRepaymentHookData {
        IPWNLenderRepaymentHook hook;
        bytes data;
    }

    /** @notice Mapping of lender repayment hook data per loan id.*/
    mapping (address => mapping (uint256 => LenderRepaymentHookData)) public lenderRepaymentHook;

    /** @notice Mapping of loan id to whether the loan context is locked.*/
    mapping (uint256 => bool) public loanLock;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a new loan in created.*/
    event LOANCreated(uint256 indexed loanId, bytes32 indexed proposalHash, address indexed proposalContract, Terms terms, LenderSpec lenderSpec, BorrowerSpec borrowerSpec, bytes extra);
    /** @notice Emitted when a loan repayment is made.*/
    event LOANRepaid(uint256 indexed loanId, uint256 repaymentAmount, uint256 indexed newPrincipal);
    /** @notice Emitted when a loan repayment is claimed.*/
    event LOANRepaymentClaimed(uint256 indexed loanId, uint256 claimedAmount);
    /** @notice Emitted when a loan collateral is liquidated.*/
    event LOANLiquidated(uint256 indexed loanId, address indexed liquidator, uint256 liquidationAmount);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when a call tries to enter locked loan context.*/
    error LoanContextLocked(uint256 loanId);
    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when managed loan is not running.*/
    error LoanNotRunning();
    /** @notice Thrown when managed loan is not defaulted.*/
    error LoanNotDefaulted();
    /** @notice Thrown when caller is not a LOAN token holder.*/
    error CallerNotLOANTokenHolder();
    /** @notice Thrown when hash of provided proposer spec doesn't match the one in loan terms.*/
    error InvalidProposerSpecHash(bytes32 current, bytes32 expected);
    /** @notice Thrown when caller is not a vault.*/
    error CallerNotVault();
    /** @notice Thrown when MultiToken.Asset is invalid because of invalid category, address, id or amount.*/
    error InvalidMultiTokenAsset(uint8 category, address addr, uint256 id, uint256 amount);
    /** @notice Thrown when repayment amount is out of bounds.*/
    error InvalidRepaymentAmount(uint256 current, uint256 limit);
    /** @notice Thrown when nothing can be claimed.*/
    error NothingToClaim();
    /** @notice Thrown when hook returns an invalid value.*/
    error InvalidHookReturnValue(bytes32 expected, bytes32 current);
    /** @notice Thrown when liquidation caller is not a liquidation module.*/
    error CallerNotLiquidationModule();
    /** @notice Thrown when caller is not a loan borrower.*/
    error CallerNotBorrower();
    /** @notice Thrown when hook is not set or is zero address.*/
    error HookZeroAddress();
    /** @notice Thrown when loan is defaulted on creation.*/
    error DefaultedOnCreation();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address _hub,
        address _loanToken,
        address _config,
        address _categoryRegistry
    ) {
        hub = PWNHub(_hub);
        loanToken = PWNLOAN(_loanToken);
        config = PWNConfig(_config);
        categoryRegistry = IMultiTokenCategoryRegistry(_categoryRegistry);
    }


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier nonLoanContextReentrant(uint256 loanId) {
        _lockLoanContext(loanId);
        _;
        _unlockLoanContext(loanId);
    }

    function _lockLoanContext(uint256 loanId) private {
        if (loanLock[loanId]) revert LoanContextLocked(loanId);
        loanLock[loanId] = true;
    }

    function _unlockLoanContext(uint256 loanId) private {
        loanLock[loanId] = false;
    }


    /*----------------------------------------------------------*|
    |*  # CREATE LOAN                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Create a new loan.
     * @dev The function assumes a prior token approval to a contract address.
     * @param proposalSpec Proposal specification struct.
     * @param lenderSpec Lender specification struct.
     * @param borrowerSpec Borrower specification struct.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return loanId Id of the created LOAN token.
     */
    function create(
        ProposalSpec calldata proposalSpec,
        LenderSpec calldata lenderSpec,
        BorrowerSpec calldata borrowerSpec,
        bytes calldata extra
    ) external returns (uint256 loanId) {
        // Accept proposal and get loan terms
        _checkHubTag(proposalSpec.proposalContract, PWNHubTags.LOAN_PROPOSAL);
        Terms memory loanTerms = IPWNProposal(proposalSpec.proposalContract)
            .acceptProposal({
                acceptor: msg.sender,
                proposalData: proposalSpec.proposalData,
                proposalInclusionProof: proposalSpec.proposalInclusionProof,
                signature: proposalSpec.signature
            });

        // Check that provided proposer spec is correct
        bytes32 proposerSpecHash = msg.sender == loanTerms.lender
            ? getBorrowerSpecHash(borrowerSpec)
            : getLenderSpecHash(lenderSpec);
        if (proposerSpecHash != loanTerms.proposerSpecHash) {
            revert InvalidProposerSpecHash({ current: proposerSpecHash, expected: loanTerms.proposerSpecHash });
        }

        // Check loan credit and collateral validity
        _checkValidAsset(loanTerms.creditAddress.ERC20(loanTerms.principal));
        _checkValidAsset(loanTerms.collateral);

        // Mint LOAN token for lender
        loanId = loanToken.mint(loanTerms.lender);

        // Store loan data under loan id
        LOAN storage loan = LOANs[loanId];
        loan.borrower = loanTerms.borrower;
        loan.lastUpdateTimestamp = uint40(block.timestamp);
        loan.creditAddress = loanTerms.creditAddress;
        loan.principal = loanTerms.principal;
        loan.collateral = loanTerms.collateral;
        loan.interestModule = loanTerms.interestModule;
        loan.defaultModule = loanTerms.defaultModule;
        loan.liquidationModule = loanTerms.liquidationModule;

        // Lock loan context to prevent reentrancy
        _lockLoanContext(loanId);

        emit LOANCreated({
            loanId: loanId,
            proposalHash: loanTerms.proposalHash,
            proposalContract: proposalSpec.proposalContract,
            terms: loanTerms,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: extra
        });

        // Store lender repayment hook
        // Note: hook tag check is not required here; would fail on repayment
        if (address(lenderSpec.repaymentHook) != address(0)) {
            lenderRepaymentHook[loanTerms.lender][loanId] = LenderRepaymentHookData({
                hook: lenderSpec.repaymentHook,
                data: lenderSpec.repaymentHookData
            });
        }

        // Note: !! DANGER ZONE !!

        // Initialize modules
        _initializeModule(address(loanTerms.interestModule), INTEREST_MODULE_INIT_HOOK_RETURN_VALUE, loanId, loanTerms.interestModuleProposerData);
        _initializeModule(address(loanTerms.defaultModule), DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE, loanId, loanTerms.defaultModuleProposerData);
        _initializeModule(address(loanTerms.liquidationModule), LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE, loanId, loanTerms.liquidationModuleProposerData);

        // Check that loan is not defaulted on creation
        if (IPWNDefaultModule(loanTerms.defaultModule).isDefaulted(address(this), loanId)) {
            revert DefaultedOnCreation();
        }

        // Settle the loan
        _settleNewLoan(loanTerms, lenderSpec, borrowerSpec);

        _unlockLoanContext(loanId);
    }

    /** @dev Initialize module by checking PWN Hub tag and call initialization hook.*/
    function _initializeModule(
        address module,
        bytes32 expectedReturnValue,
        uint256 loanId,
        bytes memory proposerData
    ) internal {
        // Check PWN Hub tag
        _checkHubTag(module, PWNHubTags.MODULE);
        // Call module initialization hook
        bytes32 hookReturnValue = IPWNModuleInitializationHook(module).onLoanCreated(loanId, proposerData);
        if (hookReturnValue != expectedReturnValue) {
            revert InvalidHookReturnValue({ expected: expectedReturnValue, current: hookReturnValue });
        }
    }

    /**
     * @notice Transfer collateral to Vault and credit to borrower.
     * @dev The function assumes a prior token approval to a contract address.
     * @param loanTerms Loan terms struct.
     * @param lenderSpec Lender specification struct.
     * @param borrowerSpec Borrower specification struct.
     */
    function _settleNewLoan(
        Terms memory loanTerms,
        LenderSpec calldata lenderSpec,
        BorrowerSpec calldata borrowerSpec
    ) private {
        // Call lender create hook
        if (address(lenderSpec.createHook) != address(0)) {
            _checkHubTag(address(lenderSpec.createHook), PWNHubTags.HOOK);
            bytes32 hookReturnValue = lenderSpec.createHook.onLoanCreated(
                loanTerms.lender,
                loanTerms.creditAddress,
                loanTerms.principal,
                lenderSpec.createHookData
            );
            if (hookReturnValue != LENDER_CREATE_HOOK_RETURN_VALUE) {
                revert InvalidHookReturnValue({ expected: LENDER_CREATE_HOOK_RETURN_VALUE, current: hookReturnValue });
            }
        }

        // Calculate fee amount and new loan amount
        (uint256 feeAmount, uint256 newLoanAmount) = _calculateFeeAmount(config.fee(), loanTerms.principal);

        // Note: `creditHelper` must not be used before updating the amount.
        MultiToken.Asset memory creditHelper = MultiToken.ERC20(loanTerms.creditAddress, loanTerms.principal);

        // Collect fees
        if (feeAmount > 0) {
            creditHelper.amount = feeAmount;
            _pushFrom(creditHelper, loanTerms.lender, config.feeCollector());
        }

        // Transfer credit to borrower
        creditHelper.amount = newLoanAmount;
        _pushFrom(creditHelper, loanTerms.lender, loanTerms.borrower);

        // Call borrower create hook
        if (address(borrowerSpec.createHook) != address(0)) {
            _checkHubTag(address(borrowerSpec.createHook), PWNHubTags.HOOK);
            bytes32 hookReturnValue = borrowerSpec.createHook.onLoanCreated(
                loanTerms.borrower,
                loanTerms.collateral,
                loanTerms.creditAddress,
                newLoanAmount,
                borrowerSpec.createHookData
            );
            if (hookReturnValue != BORROWER_CREATE_HOOK_RETURN_VALUE) {
                revert InvalidHookReturnValue({ expected: BORROWER_CREATE_HOOK_RETURN_VALUE, current: hookReturnValue });
            }
        }

        // Transfer collateral to Vault
        _pull(loanTerms.collateral, loanTerms.borrower);
    }

    /**
     * @notice Calculate fee amount.
     * @param fee Fee value in basis points. Value of 100 is 1% fee.
     * @param loanAmount Amount of an asset used as a loan credit.
     * @return feeAmount Amount of a loan asset that represents a protocol fee.
     * @return newLoanAmount New amount of a loan credit asset, after deducting protocol fee.
     */
    function _calculateFeeAmount(
        uint16 fee,
        uint256 loanAmount
    ) internal pure returns (uint256 feeAmount, uint256 newLoanAmount) {
        if (fee == 0) return (0, loanAmount);

        feeAmount = Math.mulDiv(loanAmount, fee, 1e4);
        newLoanAmount = loanAmount - feeAmount;
    }


    /*----------------------------------------------------------*|
    |*  # REPAY LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Repay running loan.
     * @dev Any address can repay a running loan, but a collateral will be transferred to
     * a borrower address associated with the loan.
     * @dev The function assumes a prior token approval to Loan contract.
     * @param loanId Id of a loan that is being repaid.
     * @param repaymentAmount Amount of a credit asset to be repaid. Use 0 to repay the whole loan.
     */
    function repay(uint256 loanId, uint256 repaymentAmount) external nonLoanContextReentrant(loanId) {
        _repay(loanId, repaymentAmount, address(0), "");
    }

    /**
     * @notice Repay running loan with collateral.
     * @dev Only a borrower can repay a running loan with collateral.
     * @dev The function transfers collateral to repayment hook before calling it,
     * expecting approval and full repayment amount at the end of execution.
     * @param loanId Id of a loan that is being repaid.
     * @param borrowerHook Borrower repayment hook.
     * @param borrowerHookData Data passed to the borrower repayment hook.
     */
    function repayWithCollateral(
        uint256 loanId,
        IPWNBorrowerCollateralRepaymentHook borrowerHook,
        bytes calldata borrowerHookData
    ) external nonLoanContextReentrant(loanId) {
        LOAN storage loan = LOANs[loanId];

        // Caller must be borrower
        if (loan.borrower != msg.sender) revert CallerNotBorrower();
        // Check that hook is set
        if (address(borrowerHook) == address(0)) revert HookZeroAddress();

        _repay(loanId, 0, address(borrowerHook), borrowerHookData);
    }

    function _repay(
        uint256 loanId,
        uint256 repaymentAmount,
        address borrowerHook,
        bytes memory borrowerHookData
    ) internal {
        LOAN storage loan = LOANs[loanId];

        // Check that loan is running
        uint8 status = getLOANStatus(loanId);
        if (status != LOANStatus.RUNNING) revert LoanNotRunning();

        // Check repayment amount
        uint256 debt = getLOANDebt(loanId);
        if (repaymentAmount == 0) {
            repaymentAmount = debt;
        } else if (repaymentAmount > debt) {
            revert InvalidRepaymentAmount({ current: repaymentAmount, limit: debt });
        }

        // Note: The accrued interest is repaid first, then principal.

        // Decrease debt by the repayment amount
        uint256 interest = debt - loan.principal;
        loan.pastAccruedInterest = repaymentAmount < interest ? interest - repaymentAmount : 0;
        loan.principal -= repaymentAmount > interest ? repaymentAmount - interest : 0;
        loan.lastUpdateTimestamp = uint40(block.timestamp);

        emit LOANRepaid({ loanId: loanId, repaymentAmount: repaymentAmount, newPrincipal: loan.principal });

        // Note: Repayment is transferred from sender, or borrower hook if set
        address repaymentOrigin = msg.sender;

        // Settle collateral
        if (loan.principal == 0) {
            if (borrowerHook == address(0)) {
                _push(loan.collateral, loan.borrower);
            } else {
                repaymentOrigin = borrowerHook;
                _callBorrowerHook(loan, repaymentAmount, borrowerHook, borrowerHookData);
            }
        }

        // Settle repayment
        _settleRepayment(loanId, repaymentOrigin, loan.creditAddress, repaymentAmount);

        // Delete loan if fully repaid and claimed
        if (loan.principal == 0 && loan.unclaimedRepayment == 0) {
            _deleteLoan(loanId);
        }
    }

    function _callBorrowerHook(
        LOAN storage loan,
        uint256 repaymentAmount,
        address borrowerHook,
        bytes memory borrowerHookData
    ) internal {
        // Check that hook has PWN Hub tag
        _checkHubTag(borrowerHook, PWNHubTags.HOOK);

        // Transfer collateral to borrower hook
        _push(loan.collateral, borrowerHook);

        // Call borrower collateral repayment hook
        bytes32 hookReturnValue = IPWNBorrowerCollateralRepaymentHook(borrowerHook).onLoanRepaid({
            borrower: loan.borrower,
            collateral: loan.collateral,
            creditAddress: loan.creditAddress,
            repayment: repaymentAmount,
            borrowerData: borrowerHookData
        });
        if (hookReturnValue != BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE) {
            revert InvalidHookReturnValue({ expected: BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE, current: hookReturnValue });
        }
    }

    function _settleRepayment(
        uint256 loanId,
        address repaymentOrigin,
        address creditAddress,
        uint256 repaymentAmount
    ) internal {
        // Note: Repayment is transferred into the Vault if the hook reverts.

        address loanOwner = loanToken.ownerOf(loanId);
        try this.tryCallLenderRepaymentHook({
            hookData: lenderRepaymentHook[loanOwner][loanId],
            repaymentOrigin: repaymentOrigin,
            loanOwner: loanOwner,
            creditAddress: creditAddress,
            repaymentAmount: repaymentAmount
        }) {} catch {
            // Update unclaimed repayment amount
            LOANs[loanId].unclaimedRepayment += repaymentAmount;
            // Transfer repayment amount to vault
            _pull(creditAddress.ERC20(repaymentAmount), repaymentOrigin);
        }
    }

    function tryCallLenderRepaymentHook(
        LenderRepaymentHookData memory hookData,
        address repaymentOrigin,
        address loanOwner,
        address creditAddress,
        uint256 repaymentAmount
    ) external {
        if (msg.sender != address(this)) revert CallerNotVault();
        if (address(hookData.hook) == address(0)) revert HookZeroAddress();
        _checkHubTag(address(hookData.hook), PWNHubTags.HOOK);

        // Transfer repayment to lender repayment hook
        _pushFrom(creditAddress.ERC20(repaymentAmount), repaymentOrigin, address(hookData.hook));

        // Call hook and check hooks return value
        bytes32 hookReturnValue = hookData.hook.onLoanRepaid(loanOwner, creditAddress, repaymentAmount, hookData.data);
        if (hookReturnValue != LENDER_REPAYMENT_HOOK_RETURN_VALUE) {
            revert InvalidHookReturnValue({ expected: LENDER_REPAYMENT_HOOK_RETURN_VALUE, current: hookReturnValue });
        }
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Claim a loan repayment.
     * @dev Only a loan owner can claim a loan repayment.
     * @param loanId Id of a loan that is being claimed.
     */
    function claimRepayment(uint256 loanId) external nonLoanContextReentrant(loanId) {
        // Check that caller is LOAN token holder
        if (loanToken.ownerOf(loanId) != msg.sender) revert CallerNotLOANTokenHolder();

        LOAN storage loan = LOANs[loanId];
        // Check that there is something to claim
        if (loan.unclaimedRepayment == 0) revert NothingToClaim();

        emit LOANRepaymentClaimed({ loanId: loanId, claimedAmount: loan.unclaimedRepayment });

        MultiToken.Asset memory unclaimedCredit = loan.creditAddress.ERC20(loan.unclaimedRepayment);

        if (loan.principal == 0) {
            // Loan is fully repaid, claiming the unclaimed amount deletes the loan
            _deleteLoan(loanId);
        } else {
            // Loan is still RUNNING or DEFAULTED
            loan.unclaimedRepayment = 0;
        }

        // Transfer unclaimed amount to the loan owner
        _push(unclaimedCredit, msg.sender);
    }

    /**
     * @notice Delete loan data and burn LOAN token.
     * @param loanId Id of a loan that is being deleted.
     */
    function _deleteLoan(uint256 loanId) private {
        loanToken.burn(loanId);
        delete LOANs[loanId];
    }


    /*----------------------------------------------------------*|
    |*  # LIQUIDATE LOAN                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Liquidate a defaulted loan by a liquidation module.
     * @dev The liquidation module can use any amount of credit asset to be repaid to lender for the liquidation.
     * @param loanId Id of a loan that is being liquidated.
     * @param data Additional data passed to the liquidation module.
     */
    function liquidate(uint256 loanId, bytes calldata data) external nonLoanContextReentrant(loanId) {
        uint8 status = getLOANStatus(loanId);
        if (status != LOANStatus.DEFAULTED) revert LoanNotDefaulted();

        LOAN storage loan = LOANs[loanId];

        // Get debt before updating the loan
        uint256 debt = getLOANDebt(loanId);

        // Update loan data
        loan.pastAccruedInterest = 0;
        loan.principal = 0;
        loan.lastUpdateTimestamp = uint40(block.timestamp);

        IPWNLiquidationModule liquidationModule = loan.liquidationModule;

        // Execute liquidation
        _push(loan.collateral, address(liquidationModule));
        uint256 liquidationAmount = liquidationModule.liquidate({
            loanId: loanId,
            liquidator: msg.sender,
            debt: debt,
            creditAddress: loan.creditAddress,
            collateral: loan.collateral,
            data: data
        });
        if (liquidationAmount > 0) {
            _settleRepayment(loanId, address(liquidationModule), loan.creditAddress, liquidationAmount);
        }

        // Emit liquidation event
        emit LOANLiquidated({
            loanId: loanId,
            liquidator: address(liquidationModule),
            liquidationAmount: liquidationAmount
        });

        // If the loan is fully claimed, delete it
        if (loan.unclaimedRepayment == 0) {
            _deleteLoan(loanId);
        }
    }


    /*----------------------------------------------------------*|
    |*  # GET LOAN                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return a LOAN data struct associated with a loan id.
     * @param loanId Id of a loan.
     * @return loan LOAN data struct.
     */
    function getLOAN(uint256 loanId) external view returns (LOAN memory) {
        return LOANs[loanId];
    }

    /**
     * @notice Return a LOAN status associated with a loan id.
     * @param loanId Id of a loan.
     * @return status LOAN status.
     */
    function getLOANStatus(uint256 loanId) public view returns (uint8) {
        LOAN storage loan = LOANs[loanId];
        if (loan.principal == 0) {
            return loan.unclaimedRepayment == 0 ? LOANStatus.DEAD : LOANStatus.REPAID;
        } else {
            return loan.defaultModule.isDefaulted(address(this), loanId) ? LOANStatus.DEFAULTED : LOANStatus.RUNNING;
        }
    }

    /**
     * @notice Calculate the total debt of a loan.
     * @dev The total debt is the sum of the principal amount and accrued interest.
     * @param loanId Id of a loan.
     * @return Total debt.
     */
    function getLOANDebt(uint256 loanId) public view returns (uint256) {
        LOAN storage loan = LOANs[loanId];
        return loan.principal + loan.pastAccruedInterest + loan.interestModule.interest(address(this), loanId);
    }


    /*----------------------------------------------------------*|
    |*  # LENDER & BORROWER SPEC                                *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get the hash of a lender specification.
     * @dev The hash is used to verify the lender specification in the loan terms.
     * @param lenderSpec Lender specification struct.
     * @return Hash of the lender specification.
     */
    function getLenderSpecHash(LenderSpec calldata lenderSpec) public pure returns (bytes32) {
        bytes32 specHash = keccak256(abi.encode(lenderSpec));
        return specHash == _EMPTY_LENDER_SPEC_HASH ? bytes32(0) : specHash;
    }

    /**
     * @notice Get the hash of a borrower specification.
     * @dev The hash is used to verify the borrower specification in the loan terms.
     * @param borrowerSpec Borrower specification struct.
     * @return Hash of the borrower specification.
     */
    function getBorrowerSpecHash(BorrowerSpec calldata borrowerSpec) public pure returns (bytes32) {
        bytes32 specHash = keccak256(abi.encode(borrowerSpec));
        return specHash == _EMPTY_BORROWER_SPEC_HASH ? bytes32(0) : specHash;
    }


    /*----------------------------------------------------------*|
    |*  # HOOKS                                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice Update the lender repayment hook for a loan.
     * @param loanId Id of a loan that is being updated.
     * @param newHook New lender repayment hook.
     * @param newHookData New lender repayment hook data.
     */
    function updateLenderRepaymentHook(
        uint256 loanId,
        IPWNLenderRepaymentHook newHook,
        bytes calldata newHookData
    ) external {
        if (address(newHook) == address(0)) {
            delete lenderRepaymentHook[msg.sender][loanId];
        } else {
            _checkHubTag(address(newHook), PWNHubTags.HOOK);
            lenderRepaymentHook[msg.sender][loanId] = LenderRepaymentHookData(newHook, newHookData);
        }
    }


    /*----------------------------------------------------------*|
    |*  # MultiToken                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Check if the asset is valid with the MultiToken dependency lib and the category registry.
     * @dev See MultiToken.isValid for more details.
     * @param asset Asset to be checked.
     * @return True if the asset is valid.
     */
    function isValidAsset(MultiToken.Asset memory asset) public view returns (bool) {
        return MultiToken.isValid(asset, categoryRegistry);
    }

    /**
     * @notice Check if the asset is valid with the MultiToken lib and the category registry.
     * @dev The function will revert if the asset is not valid.
     * @param asset Asset to be checked.
     */
    function _checkValidAsset(MultiToken.Asset memory asset) private view {
        if (!isValidAsset(asset)) {
            revert InvalidMultiTokenAsset({
                category: uint8(asset.category),
                addr: asset.assetAddress,
                id: asset.id,
                amount: asset.amount
            });
        }
    }


    /*----------------------------------------------------------*|
    |*  # IPWNLoanMetadataProvider                              *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IPWNLoanMetadataProvider*/
    function loanMetadataUri() override external view returns (string memory) {
        return config.loanMetadataUri(address(this));
    }


    /*----------------------------------------------------------*|
    |*  # ERC5646                                               *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IERC5646*/
    function getStateFingerprint(uint256 tokenId) external view virtual override returns (bytes32) {
        LOAN storage loan = LOANs[tokenId];
        uint8 status = getLOANStatus(tokenId);
        if (status == LOANStatus.DEAD)
            return bytes32(0);

        // The only mutable state properties are:
        // - status: updated for repaid or defaulted loans
        // - lastUpdateTimestamp: updated on every loan repayment
        // - pastAccruedInterest: used to store currently unpaid accrued interest on every loan repayment
        // - principal: decreased on every loan repayment
        // - unclaimedRepayment: increased on every loan repayment
        // Others don't have to be part of the state fingerprint as it does not act as a token identification.
        return keccak256(abi.encode(
            status,
            loan.lastUpdateTimestamp,
            loan.pastAccruedInterest,
            loan.principal,
            loan.unclaimedRepayment
        ));
    }


    /*----------------------------------------------------------*|
    |*  # UTILS                                                 *|
    |*----------------------------------------------------------*/

    function _checkHubTag(address addr, bytes32 tag) internal view {
        if (!hub.hasTag(addr, tag)) {
            revert AddressMissingHubTag({ addr: addr, tag: tag });
        }
    }

}
