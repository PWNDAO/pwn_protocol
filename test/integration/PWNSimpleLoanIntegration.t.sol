// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    MultiToken,
    MultiTokenCategoryRegistry,
    BaseIntegrationTest,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNSimpleLoan,
    PWNSimpleLoanDutchAuctionProposal,
    PWNSimpleLoanElasticProposal,
    PWNSimpleLoanListProposal,
    PWNSimpleLoanSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit
} from "test/integration/BaseIntegrationTest.t.sol";


contract PWNSimpleLoanIntegrationTest is BaseIntegrationTest {

    // Create LOAN

    function test_shouldCreateLOAN_fromSimpleProposal() external {
        PWNSimpleLoanSimpleProposal.Proposal memory proposal = PWNSimpleLoanSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10e18,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(credit),
            creditAmount: 100e18,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            fixedInterestAmount: 10e18,
            accruingInterestAPR: 0,
            durationOrDate: 7 days,
            expiration: uint40(block.timestamp + 1 days),
            allowedAcceptor: borrower,
            proposer: lender,
            proposerSpecHash: __d.simpleLoan.getLenderSpecHash(PWNSimpleLoan.LenderSpec(lender)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(__d.simpleLoan)
        });

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(__d.simpleLoan), true);

        // Sign proposal
        bytes memory signature = _sign(lenderPK, __d.simpleLoanSimpleProposal.getProposalHash(proposal));

        // Mint initial state
        credit.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        credit.approve(address(__d.simpleLoan), 100e18);

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = __d.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create LOAN
        vm.prank(borrower);
        uint256 loanId = __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: PWNSimpleLoan.LenderSpec({
                sourceOfFunds: lender
            }),
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 10e18);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, proposal.nonceSpace, proposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.simpleLoan));
    }

    function test_shouldCreateLOAN_fromListProposal() external {
        bytes32 id1Hash = keccak256(abi.encodePacked(uint256(52)));
        bytes32 id2Hash = keccak256(abi.encodePacked(uint256(42)));
        bytes32 collateralIdsWhitelistMerkleRoot = keccak256(abi.encodePacked(id1Hash, id2Hash));

        PWNSimpleLoanListProposal.Proposal memory proposal = PWNSimpleLoanListProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralIdsWhitelistMerkleRoot: collateralIdsWhitelistMerkleRoot,
            collateralAmount: 10e18,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(credit),
            creditAmount: 100e18,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            fixedInterestAmount: 10e18,
            accruingInterestAPR: 0,
            durationOrDate: 7 days,
            expiration: uint40(block.timestamp + 1 days),
            allowedAcceptor: borrower,
            proposer: lender,
            proposerSpecHash: __d.simpleLoan.getLenderSpecHash(PWNSimpleLoan.LenderSpec(lender)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(__d.simpleLoan)
        });

        PWNSimpleLoanListProposal.ProposalValues memory proposalValues = PWNSimpleLoanListProposal.ProposalValues({
            collateralId: 42,
            merkleInclusionProof: new bytes32[](1)
        });
        proposalValues.merkleInclusionProof[0] = id1Hash;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(__d.simpleLoan), true);

        // Sign proposal
        bytes memory signature = _sign(lenderPK, __d.simpleLoanListProposal.getProposalHash(proposal));

        // Mint initial state
        credit.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        credit.approve(address(__d.simpleLoan), 100e18);

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = __d.simpleLoanListProposal.encodeProposalData(proposal, proposalValues);

        // Create LOAN
        vm.prank(borrower);
        uint256 loanId = __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanListProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: PWNSimpleLoan.LenderSpec({
                sourceOfFunds: lender
            }),
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 10e18);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, proposal.nonceSpace, proposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.simpleLoan));
    }

    function test_shouldCreateLOAN_fromElasticProposal() external {
        PWNSimpleLoanElasticProposal.Proposal memory proposal = PWNSimpleLoanElasticProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(credit),
            creditPerCollateralUnit: 10e18 * __d.simpleLoanElasticProposal.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR(),
            minCreditAmount: 10e18,
            availableCreditLimit: 100e18,
            utilizedCreditId: 0,
            fixedInterestAmount: 10e18,
            accruingInterestAPR: 0,
            durationOrDate: 7 days,
            expiration: uint40(block.timestamp + 1 days),
            allowedAcceptor: borrower,
            proposer: lender,
            proposerSpecHash: __d.simpleLoan.getLenderSpecHash(PWNSimpleLoan.LenderSpec(lender)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(__d.simpleLoan)
        });

        PWNSimpleLoanElasticProposal.ProposalValues memory proposalValues = PWNSimpleLoanElasticProposal.ProposalValues({
            creditAmount: 70e18
        });

        // Mint initial state
        t1155.mint(borrower, 42, 10);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(__d.simpleLoan), true);

        // Sign proposal
        bytes32 proposalHash = __d.simpleLoanElasticProposal.getProposalHash(proposal);
        bytes memory signature = _sign(lenderPK, proposalHash);

        // Mint initial state
        credit.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        credit.approve(address(__d.simpleLoan), 100e18);

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = __d.simpleLoanElasticProposal.encodeProposalData(proposal, proposalValues);

        // Create LOAN
        vm.prank(borrower);
        uint256 loanId = __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanElasticProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: PWNSimpleLoan.LenderSpec({
                sourceOfFunds: lender
            }),
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 30e18);
        assertEq(credit.balanceOf(borrower), 70e18);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 3);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 7);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, proposal.nonceSpace, proposal.nonce), false);
        assertEq(__d.utilizedCredit.utilizedCredit(lender, proposal.utilizedCreditId), 70e18);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.simpleLoan));
    }

    function test_shouldCreateLOAN_fromDutchAuctionProposal() external {
        PWNSimpleLoanDutchAuctionProposal.Proposal memory proposal = PWNSimpleLoanDutchAuctionProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(credit),
            minCreditAmount: 10e18,
            maxCreditAmount: 100e18,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            fixedInterestAmount: 10e18,
            accruingInterestAPR: 0,
            durationOrDate: 7 days,
            auctionStart: uint40(block.timestamp),
            auctionDuration: 30 hours,
            allowedAcceptor: lender,
            proposer: borrower,
            proposerSpecHash: bytes32(0),
            isOffer: false,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(__d.simpleLoan)
        });

        PWNSimpleLoanDutchAuctionProposal.ProposalValues memory proposalValues = PWNSimpleLoanDutchAuctionProposal.ProposalValues({
            intendedCreditAmount: 90e18,
            slippage: 10e18
        });

        // Mint initial state
        t1155.mint(borrower, 42, 10);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(__d.simpleLoan), true);

        // Sign proposal
        bytes32 proposalHash = __d.simpleLoanDutchAuctionProposal.getProposalHash(proposal);
        bytes memory signature = _sign(borrowerPK, proposalHash);

        // Mint initial state
        credit.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        credit.approve(address(__d.simpleLoan), 100e18);

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = __d.simpleLoanDutchAuctionProposal.encodeProposalData(proposal, proposalValues);

        vm.warp(proposal.auctionStart + 4 hours);

        uint256 creditAmount = __d.simpleLoanDutchAuctionProposal.getCreditAmount(proposal, block.timestamp);

        // Create LOAN
        vm.prank(lender);
        uint256 loanId = __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanDutchAuctionProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: PWNSimpleLoan.LenderSpec({
                sourceOfFunds: lender
            }),
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 100e18 - creditAmount);
        assertEq(credit.balanceOf(borrower), creditAmount);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 10);

        assertEq(__d.revokedNonce.isNonceRevoked(borrower, proposal.nonceSpace, proposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.simpleLoan));
    }

    // Different collateral types

    function test_shouldCreateLOAN_withERC20Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC20Loan();

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t20.balanceOf(lender), 0);
        assertEq(t20.balanceOf(borrower), 0);
        assertEq(t20.balanceOf(address(__d.simpleLoan)), 10e18);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, simpleProposal.nonceSpace, simpleProposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.simpleLoan));
    }

    function test_shouldCreateLOAN_withERC721Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC721Loan();

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t721.ownerOf(42), address(__d.simpleLoan));

        assertEq(__d.revokedNonce.isNonceRevoked(lender, simpleProposal.nonceSpace, simpleProposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.simpleLoan));
    }

    function test_shouldCreateLOAN_withERC1155Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 10e18);

        assertEq(__d.revokedNonce.isNonceRevoked(lender, simpleProposal.nonceSpace, simpleProposal.nonce), true);
        assertEq(__d.loanToken.loanContract(loanId), address(__d.simpleLoan));
    }

    function test_shouldCreateLOAN_withCryptoKittiesCollateral() external {
        // TODO:
    }


    // Repay LOAN

    function test_shouldRepayLoan_whenNotExpired_whenOriginalLenderIsLOANOwner() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Repay loan
        _repayLoan(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);

        assertEq(credit.balanceOf(lender), 110e18);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 0);
    }

    function test_shouldFailToRepayLoan_whenLOANExpired() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Default on a loan
        uint256 expiration = block.timestamp + uint256(simpleProposal.durationOrDate);
        vm.warp(expiration);

        // Try to repay loan
        _repayLoanFailing(
            loanId,
            abi.encodeWithSelector(PWNSimpleLoan.LoanDefaulted.selector, uint40(expiration))
        );
    }


    // Claim LOAN

    function test_shouldClaimRepaidLOAN_whenOriginalLenderIsNotLOANOwner() external {
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
        __d.simpleLoan.claimLOAN(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(lender2), 110e18);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(lender2, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 0);
    }

    function test_shouldClaimDefaultedLOAN() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Loan defaulted
        vm.warp(block.timestamp + uint256(simpleProposal.durationOrDate));

        // Claim defaulted loan
        vm.prank(lender);
        __d.simpleLoan.claimLOAN(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(borrower), 100e18);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 10e18);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 0);
    }

}
