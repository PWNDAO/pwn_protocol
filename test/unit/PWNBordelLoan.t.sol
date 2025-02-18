// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNBordelLoan,
    Terms as SimpleTerms,
    PWNHubTags,
    Math,
    MultiToken,
    AddressMissingHubTag
} from "pwn/loan/terms/simple/loan/PWNBordelLoan.sol";

import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";
import { PWNBordelLoanHarness } from "test/harness/PWNBordelLoanHarness.sol";


abstract contract PWNBordelLoanTest is Test {

    bytes32 internal constant LOANS_SLOT = bytes32(uint256(1)); // `LOANs` mapping position

    PWNBordelLoanHarness loan;
    address hub = makeAddr("hub");
    address loanToken = makeAddr("loanToken");
    address config = makeAddr("config");
    address categoryRegistry = makeAddr("categoryRegistry");
    address feeCollector = makeAddr("feeCollector");
    address proposalContract = makeAddr("proposalContract");
    bytes proposalData = bytes("proposalData");
    bytes signature = bytes("signature");
    uint256 loanId = 42;
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");
    uint256 loanDurationInDays = 500;
    PWNBordelLoan.LOAN bordelLoan;
    PWNBordelLoan.LOAN nonExistingLoan;
    SimpleTerms simpleLoanTerms;
    PWNBordelLoan.ProposalSpec proposalSpec;
    T20 fungibleAsset;
    T721 nonFungibleAsset;

    bytes32 proposalHash = keccak256("proposalHash");

    event LOANCreated(uint256 indexed loanId, bytes32 indexed proposalHash, address indexed proposalContract, SimpleTerms terms, bytes extra);
    event LOANRepaymentMade(uint256 indexed loanId, uint256 repaymentAmount, uint256 newPrincipal);
    event LOANPaidBack(uint256 indexed loanId);
    event LOANClaimed(uint256 indexed loanId, uint256 claimedAmount, bool claimedCollateral);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(loanToken, bytes("data"));
        vm.etch(proposalContract, bytes("data"));
        vm.etch(config, bytes("data"));

        loan = new PWNBordelLoanHarness(hub, loanToken, config, categoryRegistry);
        fungibleAsset = new T20();
        nonFungibleAsset = new T721();

        fungibleAsset.mint(lender, 1000e18);
        fungibleAsset.mint(borrower, 1000e18);
        fungibleAsset.mint(address(this), 1000e18);
        fungibleAsset.mint(address(loan), 1000e18);
        nonFungibleAsset.mint(borrower, 2);

        vm.prank(lender);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(borrower);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(address(this));
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(borrower);
        nonFungibleAsset.approve(address(loan), 2);

        bordelLoan = PWNBordelLoan.LOAN({
            creditAddress: address(fungibleAsset),
            lastUpdateTimestamp: uint40(block.timestamp),
            defaultTimestamp: uint40(block.timestamp + loanDurationInDays * 1 days),
            borrower: borrower,
            accruingInterestAPR: 0,
            fixedInterestAmount: 10e18,
            principalAmount: 100e18,
            unclaimedAmount: 0,
            debtLimitTangent: _getInitialDebtLimitTangent(100e18, 10e18, block.timestamp + loanDurationInDays * 1 days),
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2)
        });

        simpleLoanTerms = SimpleTerms({
            lender: lender,
            borrower: borrower,
            duration: uint32(loanDurationInDays * 1 days),
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            credit: MultiToken.ERC20(address(fungibleAsset), 100e18),
            fixedInterestAmount: 10e18,
            accruingInterestAPR: 0,
            lenderSpecHash: bytes32(0),
            borrowerSpecHash: bytes32(0)
        });

        proposalSpec = PWNBordelLoan.ProposalSpec({
            proposalContract: proposalContract,
            proposalData: proposalData,
            signature: signature
        });

        nonExistingLoan = PWNBordelLoan.LOAN({
            creditAddress: address(0),
            lastUpdateTimestamp: 0,
            defaultTimestamp: 0,
            borrower: address(0),
            accruingInterestAPR: 0,
            fixedInterestAmount: 0,
            principalAmount: 0,
            unclaimedAmount: 0,
            debtLimitTangent: 0,
            collateral: MultiToken.Asset(MultiToken.Category(0), address(0), 0, 0)
        });

        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)"),
            abi.encode(type(uint8).max)
        );

        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(0));
        vm.mockCall(config, abi.encodeWithSignature("feeCollector()"), abi.encode(feeCollector));

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", proposalContract, PWNHubTags.LOAN_PROPOSAL),
            abi.encode(true)
        );

        _mockLoanTerms(simpleLoanTerms);
        _mockLOANMint(loanId);
        _mockLOANTokenOwner(loanId, lender);
    }


    function _assertLOANEq(PWNBordelLoan.LOAN memory _simpleLoan1, PWNBordelLoan.LOAN memory _simpleLoan2) internal {
        assertEq(_simpleLoan1.creditAddress, _simpleLoan2.creditAddress);
        assertEq(_simpleLoan1.lastUpdateTimestamp, _simpleLoan2.lastUpdateTimestamp);
        assertEq(_simpleLoan1.defaultTimestamp, _simpleLoan2.defaultTimestamp);
        assertEq(_simpleLoan1.borrower, _simpleLoan2.borrower);
        assertEq(_simpleLoan1.accruingInterestAPR, _simpleLoan2.accruingInterestAPR);
        assertEq(_simpleLoan1.fixedInterestAmount, _simpleLoan2.fixedInterestAmount);
        assertEq(_simpleLoan1.principalAmount, _simpleLoan2.principalAmount);
        assertEq(_simpleLoan1.unclaimedAmount, _simpleLoan2.unclaimedAmount);
        assertEq(_simpleLoan1.debtLimitTangent, _simpleLoan2.debtLimitTangent);
        assertEq(uint8(_simpleLoan1.collateral.category), uint8(_simpleLoan2.collateral.category));
        assertEq(_simpleLoan1.collateral.assetAddress, _simpleLoan2.collateral.assetAddress);
        assertEq(_simpleLoan1.collateral.id, _simpleLoan2.collateral.id);
        assertEq(_simpleLoan1.collateral.amount, _simpleLoan2.collateral.amount);
    }

    function _assertLOANEq(uint256 _loanId, PWNBordelLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        _assertLOANWord(loanSlot + 0, abi.encodePacked(uint16(0), _simpleLoan.defaultTimestamp, _simpleLoan.lastUpdateTimestamp, _simpleLoan.creditAddress));
        _assertLOANWord(loanSlot + 1, abi.encodePacked(uint72(0), _simpleLoan.accruingInterestAPR, _simpleLoan.borrower));
        _assertLOANWord(loanSlot + 2, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        _assertLOANWord(loanSlot + 3, abi.encodePacked(_simpleLoan.principalAmount));
        _assertLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.unclaimedAmount));
        _assertLOANWord(loanSlot + 5, abi.encodePacked(_simpleLoan.debtLimitTangent));
        _assertLOANWord(loanSlot + 6, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        _assertLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.id));
        _assertLOANWord(loanSlot + 8, abi.encodePacked(_simpleLoan.collateral.amount));
    }

    function _assertLOANWord(uint256 wordSlot, bytes memory word) private {
        assertEq(
            abi.encodePacked(vm.load(address(loan), bytes32(wordSlot))),
            word
        );
    }

    function _storeLOAN(uint256 _loanId, PWNBordelLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        _storeLOANWord(loanSlot + 0, abi.encodePacked(uint16(0), _simpleLoan.defaultTimestamp, _simpleLoan.lastUpdateTimestamp, _simpleLoan.creditAddress));
        _storeLOANWord(loanSlot + 1, abi.encodePacked(uint72(0), _simpleLoan.accruingInterestAPR, _simpleLoan.borrower));
        _storeLOANWord(loanSlot + 2, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        _storeLOANWord(loanSlot + 3, abi.encodePacked(_simpleLoan.principalAmount));
        _storeLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.unclaimedAmount));
        _storeLOANWord(loanSlot + 5, abi.encodePacked(_simpleLoan.debtLimitTangent));
        _storeLOANWord(loanSlot + 6, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        _storeLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.id));
        _storeLOANWord(loanSlot + 8, abi.encodePacked(_simpleLoan.collateral.amount));
    }

    function _storeLOANWord(uint256 wordSlot, bytes memory word) private {
        vm.store(address(loan), bytes32(wordSlot), _bytesToBytes32(word));
    }

    function _bytesToBytes32(bytes memory _bytes) private pure returns (bytes32 _bytes32) {
        assembly {
            _bytes32 := mload(add(_bytes, 32))
        }
    }

    function _mockLoanTerms(SimpleTerms memory _terms) internal {
        vm.mockCall(
            proposalContract,
            abi.encodeWithSignature("acceptProposal(address,uint256,bytes,bytes32[],bytes)"),
            abi.encode(proposalHash, _terms)
        );
    }

    function _mockLOANMint(uint256 _loanId) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("mint(address)"), abi.encode(_loanId));
    }

    function _mockLOANTokenOwner(uint256 _loanId, address _owner) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", _loanId), abi.encode(_owner));
    }

    function _getInitialDebtLimitTangent(uint256 principal, uint256 fixedInterest, uint256 defaultTimestamp) internal view returns (uint256) {
        return Math.mulDiv(
            principal + fixedInterest, 10 ** loan.DEBT_LIMIT_TANGENT_DECIMALS(),
            defaultTimestamp - block.timestamp - loan.DEBT_LIMIT_POSTPONEMENT()
        );
    }

}


