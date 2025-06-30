// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNDirectLenderRepaymentHook,
    IPWNLenderRepaymentHook
} from "pwn/periphery/loan/hook/lender/PWNDirectLenderRepaymentHook.sol";
import {
    PWNRefinanceBorrowerCreateHook,
    IPWNBorrowerCreateHook
} from "pwn/periphery/loan/hook/borrower/PWNRefinanceBorrowerCreateHook.sol";

import {
    MultiToken,
    MultiTokenCategoryRegistry,
    BaseIntegrationTest,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    PWNSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit
} from "test/integration/BaseIntegrationTest.t.sol";


contract PWNLoanIntegrationTest is BaseIntegrationTest {

    // Create Loan

    function test_shouldCreateLoan_fromSimpleProposal() external {
        PWNSimpleProposal.Proposal memory proposal = PWNSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10e18,
            creditAddress: address(credit),
            creditAmount: 100e18,
            interestAPR: 0,
            duration: 7 days,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: uint40(block.timestamp + 1 days),
            proposer: lender,
            proposerSpecHash: bytes32(0),
            isProposerLender: true,
            loanContract: address(__d.loan)
        });

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(__d.loan), true);

        // Sign proposal
        bytes memory signature = _sign(lenderPK, __d.simpleProposal.getProposalHash(proposal));

        // Mint initial state
        credit.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        credit.approve(address(__d.loan), 100e18);

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = __d.simpleProposal.encodeProposalData(proposal);

        // Create LOAN
        vm.prank(borrower);
        uint256 loanId = __d.loan.create({
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

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 10e18);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, proposal.nonceSpace, proposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.loan));
    }

    // Different collateral types

    function test_shouldCreateLoan_withERC20Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC20Loan();

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t20.balanceOf(lender), 0);
        assertEq(t20.balanceOf(borrower), 0);
        assertEq(t20.balanceOf(address(__d.loan)), 10e18);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, simpleProposal.nonceSpace, simpleProposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.loan));
    }

    function test_shouldCreateLOAN_withERC721Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC721Loan();

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t721.ownerOf(42), address(__d.loan));

        assertEq(__d.revokedNonce.isNonceRevoked(lender, simpleProposal.nonceSpace, simpleProposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.loan));
    }

    function test_shouldCreateLOAN_withERC1155Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 10e18);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, simpleProposal.nonceSpace, simpleProposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.loan));
    }

    function test_shouldCreateLOAN_withCryptoKittiesCollateral() external {
        // TODO:
    }


    // Repay LOAN

    function test_shouldRepayLoan_whenNotExpired() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Repay loan
        _repayLoan(loanId);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.loan)), 100e18);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 0);
    }

    function test_shouldFailToRepayLoan_whenLOANExpired() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Default on a loan
        uint256 expiration = block.timestamp + uint256(simpleProposal.duration);
        vm.warp(expiration);

        // Try to repay loan
        _repayLoanFailing(loanId, abi.encodeWithSelector(PWNLoan.LoanNotRunning.selector));
    }


    // Claim

    function test_shouldClaimRepaidLoan() external {
        address lender2 = makeAddr("lender2");

        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Transfer loan to another lender
        vm.prank(lender);
        __d.loanToken.transferFrom(lender, lender2, loanId);

        // Repay loan
        _repayLoan(loanId);

        // Claim loan
        vm.prank(lender2);
        __d.loan.claimRepayment(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(lender2), 100e18);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(lender2, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 0);
    }

    function test_shouldClaimDefaultedLOAN() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Loan defaulted
        vm.warp(block.timestamp + uint256(simpleProposal.duration));

        // Claim defaulted loan
        vm.prank(lender);
        __d.loan.liquidate(loanId, ""); // todo:

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 10e18);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 0);
    }

    // Hooks

    function test_shouldRepayDirectlyToLender() external {
        PWNDirectLenderRepaymentHook lenderRepaymentHook = new PWNDirectLenderRepaymentHook();

        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(lenderRepaymentHook), PWNHubTags.HOOK, true);

        lenderSpec.repaymentHook = IPWNLenderRepaymentHook(lenderRepaymentHook);

        simpleProposal.proposerSpecHash = __d.loan.getLenderSpecHash(lenderSpec);

        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Repay loan
        _repayLoan(loanId);

        // Assert final state
        assertEq(credit.balanceOf(lender), 100e18);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 0);
    }

    function test_shouldRefinanceLoan() external {
        PWNRefinanceBorrowerCreateHook borrowerCreateHook = new PWNRefinanceBorrowerCreateHook(__d.hub);

        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(borrowerCreateHook), PWNHubTags.HOOK, true);

        // Create LOAN
        simpleProposal.creditAmount = 20e18;
        uint256 loanId = _createERC1155Loan();

        borrowerSpec.createHook = IPWNBorrowerCreateHook(borrowerCreateHook);
        borrowerSpec.createHookData = abi.encode(
            PWNRefinanceBorrowerCreateHook.HookData({
                refinanceLoanId: loanId
            })
        );

        assertEq(credit.balanceOf(lender), 80e18);
        assertEq(credit.balanceOf(borrower), 20e18);
        assertEq(credit.balanceOf(address(__d.loan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 10e18);

        // Refinance loan
        vm.prank(borrower);
        credit.approve(address(borrowerCreateHook), 50e18);

        simpleProposal.creditAmount = 80e18;
        simpleProposal.nonce = 1;
        uint256 refinancedLoanId = _createERC1155Loan({ mint: false });

        // Assert final state
        assertEq(__d.loanToken.ownerOf(refinancedLoanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 80e18);
        assertEq(credit.balanceOf(address(__d.loan)), 20e18);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 10e18);

        assertEq(__d.loan.getLOANStatus(loanId), 3);
        assertEq(__d.loan.getLOANStatus(refinancedLoanId), 2);
    }

}
