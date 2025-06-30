// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";

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
    PWNRevokedNonce
} from "test/integration/BaseIntegrationTest.t.sol";


contract PWNProtocolIntegrityTest is BaseIntegrationTest {

    function test_shouldFailToCreateLOAN_whenLoanContractNotActive() external {
        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.loan), PWNHubTags.ACTIVE_LOAN, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            true, abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(__d.loan), PWNHubTags.ACTIVE_LOAN)
        );
    }

    function test_shouldRepayLOAN_whenLoanContractNotActive() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.loan), PWNHubTags.ACTIVE_LOAN, false);

        // Repay loan
        _repayLoan(loanId);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.loan)), 100e18);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.loan), 42), 0);
    }

    function test_shouldClaimRepaidLOAN_whenLoanContractNotActive() external {
        address lender2 = makeAddr("lender2");

        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Transfer loan to another lender
        vm.prank(lender);
        __d.loanToken.transferFrom(lender, lender2, loanId);

        // Repay loan
        _repayLoan(loanId);

        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.loan), PWNHubTags.ACTIVE_LOAN, false);

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

    function test_shouldFailToCreateLOANTerms_whenCallerIsNotActiveLoan() external {
        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.loan), PWNHubTags.ACTIVE_LOAN, false);

        bytes memory proposalData = __d.simpleProposal.encodeProposalData(simpleProposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNLoan.AddressMissingHubTag.selector, address(__d.loan), PWNHubTags.ACTIVE_LOAN
            )
        );
        vm.prank(address(__d.loan));
        __d.simpleProposal.acceptProposal({
            acceptor: borrower,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: ""
        });
    }

    function test_shouldFailToCreateLOAN_whenPassingInvalidTermsFactoryContract() external {
        // Remove LOAN_PROPOSAL tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.simpleProposal), PWNHubTags.LOAN_PROPOSAL, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            true, abi.encodeWithSelector(
                PWNLoan.AddressMissingHubTag.selector, address(__d.simpleProposal), PWNHubTags.LOAN_PROPOSAL
            )
        );
    }

}