/*----------------------------------------------------------*|
|*  # CREATE LOAN                                           *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_CreateLOAN_Test is PWNBordelLoanTest {

    function testFuzz_shouldFail_whenProposalContractNotTagged_LOAN_PROPOSAL(address _proposalContract) external {
        vm.assume(_proposalContract != proposalContract);

        proposalSpec.proposalContract = _proposalContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, _proposalContract, PWNHubTags.LOAN_PROPOSAL));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function testFuzz_shouldCallProposalContract(
        address caller, bytes memory _proposalData, bytes memory _signature
    ) external {
        proposalSpec.proposalData = _proposalData;
        proposalSpec.signature = _signature;

        vm.expectCall(
            proposalContract,
            abi.encodeWithSignature(
                "acceptProposal(address,uint256,bytes,bytes32[],bytes)", caller, 0, _proposalData, new bytes32[](0), _signature
            )
        );

        vm.prank(caller);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenLoanTermsDurationLessThanMin(uint256 duration) external {
        uint256 minDuration = loan.MIN_LOAN_DURATION();
        duration = bound(duration, 0, minDuration - 1);
        simpleLoanTerms.duration = uint32(duration);
        _mockLoanTerms(simpleLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(PWNBordelLoan.InvalidDuration.selector, duration, minDuration));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenLoanTermsInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = loan.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint24).max);
        simpleLoanTerms.accruingInterestAPR = uint24(interestAPR);
        _mockLoanTerms(simpleLoanTerms);

        vm.expectRevert(
            abi.encodeWithSelector(PWNBordelLoan.InterestAPROutOfBounds.selector, interestAPR, maxInterest)
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenInvalidCreditAsset() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", simpleLoanTerms.credit.assetAddress),
            abi.encode(1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNBordelLoan.InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.credit.category),
                simpleLoanTerms.credit.assetAddress,
                simpleLoanTerms.credit.id,
                simpleLoanTerms.credit.amount
            )
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenInvalidCollateralAsset() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", simpleLoanTerms.collateral.assetAddress),
            abi.encode(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNBordelLoan.InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.collateral.category),
                simpleLoanTerms.collateral.assetAddress,
                simpleLoanTerms.collateral.id,
                simpleLoanTerms.collateral.amount
            )
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function test_shouldMintLOANToken() external {
        vm.expectCall(address(loanToken), abi.encodeWithSignature("mint(address)", lender));

        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function test_shouldStoreLoanData() external {
        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });

        _assertLOANEq(loanId, bordelLoan);
    }

    function test_shouldEmit_LOANCreated() external {
        vm.expectEmit();
        emit LOANCreated(loanId, proposalHash, proposalContract, simpleLoanTerms, "lil extra");

        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: "lil extra"
        });
    }

    function test_shouldTransferCollateral_fromBorrower_toVault() external {
        simpleLoanTerms.collateral.category = MultiToken.Category.ERC20;
        simpleLoanTerms.collateral.assetAddress = address(fungibleAsset);
        simpleLoanTerms.collateral.id = 0;
        simpleLoanTerms.collateral.amount = 100;
        _mockLoanTerms(simpleLoanTerms);

        vm.expectCall(
            simpleLoanTerms.collateral.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loan), simpleLoanTerms.collateral.amount
            )
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferCredit_toBorrowerAndFeeCollector(
        uint256 fee, uint256 loanAmount
    ) external {
        fee = bound(fee, 0, 9999);
        loanAmount = bound(loanAmount, 1, 1e40);

        simpleLoanTerms.credit.amount = loanAmount;
        fungibleAsset.mint(lender, loanAmount);

        _mockLoanTerms(simpleLoanTerms);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        uint256 feeAmount = Math.mulDiv(loanAmount, fee, 1e4);
        uint256 newAmount = loanAmount - feeAmount;

        // Fee transfer
        vm.expectCall({
            callee: simpleLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, feeCollector, feeAmount),
            count: feeAmount > 0 ? 1 : 0
        });
        // Updated amount transfer
        vm.expectCall(
            simpleLoanTerms.credit.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, borrower, newAmount)
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });
    }

    function testFuzz_shouldReturnNewLoanId(uint256 _loanId) external {
        _mockLOANMint(_loanId);

        uint256 createdLoanId = loan.createLOAN({
            proposalSpec: proposalSpec,
            extra: ""
        });

        assertEq(createdLoanId, _loanId);
    }

}


/*----------------------------------------------------------*|
|*  # DEBT LIMIT TANGENT                                    *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_DebtLimitTangent_Test is PWNBordelLoanTest {

    function testFuzz_shouldComputeDebtLimitTangent(uint256 principal, uint256 fixedInterest, uint256 duration) external {
        principal = bound(principal, 1e6, 1e40);
        fixedInterest = bound(fixedInterest, 0, principal);
        duration = bound(duration, loan.MIN_LOAN_DURATION(), 3650 days);

        uint256 postponement = loan.DEBT_LIMIT_POSTPONEMENT();
        uint256 decimals = loan.DEBT_LIMIT_TANGENT_DECIMALS();

        assertEq(
            loan.exposed_debtLimitTangent(principal, fixedInterest, duration),
            (principal + fixedInterest) * 10 ** decimals / (duration - postponement)
        );
    }

}


/*----------------------------------------------------------*|
|*  # REPAY LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_RepayLOAN_Test is PWNBordelLoanTest {

    address notOriginalLender = makeAddr("notOriginalLender");

    function setUp() override public {
        super.setUp();

        bordelLoan.fixedInterestAmount = 0;
        _storeLOAN(loanId, bordelLoan);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }


    function test_shouldFail_whenLoanDoesNotExist() external {
        vm.expectRevert(abi.encodeWithSelector(PWNBordelLoan.NonExistingLoan.selector));
        loan.repayLOAN(loanId + 1, 0);
    }

    function test_shouldFail_whenLoanRepaid() external {
        bordelLoan.principalAmount = 0;
        bordelLoan.unclaimedAmount = 1;
        _storeLOAN(loanId, bordelLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNBordelLoan.LoanRepaid.selector));
        loan.repayLOAN(loanId, 0);
    }

    function test_shouldFail_whenLoanIsDefaulted() external {
        vm.warp(bordelLoan.defaultTimestamp);

        vm.expectRevert(abi.encodeWithSelector(PWNBordelLoan.LoanDefaulted.selector, bordelLoan.defaultTimestamp));
        loan.repayLOAN(loanId, 0);
    }

    function testFuzz_shouldFail_whenInvalidRepaymentAmount(uint256 repayment) external {
        repayment = bound(repayment, bordelLoan.principalAmount + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNBordelLoan.InvalidRepaymentAmount.selector,
                repayment, loan.loanRepaymentAmount(loanId)
            )
        );
        loan.repayLOAN(loanId, repayment);
    }

    function testFuzz_shouldUpdateLoanData_whenPartialInterestPayment(uint256 repayment) external {
        bordelLoan.fixedInterestAmount = 1e18;
        _storeLOAN(loanId, bordelLoan);

        repayment = bound(repayment, 1, bordelLoan.fixedInterestAmount - 1);

        loan.repayLOAN(loanId, repayment);

        (, PWNBordelLoan.LOAN memory loan) = loan.getLOAN(loanId);
        assertEq(uint256(loan.fixedInterestAmount), bordelLoan.fixedInterestAmount - repayment);
        assertEq(uint256(loan.principalAmount), bordelLoan.principalAmount);
    }

    function testFuzz_shouldUpdateLoanData_whenFullInterestPayment(uint256 repayment) external {
        bordelLoan.fixedInterestAmount = 1e18;
        _storeLOAN(loanId, bordelLoan);

        repayment = bound(repayment, bordelLoan.fixedInterestAmount, bordelLoan.principalAmount);

        loan.repayLOAN(loanId, repayment);

        (, PWNBordelLoan.LOAN memory loan) = loan.getLOAN(loanId);
        assertEq(uint256(loan.fixedInterestAmount), 0);
        assertEq(uint256(loan.principalAmount), bordelLoan.principalAmount + bordelLoan.fixedInterestAmount - repayment);
    }

    function testFuzz_shouldUpdate_unclaimedAmount(uint256 repayment, uint256 unclaimedAmount) external {
        repayment = bound(repayment, 1, bordelLoan.principalAmount);
        unclaimedAmount = bound(unclaimedAmount, 0, 1e40);

        bordelLoan.unclaimedAmount = unclaimedAmount;
        _storeLOAN(loanId, bordelLoan);

        loan.repayLOAN(loanId, repayment);

        (, PWNBordelLoan.LOAN memory loan) = loan.getLOAN(loanId);
        assertEq(uint256(loan.unclaimedAmount), unclaimedAmount + repayment);
    }

    function testFuzz_shouldUpdate_lastUpdateTimestamp(uint256 timestmap) external {
        uint256 postponement = loan.DEBT_LIMIT_POSTPONEMENT();
        timestmap = bound(timestmap, bordelLoan.lastUpdateTimestamp + 1, bordelLoan.lastUpdateTimestamp + postponement - 1);

        vm.warp(timestmap);
        loan.repayLOAN(loanId, 0);

        (, PWNBordelLoan.LOAN memory loan) = loan.getLOAN(loanId);
        assertEq(uint256(loan.lastUpdateTimestamp), timestmap);
    }

    function testFuzz_shouldEmit_LOANRepaymentMade(uint256 repayment) external {
        repayment = bound(repayment, 1, bordelLoan.principalAmount);

        vm.expectEmit();
        emit LOANRepaymentMade(loanId, repayment, bordelLoan.principalAmount - repayment); // Note: not testing correct interest repayment

        loan.repayLOAN(loanId, repayment);
    }

    function testFuzz_shouldTransferRepaymentToVault(uint256 repayment) external {
        repayment = bound(repayment, 1, bordelLoan.principalAmount);

        vm.expectCall(
            bordelLoan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loan), repayment
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, repayment);
    }

    function testFuzz_shouldKeepLoanInRunningState_whenPartialRepayment(uint256 repayment) external {
        repayment = bound(repayment, 1, bordelLoan.principalAmount - 1);

        loan.repayLOAN(loanId, repayment);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 2);
    }

    function test_shouldMoveLoanToRepaidState_whenFullRepayment() external {
        loan.repayLOAN(loanId, 0);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 3);
    }

    function test_shouldTransferCollateralToBorrower_whenFullRepayment() external {
        vm.expectCall(
            bordelLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), bordelLoan.borrower, bordelLoan.collateral.id
            )
        );

        loan.repayLOAN(loanId, 0);
    }

    function test_shouldEmit_LOANPaidBack_whenFullRepayment() external {
        vm.expectEmit();
        emit LOANPaidBack(loanId);

        loan.repayLOAN(loanId, 0);
    }

}


/*----------------------------------------------------------*|
|*  # LOAN REPAYMENT AMOUNT                                 *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_LoanRepaymentAmount_Test is PWNBordelLoanTest {

    function test_shouldReturnZero_whenLoanDoesNotExist() external {
        assertEq(loan.loanRepaymentAmount(loanId), 0);
    }

    function testFuzz_shouldReturnFixedInterest_whenZeroAccruedInterest(
        uint256 _days, uint256 _principal, uint256 _fixedInterest
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays); // should return non zero value even after loan expiration
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);

        bordelLoan.defaultTimestamp = bordelLoan.lastUpdateTimestamp + 101 * 1 days;
        bordelLoan.principalAmount = _principal;
        bordelLoan.fixedInterestAmount = _fixedInterest;
        bordelLoan.accruingInterestAPR = 0;
        _storeLOAN(loanId, bordelLoan);

        vm.warp(bordelLoan.lastUpdateTimestamp + _days + 1 days); // should not have an effect

        assertEq(loan.loanRepaymentAmount(loanId), _principal + _fixedInterest);
    }

    function testFuzz_shouldReturnAccruedInterest_whenNonZeroAccruedInterest(
        uint256 _minutes, uint256 _principal, uint256 _fixedInterest, uint256 _interestAPR
    ) external {
        _minutes = bound(_minutes, 0, 2 * loanDurationInDays * 24 * 60); // should return non zero value even after loan expiration
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _interestAPR = bound(_interestAPR, 1, 16e6);

        bordelLoan.defaultTimestamp = bordelLoan.lastUpdateTimestamp + 101 * 1 days;
        bordelLoan.principalAmount = _principal;
        bordelLoan.fixedInterestAmount = _fixedInterest;
        bordelLoan.accruingInterestAPR = uint24(_interestAPR);
        _storeLOAN(loanId, bordelLoan);

        vm.warp(bordelLoan.lastUpdateTimestamp + _minutes * 1 minutes + 1);

        uint256 expectedInterest = _fixedInterest + _principal * _interestAPR * _minutes / (1e2 * 60 * 24 * 365) / 100;
        uint256 expectedLoanRepaymentAmount = _principal + expectedInterest;
        assertEq(loan.loanRepaymentAmount(loanId), expectedLoanRepaymentAmount);
    }

    function test_shouldReturnAccuredInterest() external {
        bordelLoan.defaultTimestamp = bordelLoan.lastUpdateTimestamp + 101 * 1 days;
        bordelLoan.principalAmount = 100e18;
        bordelLoan.fixedInterestAmount = 10e18;
        bordelLoan.accruingInterestAPR = uint24(365e2);
        _storeLOAN(loanId, bordelLoan);

        vm.warp(bordelLoan.lastUpdateTimestamp);
        assertEq(loan.loanRepaymentAmount(loanId), bordelLoan.principalAmount + bordelLoan.fixedInterestAmount);

        vm.warp(bordelLoan.lastUpdateTimestamp + 1 days);
        assertEq(loan.loanRepaymentAmount(loanId), bordelLoan.principalAmount + bordelLoan.fixedInterestAmount + 1e18);

        bordelLoan.accruingInterestAPR = uint24(100e2);
        _storeLOAN(loanId, bordelLoan);

        vm.warp(bordelLoan.lastUpdateTimestamp + 365 days);
        assertEq(loan.loanRepaymentAmount(loanId), 2 * bordelLoan.principalAmount + bordelLoan.fixedInterestAmount);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_ClaimLOAN_Test is PWNBordelLoanTest {

    function setUp() override public {
        super.setUp();

        bordelLoan.unclaimedAmount = bordelLoan.principalAmount;
        bordelLoan.principalAmount = 0;
        _storeLOAN(loanId, bordelLoan);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }


    function testFuzz_shouldFail_whenCallerIsNotLOANTokenHolder(address caller) external {
        vm.assume(caller != lender);

        vm.expectRevert(abi.encodeWithSelector(PWNBordelLoan.CallerNotLOANTokenHolder.selector));
        vm.prank(caller);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        bordelLoan.principalAmount = 0;
        bordelLoan.unclaimedAmount = 0;
        _storeLOAN(loanId, bordelLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNBordelLoan.NonExistingLoan.selector));
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenNothingToClaim() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 0;
        _storeLOAN(loanId, bordelLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNBordelLoan.NothingToClaim.selector));
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmit_LOANClaimed_whenRunning() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 2); // Note: sanity check

        vm.expectEmit();
        emit LOANClaimed(loanId, bordelLoan.unclaimedAmount, false);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmit_LOANClaimed_whenRepaid() external {
        bordelLoan.principalAmount = 0;
        bordelLoan.unclaimedAmount = 10e18;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 3); // Note: sanity check

        vm.expectEmit();
        emit LOANClaimed(loanId, bordelLoan.unclaimedAmount, false);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmit_LOANClaimed_whenDefaulted() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        bordelLoan.defaultTimestamp = 1;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 4); // Note: sanity check

        vm.expectEmit();
        emit LOANClaimed(loanId, bordelLoan.unclaimedAmount, true);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldUpdateUnclaimedAmount_whenRunning() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 2); // Note: sanity check

        vm.prank(lender);
        loan.claimLOAN(loanId);

        bordelLoan.unclaimedAmount = 0;
        _assertLOANEq(loanId, bordelLoan);
    }

    function test_shouldDeleteLoanData_whenFullyRepaid() external {
        bordelLoan.principalAmount = 0;
        bordelLoan.unclaimedAmount = 10e18;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 3); // Note: sanity check

        vm.prank(lender);
        loan.claimLOAN(loanId);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldDeleteLoanData_whenDefaulted() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        bordelLoan.defaultTimestamp = 1;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 4); // Note: sanity check

        vm.prank(lender);
        loan.claimLOAN(loanId);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken_whenFullyRepaid() external {
        bordelLoan.principalAmount = 0;
        bordelLoan.unclaimedAmount = 10e18;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 3); // Note: sanity check

        vm.expectCall(
            loanToken,
            abi.encodeWithSignature("burn(uint256)", loanId)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldBurnLOANToken_whenDefaulted() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        bordelLoan.defaultTimestamp = 1;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 4); // Note: sanity check

        vm.expectCall(
            loanToken,
            abi.encodeWithSignature("burn(uint256)", loanId)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferUnclaimedAmount_whenRunning() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        _storeLOAN(loanId, bordelLoan);

        fungibleAsset.mint(address(loan), bordelLoan.unclaimedAmount);

        vm.expectCall(
            bordelLoan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, bordelLoan.unclaimedAmount)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferUnclaimedAmount_whenRepaid() external {
        bordelLoan.principalAmount = 0;
        bordelLoan.unclaimedAmount = 10e18;
        _storeLOAN(loanId, bordelLoan);

        fungibleAsset.mint(address(loan), bordelLoan.unclaimedAmount);

        vm.expectCall(
            bordelLoan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, bordelLoan.unclaimedAmount)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferUnclaimedAmount_whenDefaulted() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        bordelLoan.defaultTimestamp = 1;
        _storeLOAN(loanId, bordelLoan);

        fungibleAsset.mint(address(loan), bordelLoan.unclaimedAmount);

        vm.expectCall(
            bordelLoan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, bordelLoan.unclaimedAmount)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferCollateral_whenDefaulted() external {
        bordelLoan.principalAmount = 1;
        bordelLoan.unclaimedAmount = 10e18;
        bordelLoan.defaultTimestamp = 1;
        _storeLOAN(loanId, bordelLoan);

        vm.expectCall(
            bordelLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), lender, bordelLoan.collateral.id, ""
            )
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN                                              *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_GetLOAN_Test is PWNBordelLoanTest {

    function test_shouldReturnStoredLOANData_FirstPart() external {
        _storeLOAN(loanId, bordelLoan);

        (, PWNBordelLoan.LOAN memory loan) = loan.getLOAN(loanId);

        _assertLOANEq(loanId, loan);
    }

    function test_shouldReturnCorrectStatus() external {
        _storeLOAN(loanId, bordelLoan);

        (uint8 status,) = loan.getLOAN(loanId);
        assertEq(status, 2);

        vm.warp(bordelLoan.defaultTimestamp);

        (status,) = loan.getLOAN(loanId);
        assertEq(status, 4);

        bordelLoan.principalAmount = 0;
        bordelLoan.unclaimedAmount = 1;
        _storeLOAN(loanId, bordelLoan);

        (status,) = loan.getLOAN(loanId);
        assertEq(status, 3);
    }

    function test_shouldReturnEmptyLOANDataForNonExistingLoan() external {
        uint256 nonExistingLoanId = loanId + 1;

        (uint8 status, PWNBordelLoan.LOAN memory loan) = loan.getLOAN(nonExistingLoanId);

        assertEq(status, 0);
        _assertLOANEq(nonExistingLoan, loan);
    }

}


/*----------------------------------------------------------*|
|*  # DEFAULT CONDITIONS                                    *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_DefaultConditions_Test is PWNBordelLoanTest {

    function testFuzz_shouldDefault_whenPassedDefaultTimestamp(uint256 timestamp) external {
        bordelLoan.defaultTimestamp = 500;
        _storeLOAN(loanId, bordelLoan);
        timestamp = bound(timestamp, bordelLoan.defaultTimestamp, 1e9);

        vm.warp(timestamp);

        (uint8 status, ) = loan.getLOAN(loanId);
        assertEq(status, 4);
    }

    function test_shouldDefault_whenDebtAboveLimit() external {
        vm.warp(1);

        bordelLoan.lastUpdateTimestamp = 1;
        bordelLoan.defaultTimestamp = 1 + 360 days;
        bordelLoan.principalAmount = 800e18;
        bordelLoan.fixedInterestAmount = 200e18;
        bordelLoan.accruingInterestAPR = 0;
        bordelLoan.debtLimitTangent = _getInitialDebtLimitTangent(bordelLoan.principalAmount, bordelLoan.fixedInterestAmount, bordelLoan.defaultTimestamp);
        _storeLOAN(loanId, bordelLoan);

        vm.warp(block.timestamp + loan.DEBT_LIMIT_POSTPONEMENT() - 1);

        (uint8 status, ) = loan.getLOAN(loanId);
        assertEq(status, 2);

        vm.warp(block.timestamp + 1);

        (status, ) = loan.getLOAN(loanId);
        assertEq(status, 4);

        vm.warp(block.timestamp + 120 days - 1); // 50% of the debt limit value

        bordelLoan.principalAmount = 400e18;
        bordelLoan.fixedInterestAmount = 100e18;
        _storeLOAN(loanId, bordelLoan);

        (status, ) = loan.getLOAN(loanId);
        assertEq(status, 2);

        vm.warp(block.timestamp + 1);

        (status, ) = loan.getLOAN(loanId);
        assertEq(status, 4);

        vm.warp(block.timestamp + 60 days);

        bordelLoan.principalAmount = 200e18;
        bordelLoan.fixedInterestAmount = 40e18;
        _storeLOAN(loanId, bordelLoan);

        (status, ) = loan.getLOAN(loanId);
        assertEq(status, 2);

        bordelLoan.principalAmount = 200e18;
        bordelLoan.fixedInterestAmount = 51e18;
        _storeLOAN(loanId, bordelLoan);

        (status, ) = loan.getLOAN(loanId);
        assertEq(status, 4);
    }

    function testFuzz_shouldDefault_whenDebtAboveLimit(uint256 debt, uint256 duration) external {
        vm.warp(1);

        bordelLoan.lastUpdateTimestamp = 1;
        bordelLoan.defaultTimestamp = 1 + 360 days;
        bordelLoan.principalAmount = 100e18;
        bordelLoan.fixedInterestAmount = 0;
        bordelLoan.accruingInterestAPR = 0;
        bordelLoan.debtLimitTangent = _getInitialDebtLimitTangent(bordelLoan.principalAmount, bordelLoan.fixedInterestAmount, bordelLoan.defaultTimestamp);
        _storeLOAN(loanId, bordelLoan);

        duration = bound(duration, 0, 240 days);
        uint256 limit = bordelLoan.principalAmount * (240 days - duration) / 240 days;
        debt = bound(debt, limit, type(uint256).max);

        vm.warp(block.timestamp + loan.DEBT_LIMIT_POSTPONEMENT() + duration);

        bordelLoan.principalAmount = debt;
        _storeLOAN(loanId, bordelLoan);

        (uint8 status, ) = loan.getLOAN(loanId);
        assertEq(status, 4);
    }

}


/*----------------------------------------------------------*|
|*  # LOAN METADATA URI                                     *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_LoanMetadataUri_Test is PWNBordelLoanTest {

    string tokenUri;

    function setUp() override public {
        super.setUp();

        tokenUri = "test.uri.xyz";

        vm.mockCall(
            config,
            abi.encodeWithSignature("loanMetadataUri(address)"),
            abi.encode(tokenUri)
        );
    }


    function test_shouldCallConfig() external {
        vm.expectCall(
            config,
            abi.encodeWithSignature("loanMetadataUri(address)", loan)
        );

        loan.loanMetadataUri();
    }

    function test_shouldReturnCorrectValue() external {
        string memory _tokenUri = loan.loanMetadataUri();

        assertEq(tokenUri, _tokenUri);
    }

}


/*----------------------------------------------------------*|
|*  # ERC5646                                               *|
|*----------------------------------------------------------*/

