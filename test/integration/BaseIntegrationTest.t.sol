// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";
import { T1155 } from "test/helper/T1155.sol";
import {
    DeploymentTest,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    PWNDutchAuctionProposal,
    PWNElasticProposal,
    PWNListProposal,
    PWNSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry
} from "test/DeploymentTest.t.sol";


abstract contract BaseIntegrationTest is DeploymentTest {

    T20 t20;
    T721 t721;
    T1155 t1155;
    T20 credit;

    PWNSimpleProposal.Proposal simpleProposal;

    PWNLoan.LenderSpec lenderSpec;
    PWNLoan.BorrowerSpec borrowerSpec;

    function setUp() public override virtual {
        super.setUp();

        // Deploy tokens
        t20 = new T20();
        t721 = new T721();
        t1155 = new T1155();
        credit = new T20();

        // Default offer
        simpleProposal = PWNSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10e18,
            creditAddress: address(credit),
            creditAmount: 100e18,
            interestAPR: 0,
            duration: 1 days,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: uint40(block.timestamp + 7 days),
            proposer: lender,
            proposerSpecHash: bytes32(0),
            isProposerLender: true,
            loanContract: address(__d.loan)
        });
    }


    // Create from proposal

    function _createERC20Loan() internal returns (uint256) {
        // Proposal
        simpleProposal.collateralCategory = MultiToken.Category.ERC20;
        simpleProposal.collateralAddress = address(t20);
        simpleProposal.collateralId = 0;
        simpleProposal.collateralAmount = 10e18;

        // Mint initial state
        t20.mint(borrower, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t20.approve(address(__d.loan), 10e18);

        // Create LOAN
        return _createLoan(true, simpleProposal, "");
    }

    function _createERC721Loan() internal returns (uint256) {
        // Proposal
        simpleProposal.collateralCategory = MultiToken.Category.ERC721;
        simpleProposal.collateralAddress = address(t721);
        simpleProposal.collateralId = 42;
        simpleProposal.collateralAmount = 0;

        // Mint initial state
        t721.mint(borrower, 42);

        // Approve collateral
        vm.prank(borrower);
        t721.approve(address(__d.loan), 42);

        // Create LOAN
        return _createLoan(true, simpleProposal, "");
    }

    function _createERC1155Loan() internal returns (uint256) {
        return _createERC1155LoanFailing(true, "");
    }

    function _createERC1155Loan(bool mint) internal returns (uint256) {
        return _createERC1155LoanFailing(mint, "");
    }

    function _createERC1155LoanFailing(bool mint, bytes memory revertData) internal returns (uint256) {
        // Offer
        simpleProposal.collateralCategory = MultiToken.Category.ERC1155;
        simpleProposal.collateralAddress = address(t1155);
        simpleProposal.collateralId = 42;
        simpleProposal.collateralAmount = 10e18;

        // Mint initial state
        if (mint) t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(__d.loan), true);

        // Create LOAN
        return _createLoan(mint, simpleProposal, revertData);
    }

    function _createLoan(
        bool mint,
        PWNSimpleProposal.Proposal memory _proposal,
        bytes memory revertData
    ) private returns (uint256) {
        // Sign proposal
        bytes memory signature = _sign(lenderPK, __d.simpleProposal.getProposalHash(_proposal));

        if (mint) {
            // Mint initial state
            credit.mint(lender, 100e18);

            // Approve loan asset
            vm.prank(lender);
            credit.approve(address(__d.loan), 100e18);
        }

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = __d.simpleProposal.encodeProposalData(_proposal);

        // Create LOAN
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return __d.loan.create({
            proposalSpec: PWNLoan.ProposalSpec({
                proposalContract: address(__d.simpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    // Repay

    function _repayLoan(uint256 loanId) internal {
        _repayLoanFailing(loanId, "");
    }

    function _repayLoanFailing(uint256 loanId, bytes memory revertData) internal {
        // Approve loan asset
        vm.prank(borrower);
        credit.approve(address(__d.loan), 100e18);

        // Repay loan
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        __d.loan.repay(loanId, 0);
    }

}