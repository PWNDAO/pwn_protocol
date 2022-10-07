// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "MultiToken/MultiToken.sol";

import "../../hub/PWNHub.sol";
import "../../hub/PWNHubTags.sol";
import "../../loan-factory/simple-loan/IPWNSimpleLoanFactory.sol";
import "../../PWNConfig.sol";
import "../PWNVault.sol";
import "../PWNLOAN.sol";


contract PWNSimpleLoan is PWNVault {

    string internal constant VERSION = "0.1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNHub immutable internal hub;
    // TODO: Doc
    PWNLOAN immutable internal loanToken;
    // TODO: Doc
    PWNConfig immutable internal config;

    /**
     * Struct defining a LOAN
     * @param status 0 == none/dead || 2 == running/accepted offer || 3 == paid back || 4 == expired
     * @param borrower Address of the borrower - stays the same for entire lifespan of the token
     * @param duration Loan duration in seconds
     * @param expiration Unix timestamp (in seconds) setting up the default deadline
     * @param collateral Asset used as a loan collateral. Consisting of another `Asset` struct defined in the MultiToken library
     * @param asset Asset to be borrowed by lender to borrower. Consisting of another `Asset` struct defined in the MultiToken library
     * @param loanRepayAmount Amount of LOAN asset to be repaid
     */
    struct LOAN {
        uint8 status;
        address borrower;
        uint32 duration;
        uint40 expiration;
        MultiToken.Asset collateral;
        MultiToken.Asset asset;
        uint256 loanRepayAmount;
    }

    /**
     * Mapping of all LOAN data by loan id
     */
    mapping (uint256 => LOAN) public LOANs;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    // TODO: Update for Dune
    event LOANCreated(uint256 indexed loanId, address indexed lender);
    event LOANPaidBack(uint256 loanId);
    event LOANClaimed(uint256 loanId);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _hub, address _loanToken, address _config) {
        hub = PWNHub(_hub);
        loanToken = PWNLOAN(_loanToken);
        config = PWNConfig(_config);
    }


    /*----------------------------------------------------------*|
    |*  # CREATE LOAN                                           *|
    |*----------------------------------------------------------*/

    // TODO: Doc
    function createLOAN(
        address loanFactoryContract,
        bytes calldata loanFactoryData,
        bytes calldata signature,
        bytes calldata loanAssetPermit,
        bytes calldata collateralPermit
    ) external returns (uint256 loanId) {
        // Check that loan factory contract is tagged in PWNHub
        require(hub.hasTag(loanFactoryContract, PWNHubTags.LOAN_FACTORY), "Given contract is not loan factory");

        // Build LOAN by loan factory
        (LOAN memory loan, address lender, address borrower) = IPWNSimpleLoanFactory(loanFactoryContract).createLOAN({
            caller: msg.sender,
            loanFactoryData: loanFactoryData,
            signature: signature
        });

        // Mint LOAN token for lender
        loanId = loanToken.mint(lender);

        // Store loan data under loan id
        LOANs[loanId] = loan;

        emit LOANCreated(loanId, lender);

        // TODO: Work with fee

        // Transfer collateral to Vault
        _pull(loan.collateral, borrower, collateralPermit);
        // Transfer loan asset to borrower
        _pushFrom(loan.asset, lender, borrower, loanAssetPermit);
    }


    /*----------------------------------------------------------*|
    |*  # REPAY LOAN                                            *|
    |*----------------------------------------------------------*/

    // TODO: Doc
    function repayLoan(
        uint256 loanId,
        bytes calldata loanAssetPermit
    ) external {
        LOAN storage loan = LOANs[loanId];

        // Check that loan is not from a different loan contract
        require(loan.status != 0, "Loan does not exist or is not from current loan contract");

        // Check that loan running
        require(loan.status == 2, "Loan is not running");

        // Check that loan is not expired
        require(loan.expiration > block.timestamp, "Loan is expired");

        // Move loan to repaid state
        loan.status = 3;

        // Transfer repaid amount of loan asset to Vault
        MultiToken.Asset memory repayLoanAsset = loan.asset;
        repayLoanAsset.amount = loan.loanRepayAmount;
        _pull(repayLoanAsset, msg.sender, loanAssetPermit);

        // Transfer collateral back to borrower
        _push(loan.collateral, loan.borrower);

        emit LOANPaidBack(loanId);
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM LOAN                                            *|
    |*----------------------------------------------------------*/

    // TODO: Doc
    function claimLoan(uint256 loanId) external {
        LOAN memory loan = LOANs[loanId];

        // Check that caller is LOAN token holder
        require(loanToken.ownerOf(loanId) == msg.sender, "Caller is not a LOAN token holder");

        // Check that loan can be claimed
        require(loan.status == 3 || (loan.status == 2 && loan.expiration <= block.timestamp), "Loan can't be claimed yet or is not from current loan contract");

        // Delete loan data and burn loan token
        delete LOANs[loanId];
        loanToken.burn(loanId);

        if (loan.status == 3) { // Loan has been paid back
            // Transfer repaid loan to lender
            MultiToken.Asset memory repayLoanAsset = loan.asset;
            repayLoanAsset.amount = loan.loanRepayAmount;

            _push(repayLoanAsset, msg.sender);
        } else { // Loan is running but expired
             // Transfer collateral to lender
            _push(loan.collateral, msg.sender);
        }

        emit LOANClaimed(loanId);
    }

}