contract PWNBordelLoan_GetStateFingerprint_Test is PWNBordelLoanTest {

    function test_shouldReturnZeroIfLoanDoesNotExist() external {
        bytes32 fingerprint = loan.getStateFingerprint(loanId);

        assertEq(fingerprint, bytes32(0));
    }

    function test_shouldUpdateStateFingerprint_whenLoanDefaulted() external {
        _storeLOAN(loanId, bordelLoan);

        vm.warp(bordelLoan.lastUpdateTimestamp);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(2, bordelLoan.lastUpdateTimestamp, bordelLoan.fixedInterestAmount, bordelLoan.principalAmount, bordelLoan.unclaimedAmount))
        );

        vm.warp(bordelLoan.defaultTimestamp);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(4, bordelLoan.lastUpdateTimestamp, bordelLoan.fixedInterestAmount, bordelLoan.principalAmount, bordelLoan.unclaimedAmount))
        );
    }

    function test_shouldReturnCorrectStateFingerprint() external {
        bordelLoan.debtLimitTangent = type(uint256).max;

        bordelLoan.lastUpdateTimestamp = 1;
        bordelLoan.principalAmount = 1e22;
        bordelLoan.fixedInterestAmount = 1e6;
        bordelLoan.unclaimedAmount = 1e30;
        _storeLOAN(loanId, bordelLoan);

        vm.warp(1);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(2, bordelLoan.lastUpdateTimestamp, bordelLoan.fixedInterestAmount, bordelLoan.principalAmount, bordelLoan.unclaimedAmount))
        );
    }

}
