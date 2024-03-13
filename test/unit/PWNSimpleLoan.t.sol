// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import "@pwn/PWNErrors.sol";

import { T20 } from "@pwn-test/helper/token/T20.sol";
import { T721 } from "@pwn-test/helper/token/T721.sol";


abstract contract PWNSimpleLoanTest is Test {

    bytes32 internal constant LOANS_SLOT = bytes32(uint256(0)); // `LOANs` mapping position
    bytes32 internal constant EXTENSION_OFFERS_MADE_SLOT = bytes32(uint256(1)); // `extensionOffersMade` mapping position

    PWNSimpleLoan loan;
    address hub = makeAddr("hub");
    address loanToken = makeAddr("loanToken");
    address config = makeAddr("config");
    address revokedNonce = makeAddr("revokedNonce");
    address categoryRegistry = makeAddr("categoryRegistry");
    address feeCollector = makeAddr("feeCollector");
    address alice = makeAddr("alice");
    address proposalContract = makeAddr("proposalContract");
    uint256 loanId = 42;
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");
    uint256 loanDurationInDays = 101;
    PWNSimpleLoan.LOAN simpleLoan;
    PWNSimpleLoan.LOAN nonExistingLoan;
    PWNSimpleLoan.Terms simpleLoanTerms;
    PWNSimpleLoan.Extension extension;
    T20 fungibleAsset;
    T721 nonFungibleAsset;

    bytes creditPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));
    bytes collateralPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));
    bytes32 proposalHash = keccak256("proposalHash");

    event LOANCreated(uint256 indexed loanId, PWNSimpleLoan.Terms terms, bytes32 indexed factoryDataHash, address indexed factoryAddress);
    event LOANPaidBack(uint256 indexed loanId);
    event LOANClaimed(uint256 indexed loanId, bool indexed defaulted);
    event LOANRefinanced(uint256 indexed loanId, uint256 indexed refinancedLoanId);
    event LOANExtended(uint256 indexed loanId, uint40 originalDefaultTimestamp, uint40 extendedDefaultTimestamp);
    event ExtensionOfferMade(bytes32 indexed extensionHash, address indexed proposer, PWNSimpleLoan.Extension extension);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(loanToken, bytes("data"));
        vm.etch(proposalContract, bytes("data"));
        vm.etch(config, bytes("data"));

        loan = new PWNSimpleLoan(hub, loanToken, config, revokedNonce, categoryRegistry);
        fungibleAsset = new T20();
        nonFungibleAsset = new T721();

        fungibleAsset.mint(lender, 6831);
        fungibleAsset.mint(borrower, 6831);
        fungibleAsset.mint(address(this), 6831);
        fungibleAsset.mint(address(loan), 6831);
        nonFungibleAsset.mint(borrower, 2);

        vm.prank(lender);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(borrower);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(address(this));
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(borrower);
        nonFungibleAsset.approve(address(loan), 2);

        simpleLoan = PWNSimpleLoan.LOAN({
            status: 2,
            creditAddress: address(fungibleAsset),
            startTimestamp: uint40(block.timestamp),
            defaultTimestamp: uint40(block.timestamp + loanDurationInDays * 1 days),
            borrower: borrower,
            originalLender: lender,
            accruingInterestDailyRate: 0,
            fixedInterestAmount: 6631,
            principalAmount: 100,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2)
        });

        simpleLoanTerms = PWNSimpleLoan.Terms({
            lender: lender,
            borrower: borrower,
            duration: uint32(loanDurationInDays * 1 days),
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            credit: MultiToken.ERC20(address(fungibleAsset), 100),
            fixedInterestAmount: 6631,
            accruingInterestAPR: 0
        });

        nonExistingLoan = PWNSimpleLoan.LOAN({
            status: 0,
            creditAddress: address(0),
            startTimestamp: 0,
            defaultTimestamp: 0,
            borrower: address(0),
            originalLender: address(0),
            accruingInterestDailyRate: 0,
            fixedInterestAmount: 0,
            principalAmount: 0,
            collateral: MultiToken.Asset(MultiToken.Category(0), address(0), 0, 0)
        });

        extension = PWNSimpleLoan.Extension({
            loanId: loanId,
            price: 100,
            duration: 2 days,
            expiration: simpleLoan.defaultTimestamp,
            proposer: borrower,
            nonceSpace: 1,
            nonce: 1
        });

        vm.mockCall(
            address(fungibleAsset),
            abi.encodeWithSignature("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"),
            abi.encode()
        );

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

        _mockLOANMint(loanId);
        _mockLOANTokenOwner(loanId, lender);

        vm.mockCall(
            revokedNonce, abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"), abi.encode(true)
        );
    }


    function _assertLOANEq(PWNSimpleLoan.LOAN memory _simpleLoan1, PWNSimpleLoan.LOAN memory _simpleLoan2) internal {
        assertEq(_simpleLoan1.status, _simpleLoan2.status);
        assertEq(_simpleLoan1.creditAddress, _simpleLoan2.creditAddress);
        assertEq(_simpleLoan1.startTimestamp, _simpleLoan2.startTimestamp);
        assertEq(_simpleLoan1.defaultTimestamp, _simpleLoan2.defaultTimestamp);
        assertEq(_simpleLoan1.borrower, _simpleLoan2.borrower);
        assertEq(_simpleLoan1.originalLender, _simpleLoan2.originalLender);
        assertEq(_simpleLoan1.accruingInterestDailyRate, _simpleLoan2.accruingInterestDailyRate);
        assertEq(_simpleLoan1.fixedInterestAmount, _simpleLoan2.fixedInterestAmount);
        assertEq(_simpleLoan1.principalAmount, _simpleLoan2.principalAmount);
        assertEq(uint8(_simpleLoan1.collateral.category), uint8(_simpleLoan2.collateral.category));
        assertEq(_simpleLoan1.collateral.assetAddress, _simpleLoan2.collateral.assetAddress);
        assertEq(_simpleLoan1.collateral.id, _simpleLoan2.collateral.id);
        assertEq(_simpleLoan1.collateral.amount, _simpleLoan2.collateral.amount);
    }

    function _assertLOANEq(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        // Status, credit address, start timestamp, default timestamp
        _assertLOANWord(loanSlot + 0, abi.encodePacked(uint8(0), _simpleLoan.defaultTimestamp, _simpleLoan.startTimestamp, _simpleLoan.creditAddress, _simpleLoan.status));
        // Borrower address
        _assertLOANWord(loanSlot + 1, abi.encodePacked(uint96(0), _simpleLoan.borrower));
        // Original lender, accruing interest daily rate
        _assertLOANWord(loanSlot + 2, abi.encodePacked(uint56(0), _simpleLoan.accruingInterestDailyRate, _simpleLoan.originalLender));
        // Fixed interest amount
        _assertLOANWord(loanSlot + 3, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        // Principal amount
        _assertLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.principalAmount));
        // Collateral category, collateral asset address
        _assertLOANWord(loanSlot + 5, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _assertLOANWord(loanSlot + 6, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _assertLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.amount));
    }


    function _mockLOAN(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        // Status, credit address, start timestamp, default timestamp
        _storeLOANWord(loanSlot + 0, abi.encodePacked(uint8(0), _simpleLoan.defaultTimestamp, _simpleLoan.startTimestamp, _simpleLoan.creditAddress, _simpleLoan.status));
        // Borrower address
        _storeLOANWord(loanSlot + 1, abi.encodePacked(uint96(0), _simpleLoan.borrower));
        // Original lender, accruing interest daily rate
        _storeLOANWord(loanSlot + 2, abi.encodePacked(uint56(0), _simpleLoan.accruingInterestDailyRate, _simpleLoan.originalLender));
        // Fixed interest amount
        _storeLOANWord(loanSlot + 3, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        // Principal amount
        _storeLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.principalAmount));
        // Collateral category, collateral asset address
        _storeLOANWord(loanSlot + 5, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _storeLOANWord(loanSlot + 6, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _storeLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.amount));
    }

    function _mockLOANMint(uint256 _loanId) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("mint(address)"), abi.encode(_loanId));
    }

    function _mockLOANTokenOwner(uint256 _loanId, address _owner) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", _loanId), abi.encode(_owner));
    }

    function _mockExtensionOfferMade(PWNSimpleLoan.Extension memory _extension) internal {
        bytes32 extensionOfferSlot = keccak256(abi.encode(_extensionHash(_extension), EXTENSION_OFFERS_MADE_SLOT));
        vm.store(address(loan), extensionOfferSlot, bytes32(uint256(1)));
    }


    function _assertLOANWord(uint256 wordSlot, bytes memory word) private {
        assertEq(
            abi.encodePacked(vm.load(address(loan), bytes32(wordSlot))),
            word
        );
    }

    function _storeLOANWord(uint256 wordSlot, bytes memory word) private {
        vm.store(address(loan), bytes32(wordSlot), _bytesToBytes32(word));
    }

    function _bytesToBytes32(bytes memory _bytes) private pure returns (bytes32 _bytes32) {
        assembly {
            _bytes32 := mload(add(_bytes, 32))
        }
    }

    function _extensionHash(PWNSimpleLoan.Extension memory _extension) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoan"),
                keccak256("1.2"),
                block.chainid,
                address(loan)
            )),
            keccak256(abi.encodePacked(
                keccak256("Extension(uint256 loanId,uint256 price,uint40 duration,uint40 expiration,address proposer,uint256 nonceSpace,uint256 nonce)"),
                abi.encode(_extension)
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # CREATE LOAN                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_CreateLOAN_Test is PWNSimpleLoanTest {

    function testFuzz_shouldFail_whenCallerNotTagged_LOAN_PROPOSAL(address caller) external {
        vm.assume(caller != proposalContract);

        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.LOAN_PROPOSAL));
        vm.prank(caller);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: ""
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
                InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.credit.category),
                simpleLoanTerms.credit.assetAddress,
                simpleLoanTerms.credit.id,
                simpleLoanTerms.credit.amount
            )
        );
        vm.prank(proposalContract);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: ""
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
                InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.collateral.category),
                simpleLoanTerms.collateral.assetAddress,
                simpleLoanTerms.collateral.id,
                simpleLoanTerms.collateral.amount
            )
        );
        vm.prank(proposalContract);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: ""
        });
    }

    function test_shouldMintLOANToken() external {
        vm.expectCall(address(loanToken), abi.encodeWithSignature("mint(address)", lender));

        vm.prank(proposalContract);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: ""
        });
    }

    function testFuzz_shouldStoreLoanData(uint40 accruingInterestAPR) external {
        accruingInterestAPR = uint40(bound(accruingInterestAPR, 0, 1e11));
        simpleLoanTerms.accruingInterestAPR = accruingInterestAPR;

        vm.prank(proposalContract);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: ""
        });

        simpleLoan.accruingInterestDailyRate = uint40(uint256(accruingInterestAPR) * 274 / 1e5);
        _assertLOANEq(loanId, simpleLoan);
    }

    function test_shouldTransferCollateral_fromBorrower_toVault() external {
        simpleLoanTerms.collateral.category = MultiToken.Category.ERC20;
        simpleLoanTerms.collateral.assetAddress = address(fungibleAsset);
        simpleLoanTerms.collateral.id = 0;
        simpleLoanTerms.collateral.amount = 100;

        vm.expectCall(
            simpleLoanTerms.collateral.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), simpleLoanTerms.collateral.amount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        vm.expectCall(
            simpleLoanTerms.collateral.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, address(loan), simpleLoanTerms.collateral.amount)
        );

        vm.prank(proposalContract);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: collateralPermit
        });
    }

    function testFuzz_shouldTransferCredit_fromLender_toBorrowerAndFeeCollector(
        uint256 fee, uint256 loanAmount
    ) external {
        fee = bound(fee, 0, 9999);
        loanAmount = bound(loanAmount, 1, 1e40);

        simpleLoanTerms.credit.amount = loanAmount;
        fungibleAsset.mint(lender, loanAmount);

        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        uint256 feeAmount = Math.mulDiv(loanAmount, fee, 1e4);
        uint256 newAmount = loanAmount - feeAmount;

        vm.expectCall(
            simpleLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                lender, address(loan), loanAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
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

        vm.prank(proposalContract);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: creditPermit,
            collateralPermit: ""
        });
    }

    function test_shouldEmitEvent_LOANCreated() external {
        vm.expectEmit();
        emit LOANCreated(loanId, simpleLoanTerms, proposalHash, proposalContract);

        vm.prank(proposalContract);
        loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: ""
        });
    }

    function test_shouldReturnCreatedLoanId() external {
        vm.prank(proposalContract);
        uint256 createdLoanId = loan.createLOAN({
            proposalHash: proposalHash,
            loanTerms: simpleLoanTerms,
            creditPermit: "",
            collateralPermit: ""
        });

        assertEq(createdLoanId, loanId);
    }

}


/*----------------------------------------------------------*|
|*  # REFINANCE LOAN                                        *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_RefinanceLOAN_Test is PWNSimpleLoanTest {

    PWNSimpleLoan.LOAN refinancedLoan;
    PWNSimpleLoan.Terms refinancedLoanTerms;
    uint256 ferinancedLoanId = 44;
    address newLender = makeAddr("newLender");

    function setUp() override public {
        super.setUp();

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);

        refinancedLoan = PWNSimpleLoan.LOAN({
            status: 2,
            creditAddress: address(fungibleAsset),
            startTimestamp: uint40(block.timestamp),
            defaultTimestamp: uint40(block.timestamp + 40039),
            borrower: borrower,
            originalLender: lender,
            accruingInterestDailyRate: 0,
            fixedInterestAmount: 6631,
            principalAmount: 100,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2)
        });

        refinancedLoanTerms = PWNSimpleLoan.Terms({
            lender: lender,
            borrower: borrower,
            duration: 40039,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            credit: MultiToken.ERC20(address(fungibleAsset), 100),
            fixedInterestAmount: 6631,
            accruingInterestAPR: 0
        });

        _mockLOAN(loanId, simpleLoan);
        _mockLOANMint(ferinancedLoanId);

        vm.prank(newLender);
        fungibleAsset.approve(address(loan), type(uint256).max);
    }


    function testFuzz_shouldFail_whenCallerNotTagged_LOAN_PROPOSAL(address caller) external {
        vm.assume(caller != proposalContract);

        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.LOAN_PROPOSAL));
        vm.prank(caller);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 3));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldFail_whenLoanIsDefaulted() external {
        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectRevert(abi.encodeWithSelector(LoanDefaulted.selector, simpleLoan.defaultTimestamp));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldFail_whenCreditAssetMismatch(address _assetAddress) external {
        vm.assume(_assetAddress != simpleLoan.creditAddress);
        refinancedLoanTerms.credit.assetAddress = _assetAddress;

        vm.expectRevert(abi.encodeWithSelector(RefinanceCreditMismatch.selector));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldFail_whenCreditAssetAmountZero() external {
        refinancedLoanTerms.credit.amount = 0;

        vm.expectRevert(abi.encodeWithSelector(RefinanceCreditMismatch.selector));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralCategoryMismatch(uint8 _category) external {
        _category = _category % 4;
        vm.assume(_category != uint8(simpleLoan.collateral.category));
        refinancedLoanTerms.collateral.category = MultiToken.Category(_category);

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralAddressMismatch(address _assetAddress) external {
        vm.assume(_assetAddress != simpleLoan.collateral.assetAddress);
        refinancedLoanTerms.collateral.assetAddress = _assetAddress;

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralIdMismatch(uint256 _id) external {
        vm.assume(_id != simpleLoan.collateral.id);
        refinancedLoanTerms.collateral.id = _id;

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralAmountMismatch(uint256 _amount) external {
        vm.assume(_amount != simpleLoan.collateral.amount);
        refinancedLoanTerms.collateral.amount = _amount;

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldFail_whenBorrowerMismatch(address _borrower) external {
        vm.assume(_borrower != simpleLoan.borrower);
        refinancedLoanTerms.borrower = _borrower;

        vm.expectRevert(abi.encodeWithSelector(RefinanceBorrowerMismatch.selector, simpleLoan.borrower, _borrower));
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldMintLOANToken() external {
        vm.expectCall(address(loanToken), abi.encodeWithSignature("mint(address)"));

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldStoreRefinancedLoanData() external {
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        _assertLOANEq(ferinancedLoanId, refinancedLoan);
    }

    function test_shouldEmit_LOANCreated() external {
        vm.expectEmit();
        emit LOANCreated(ferinancedLoanId, refinancedLoanTerms, proposalHash, proposalContract);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldReturnNewLoanId() external {
        vm.prank(proposalContract);
        uint256 newLoanId = loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        assertEq(newLoanId, ferinancedLoanId);
    }

    function test_shouldEmit_LOANPaidBack() external {
        vm.expectEmit();
        emit LOANPaidBack(loanId);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldEmit_LOANRefinanced() external {
        vm.expectEmit();
        emit LOANRefinanced(loanId, ferinancedLoanId);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function test_shouldDeleteOldLoanData_whenLOANOwnerIsOriginalLender() external {
        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldEmit_LOANClaimed_whenLOANOwnerIsOriginalLender() external {
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldUpdateLoanData_whenLOANOwnerIsNotOriginalLender(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 dailyInterest
    ) external {
        _mockLOANTokenOwner(loanId, makeAddr("notOriginalLender"));

        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        dailyInterest = bound(dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        // Update loan and compare
        simpleLoan.status = 3; // move loan to repaid state
        simpleLoan.fixedInterestAmount = loanRepaymentAmount - principal; // stored accrued interest at the time of repayment
        simpleLoan.accruingInterestDailyRate = 0; // stop accruing interest
        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentDirectly_andTransferSurplusToBorrower_whenLOANOwnerIsOriginalLender_whenRefinanceLoanMoreThanOrEqualToOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(
            refinanceAmount,
            minRefinanceAmount,
            type(uint256).max - minRefinanceAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerSurplus = refinanceAmount - feeAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, simpleLoan.originalLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall( // lender permit
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                newLender, address(loan), refinanceAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        // no borrower permit
        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, simpleLoan.originalLender, loanRepaymentAmount
            )
        );
        vm.expectCall({ // borrower surplus
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, borrower, borrowerSurplus
            ),
            count: borrowerSurplus > 0 ? 1 : 0
        });

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: creditPermit,
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentToVault_andTransferSurplusToBorrower_whenLOANOwnerIsNotOriginalLender_whenRefinanceLoanMoreThanOrEqualToOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(
            refinanceAmount,
            minRefinanceAmount,
            type(uint256).max - minRefinanceAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerSurplus = refinanceAmount - feeAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, makeAddr("notOriginalLender"));
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall( // lender permit
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                newLender, address(loan), refinanceAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        // no borrower permit
        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, address(loan), loanRepaymentAmount
            )
        );
        vm.expectCall({ // borrower surplus
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, borrower, borrowerSurplus
            ),
            count: borrowerSurplus > 0 ? 1 : 0
        });

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: creditPermit,
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldNotTransferOriginalLoanRepayment_andTransferSurplusToBorrower_whenLOANOwnerIsNewLender_whenRefinanceLoanMoreThanOrEqualOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(
            refinanceAmount,
            minRefinanceAmount,
            type(uint256).max - minRefinanceAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerSurplus = refinanceAmount - feeAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, newLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // lender permit
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                newLender, address(loan), borrowerSurplus + feeAmount, 1, uint8(4), uint256(2), uint256(3)
            ),
            count: borrowerSurplus + feeAmount > 0 ? 1 : 0
        });
        // no borrower permit
        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall({ // lender repayment
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, newLender, loanRepaymentAmount
            ),
            count: 0
        });
        vm.expectCall({ // borrower surplus
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, borrower, borrowerSurplus
            ),
            count: borrowerSurplus > 0 ? 1 : 0
        });

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: creditPermit,
            borrowerCreditPermit: ""
        });
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentDirectly_andContributeFromBorrower_whenLOANOwnerIsOriginalLender_whenRefinanceLoanLessThanOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(refinanceAmount, 1, minRefinanceAmount - 1);
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerContribution = loanRepaymentAmount - (refinanceAmount - feeAmount);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, simpleLoan.originalLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall( // lender permit
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                newLender, address(loan), refinanceAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        vm.expectCall({ // borrower permit
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), borrowerContribution, 1, uint8(4), uint256(2), uint256(3)
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });
        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, simpleLoan.originalLender, refinanceAmount - feeAmount
            )
        );
        vm.expectCall({ // borrower contribution
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                borrower, simpleLoan.originalLender, borrowerContribution
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: creditPermit,
            borrowerCreditPermit: creditPermit
        });
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentToVault_andContributeFromBorrower_whenLOANOwnerIsNotOriginalLender_whenRefinanceLoanLessThanOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(refinanceAmount, 1, minRefinanceAmount - 1);
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerContribution = loanRepaymentAmount - (refinanceAmount - feeAmount);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, makeAddr("notOriginalLender"));
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall( // lender permit
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                newLender, address(loan), refinanceAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        vm.expectCall({ // borrower permit
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), borrowerContribution, 1, uint8(4), uint256(2), uint256(3)
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });
        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, address(loan), refinanceAmount - feeAmount
            )
        );
        vm.expectCall({ // borrower contribution
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                borrower, address(loan), borrowerContribution
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: creditPermit,
            borrowerCreditPermit: creditPermit
        });
    }

    function testFuzz_shouldNotTransferOriginalLoanRepayment_andContributeFromBorrower_whenLOANOwnerIsNewLender_whenRefinanceLoanLessThanOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(refinanceAmount, 1, minRefinanceAmount - 1);
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerContribution = loanRepaymentAmount - (refinanceAmount - feeAmount);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, newLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // lender permit
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                newLender, address(loan), feeAmount, 1, uint8(4), uint256(2), uint256(3)
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall({ // borrower permit
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), borrowerContribution, 1, uint8(4), uint256(2), uint256(3)
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });
        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall({ // lender repayment
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, newLender, refinanceAmount - feeAmount
            ),
            count: 0
        });
        vm.expectCall({ // borrower contribution
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                borrower, newLender, borrowerContribution
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: creditPermit,
            borrowerCreditPermit: creditPermit
        });
    }

    function testFuzz_shouldRepayOriginalLoan(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 dailyInterest, uint256 refinanceAmount
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        dailyInterest = bound(dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        refinanceAmount = bound(
            refinanceAmount, 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        if (loanRepaymentAmount > refinanceAmount) {
            fungibleAsset.mint(borrower, loanRepaymentAmount - refinanceAmount);
        }

        uint256 originalBalance = fungibleAsset.balanceOf(lender);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        assertEq(fungibleAsset.balanceOf(lender), originalBalance + loanRepaymentAmount);
    }

    function testFuzz_shouldCollectProtocolFee(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 dailyInterest, uint256 refinanceAmount, uint256 fee
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        dailyInterest = bound(dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fee = bound(fee, 1, 9999); // 0 - 99.99%
        refinanceAmount = bound(
            refinanceAmount, 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, lender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);
        if (loanRepaymentAmount > refinanceAmount - feeAmount) {
            fungibleAsset.mint(borrower, loanRepaymentAmount - (refinanceAmount - feeAmount));
        }

        uint256 originalBalance = fungibleAsset.balanceOf(feeCollector);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        assertEq(fungibleAsset.balanceOf(feeCollector), originalBalance + feeAmount);
    }

    function testFuzz_shouldTransferSurplusToBorrower(uint256 refinanceAmount) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        refinanceAmount = bound(
            refinanceAmount, loanRepaymentAmount + 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );
        uint256 surplus = refinanceAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        uint256 originalBalance = fungibleAsset.balanceOf(borrower);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        assertEq(fungibleAsset.balanceOf(borrower), originalBalance + surplus);
    }

    function testFuzz_shouldContributeFromBorrower(uint256 refinanceAmount) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        refinanceAmount = bound(refinanceAmount, 1, loanRepaymentAmount - 1);
        uint256 contribution = loanRepaymentAmount - refinanceAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLOANTokenOwner(loanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        uint256 originalBalance = fungibleAsset.balanceOf(borrower);

        vm.prank(proposalContract);
        loan.refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: refinancedLoanTerms,
            lenderCreditPermit: "",
            borrowerCreditPermit: ""
        });

        assertEq(fungibleAsset.balanceOf(borrower), originalBalance - contribution);
    }

}


/*----------------------------------------------------------*|
|*  # REPAY LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_RepayLOAN_Test is PWNSimpleLoanTest {

    address notOriginalLender = makeAddr("notOriginalLender");

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, simpleLoan);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }


    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        loan.repayLOAN(loanId, creditPermit);
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 3));
        loan.repayLOAN(loanId, creditPermit);
    }

    function test_shouldFail_whenLoanIsDefaulted() external {
        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectRevert(abi.encodeWithSelector(LoanDefaulted.selector, simpleLoan.defaultTimestamp));
        loan.repayLOAN(loanId, creditPermit);
    }

    function testFuzz_shouldCallPermit_whenProvided(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), loanRepaymentAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, creditPermit);
    }

    function test_shouldDeleteLoanData_whenLOANOwnerIsOriginalLender() external {
        loan.repayLOAN(loanId, creditPermit);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken_whenLOANOwnerIsOriginalLender() external {
        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        loan.repayLOAN(loanId, creditPermit);
    }

    function testFuzz_shouldTransferRepaidAmountToLender_whenLOANOwnerIsOriginalLender(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, lender, loanRepaymentAmount
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, creditPermit);
    }

    function testFuzz_shouldUpdateLoanData_whenLOANOwnerIsNotOriginalLender(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _mockLOANTokenOwner(loanId, notOriginalLender);

        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.prank(borrower);
        loan.repayLOAN(loanId, creditPermit);

        // Update loan and compare
        simpleLoan.status = 3; // move loan to repaid state
        simpleLoan.fixedInterestAmount = loanRepaymentAmount - _principal; // stored accrued interest at the time of repayment
        simpleLoan.accruingInterestDailyRate = 0; // stop accruing interest
        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldTransferRepaidAmountToVault_whenLOANOwnerIsNotOriginalLender(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _mockLOANTokenOwner(loanId, notOriginalLender);

        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loan), loanRepaymentAmount
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, creditPermit);
    }

    function test_shouldTransferCollateralToBorrower() external {
        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), simpleLoan.borrower, simpleLoan.collateral.id
            )
        );

        loan.repayLOAN(loanId, creditPermit);
    }

    function test_shouldEmitEvent_LOANPaidBack() external {
        vm.expectEmit();
        emit LOANPaidBack(loanId);

        loan.repayLOAN(loanId, creditPermit);
    }

    function test_shouldEmitEvent_LOANClaimed_whenLOANOwnerIsOriginalLender() external {
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        loan.repayLOAN(loanId, creditPermit);
    }

}


/*----------------------------------------------------------*|
|*  # LOAN REPAYMENT AMOUNT                                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_LoanRepaymentAmount_Test is PWNSimpleLoanTest {

    function test_shouldReturnZero_whenLoanDoesNotExist() external {
        assertEq(loan.loanRepaymentAmount(loanId), 0);
    }

    function testFuzz_shouldReturnFixedInterest_whenZeroAccruedInterest(
        uint256 _days, uint256 _principal, uint256 _fixedInterest
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays); // should return non zero value even after loan expiration
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);

        simpleLoan.defaultTimestamp = simpleLoan.startTimestamp + 101 * 1 days;
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days + 1 days); // should not have an effect

        assertEq(loan.loanRepaymentAmount(loanId), _principal + _fixedInterest);
    }

    function test_shouldReturnAccruedInterest_whenNonZeroAccruedInterest(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays); // should return non zero value even after loan expiration
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.defaultTimestamp = simpleLoan.startTimestamp + 101 * 1 days;
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days + 1);

        uint256 expectedInterest = _fixedInterest + _principal * _dailyInterest * _days / 1e10;
        uint256 expectedLoanRepaymentAmount = _principal + expectedInterest;
        assertEq(loan.loanRepaymentAmount(loanId), expectedLoanRepaymentAmount);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_ClaimLOAN_Test is PWNSimpleLoanTest {

    function setUp() override public {
        super.setUp();

        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }


    function testFuzz_shouldFail_whenCallerIsNotLOANTokenHolder(address caller) external {
        vm.assume(caller != lender);

        vm.expectRevert(abi.encodeWithSelector(CallerNotLOANTokenHolder.selector));
        vm.prank(caller);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanIsNotRepaidNorExpired() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 2));
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldPass_whenLoanIsRepaid() external {
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldPass_whenLoanIsDefaulted() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldDeleteLoanData() external {
        vm.prank(lender);
        loan.claimLOAN(loanId);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken() external {
        vm.expectCall(
            loanToken,
            abi.encodeWithSignature("burn(uint256)", loanId)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function testFuzz_shouldTransferRepaidAmountToLender_whenLoanIsRepaid(
        uint256 _principal, uint256 _fixedInterest
    ) external {
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);

        // Note: loan repayment into Vault will reuse `fixedInterestAmount` and store total interest
        // at the time of repayment and set `accruingInterestDailyRate` to zero.
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = 0;
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);

        fungibleAsset.mint(address(loan), loanRepaymentAmount);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, loanRepaymentAmount)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferCollateralToLender_whenLoanIsDefaulted() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), lender, simpleLoan.collateral.id, ""
            )
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmitEvent_LOANClaimed_whenRepaid() external {
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmitEvent_LOANClaimed_whenDefaulted() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectEmit();
        emit LOANClaimed(loanId, true);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

}


/*----------------------------------------------------------*|
|*  # MAKE EXTENSION OFFER                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_MakeExtensionOffer_Test is PWNSimpleLoanTest {

    function testFuzz_shouldFail_whenCallerNotProposer(address caller) external {
        vm.assume(caller != extension.proposer);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionSigner.selector, extension.proposer, caller));
        vm.prank(caller);
        loan.makeExtensionOffer(extension);
    }

    function test_shouldStoreMadeFlag() external {
        vm.prank(extension.proposer);
        loan.makeExtensionOffer(extension);

        bytes32 extensionOfferSlot = keccak256(abi.encode(_extensionHash(extension), EXTENSION_OFFERS_MADE_SLOT));
        bytes32 isMadeValue = vm.load(address(loan), extensionOfferSlot);
        assertEq(uint256(isMadeValue), 1);
    }

    function test_shouldEmit_ExtensionOfferMade() external {
        bytes32 extensionHash = _extensionHash(extension);

        vm.expectEmit();
        emit ExtensionOfferMade(extensionHash, extension.proposer, extension);

        vm.prank(extension.proposer);
        loan.makeExtensionOffer(extension);
    }

}


/*----------------------------------------------------------*|
|*  # EXTEND LOAN                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_ExtendLOAN_Test is PWNSimpleLoanTest {

    uint256 lenderPk;
    uint256 borrowerPk;

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, simpleLoan);

        (, lenderPk) = makeAddrAndKey("lender");
        (, borrowerPk) = makeAddrAndKey("borrower");

        // borrower as proposer, lender accepting extension
        extension.proposer = borrower;
    }


    // Helpers

    function _signExtension(uint256 pk, PWNSimpleLoan.Extension memory _extension) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _extensionHash(_extension));
        return abi.encodePacked(r, s, v);
    }

    // Tests

    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function test_shouldFail_whenLoanIsRepaid() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 3));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenInvalidSignature_whenEOA(uint256 pk) external {
        pk = boundPrivateKey(pk);
        vm.assume(pk != borrowerPk);

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, extension.proposer, _extensionHash(extension)));
        vm.prank(lender);
        loan.extendLOAN(extension, _signExtension(pk, extension), "");
    }

    function testFuzz_shouldFail_whenOfferExpirated(uint40 expiration) external {
        uint256 timestamp = 300;
        vm.warp(timestamp);

        extension.expiration = uint40(bound(expiration, 0, timestamp));
        _mockExtensionOfferMade(extension);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, block.timestamp, extension.expiration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function test_shouldFail_whenOfferNonceNotUsable() external {
        _mockExtensionOfferMade(extension);

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", extension.proposer, extension.nonceSpace, extension.nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, extension.proposer, extension.nonceSpace, extension.nonce
        ));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenCallerIsNotBorrowerNorLoanOwner(address caller) external {
        vm.assume(caller != borrower && caller != lender);
        _mockExtensionOfferMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionCaller.selector));
        vm.prank(caller);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenCallerIsBorrower_andProposerIsNotLoanOwner(address proposer) external {
        vm.assume(proposer != lender);

        extension.proposer = proposer;
        _mockExtensionOfferMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionSigner.selector, lender, proposer));
        vm.prank(borrower);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenCallerIsLoanOwner_andProposerIsNotBorrower(address proposer) external {
        vm.assume(proposer != borrower);

        extension.proposer = proposer;
        _mockExtensionOfferMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionSigner.selector, borrower, proposer));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenExtensionDurationLessThanMin(uint40 duration) external {
        uint256 minDuration = loan.MIN_EXTENSION_DURATION();
        duration = uint40(bound(duration, 0, minDuration - 1));

        extension.duration = duration;
        _mockExtensionOfferMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionDuration.selector, duration, minDuration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenExtensionDurationMoreThanMax(uint40 duration) external {
        uint256 maxDuration = loan.MAX_EXTENSION_DURATION();
        duration = uint40(bound(duration, maxDuration + 1, type(uint40).max));

        extension.duration = duration;
        _mockExtensionOfferMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionDuration.selector, duration, maxDuration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldRevokeExtensionNonce(uint256 nonceSpace, uint256 nonce) external {
        extension.nonceSpace = nonceSpace;
        extension.nonce = nonce;
        _mockExtensionOfferMade(extension);

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", extension.proposer, nonceSpace, nonce)
        );

        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldUpdateLoanData(uint40 duration) external {
        duration = uint40(bound(duration, loan.MIN_EXTENSION_DURATION(), loan.MAX_EXTENSION_DURATION()));

        extension.duration = duration;
        _mockExtensionOfferMade(extension);

        vm.prank(lender);
        loan.extendLOAN(extension, "", "");

        simpleLoan.defaultTimestamp = simpleLoan.defaultTimestamp + duration;
        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldEmit_LOANExtended(uint40 duration) external {
        duration = uint40(bound(duration, loan.MIN_EXTENSION_DURATION(), loan.MAX_EXTENSION_DURATION()));

        extension.duration = duration;
        _mockExtensionOfferMade(extension);

        vm.expectEmit();
        emit LOANExtended(loanId, simpleLoan.defaultTimestamp, simpleLoan.defaultTimestamp + duration);

        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldTransferCredit_whenPriceMoreThanZero(uint256 price) external {
        price = bound(price, 1, 1e40);

        extension.price = price;
        _mockExtensionOfferMade(extension);
        fungibleAsset.mint(borrower, price);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, lender, price)
        );

        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function test_shouldNotTransferCredit_whenPriceZero() external {
        extension.price = 0;
        _mockExtensionOfferMade(extension);

        vm.expectCall({
            callee: simpleLoan.creditAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, lender, 0),
            count: 0
        });

        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldCallPermit_whenPriceMoreThanZero_whenPermitData(uint256 price) external {
        price = bound(price, 1, 1e40);

        extension.price = price;
        _mockExtensionOfferMade(extension);
        fungibleAsset.mint(borrower, price);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), price, 1, uint8(4), uint256(2), uint256(3)
            )
        );

        vm.prank(lender);
        loan.extendLOAN(extension, "", creditPermit);
    }

    function test_shouldPass_whenBorrowerSignature_whenLenderAccepts() external {
        extension.proposer = borrower;

        vm.prank(lender);
        loan.extendLOAN(extension, _signExtension(borrowerPk, extension), "");
    }

    function test_shouldPass_whenLenderSignature_whenBorrowerAccepts() external {
        extension.proposer = lender;

        vm.prank(borrower);
        loan.extendLOAN(extension, _signExtension(lenderPk, extension), "");
    }

}


/*----------------------------------------------------------*|
|*  # GET EXTENSION HASH                                    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_GetExtensionHash_Test is PWNSimpleLoanTest {

    function test_shouldHaveCorrectDomainSeparator() external {
        assertEq(_extensionHash(extension), loan.getExtensionHash(extension));
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN                                              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_GetLOAN_Test is PWNSimpleLoanTest {

    function testFuzz_shouldReturnStaticLOANData(
        uint40 _startTimestamp,
        uint40 _defaultTimestamp,
        address _borrower,
        address _originalLender,
        uint40 _accruingInterestDailyRate,
        uint256 _fixedInterestAmount,
        address _creditAddress,
        uint256 _principalAmount,
        uint8 _collateralCategory,
        address _collateralAssetAddress,
        uint256 _collateralId,
        uint256 _collateralAmount
    ) external {
        _startTimestamp = uint40(bound(_startTimestamp, 0, type(uint40).max - 1));
        _defaultTimestamp = uint40(bound(_defaultTimestamp, _startTimestamp + 1, type(uint40).max));
        _accruingInterestDailyRate = uint40(bound(_accruingInterestDailyRate, 0, 274e8));
        _fixedInterestAmount = bound(_fixedInterestAmount, 0, type(uint256).max - _principalAmount);

        simpleLoan.startTimestamp = _startTimestamp;
        simpleLoan.defaultTimestamp = _defaultTimestamp;
        simpleLoan.borrower = _borrower;
        simpleLoan.originalLender = _originalLender;
        simpleLoan.accruingInterestDailyRate = _accruingInterestDailyRate;
        simpleLoan.fixedInterestAmount = _fixedInterestAmount;
        simpleLoan.creditAddress = _creditAddress;
        simpleLoan.principalAmount = _principalAmount;
        simpleLoan.collateral.category = MultiToken.Category(_collateralCategory % 4);
        simpleLoan.collateral.assetAddress = _collateralAssetAddress;
        simpleLoan.collateral.id = _collateralId;
        simpleLoan.collateral.amount = _collateralAmount;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(_startTimestamp);

        // test every property separately to avoid stack too deep error
        {
            (,uint40 startTimestamp,,,,,,,,,) = loan.getLOAN(loanId);
            assertEq(startTimestamp, _startTimestamp);
        }
        {
            (,,uint40 defaultTimestamp,,,,,,,,) = loan.getLOAN(loanId);
            assertEq(defaultTimestamp, _defaultTimestamp);
        }
        {
            (,,,address borrower,,,,,,,) = loan.getLOAN(loanId);
            assertEq(borrower, _borrower);
        }
        {
            (,,,,address originalLender,,,,,,) = loan.getLOAN(loanId);
            assertEq(originalLender, _originalLender);
        }
        {
            (,,,,,,uint40 accruingInterestDailyRate,,,,) = loan.getLOAN(loanId);
            assertEq(accruingInterestDailyRate, _accruingInterestDailyRate);
        }
        {
            (,,,,,,,uint256 fixedInterestAmount,,,) = loan.getLOAN(loanId);
            assertEq(fixedInterestAmount, _fixedInterestAmount);
        }
        {
            (,,,,,,,,MultiToken.Asset memory credit,,) = loan.getLOAN(loanId);
            assertEq(credit.assetAddress, _creditAddress);
            assertEq(credit.amount, _principalAmount);
        }
        {
            (,,,,,,,,,MultiToken.Asset memory collateral,) = loan.getLOAN(loanId);
            assertEq(collateral.assetAddress, _collateralAssetAddress);
            assertEq(uint8(collateral.category), _collateralCategory % 4);
            assertEq(collateral.id, _collateralId);
            assertEq(collateral.amount, _collateralAmount);
        }
    }

    function test_shouldReturnCorrectStatus() external {
        _mockLOAN(loanId, simpleLoan);

        (uint8 status,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 2);

        vm.warp(simpleLoan.defaultTimestamp);

        (status,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 4);

        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        (status,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 3);
    }

    function testFuzz_shouldReturnLOANTokenOwner(address _loanOwner) external {
        _mockLOAN(loanId, simpleLoan);
        _mockLOANTokenOwner(loanId, _loanOwner);

        (,,,,, address loanOwner,,,,,) = loan.getLOAN(loanId);
        assertEq(loanOwner, _loanOwner);
    }

    function testFuzz_shouldReturnRepaymentAmount(
        uint256 _days,
        uint256 _principalAmount,
        uint40 _accruingInterestDailyRate,
        uint256 _fixedInterestAmount
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays);
        _principalAmount = bound(_principalAmount, 1, 1e40);
        _accruingInterestDailyRate = uint40(bound(_accruingInterestDailyRate, 0, 274e8));
        _fixedInterestAmount = bound(_fixedInterestAmount, 0, _principalAmount);

        simpleLoan.accruingInterestDailyRate = _accruingInterestDailyRate;
        simpleLoan.fixedInterestAmount = _fixedInterestAmount;
        simpleLoan.principalAmount = _principalAmount;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        (,,,,,,,,,, uint256 repaymentAmount) = loan.getLOAN(loanId);
        assertEq(repaymentAmount, loan.loanRepaymentAmount(loanId));
    }

    function test_shouldReturnEmptyLOANDataForNonExistingLoan() external {
        uint256 nonExistingLoanId = loanId + 1;

        (
            uint8 status,
            uint40 startTimestamp,
            uint40 defaultTimestamp,
            address borrower,
            address originalLender,
            address loanOwner,
            uint40 accruingInterestDailyRate,
            uint256 fixedInterestAmount,
            MultiToken.Asset memory credit,
            MultiToken.Asset memory collateral,
            uint256 repaymentAmount
        ) = loan.getLOAN(nonExistingLoanId);

        assertEq(status, 0);
        assertEq(startTimestamp, 0);
        assertEq(defaultTimestamp, 0);
        assertEq(borrower, address(0));
        assertEq(originalLender, address(0));
        assertEq(loanOwner, address(0));
        assertEq(accruingInterestDailyRate, 0);
        assertEq(fixedInterestAmount, 0);
        assertEq(credit.assetAddress, address(0));
        assertEq(credit.amount, 0);
        assertEq(collateral.assetAddress, address(0));
        assertEq(uint8(collateral.category), 0);
        assertEq(collateral.id, 0);
        assertEq(collateral.amount, 0);
        assertEq(repaymentAmount, 0);
    }

}


/*----------------------------------------------------------*|
|*  # LOAN METADATA URI                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_LoanMetadataUri_Test is PWNSimpleLoanTest {

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

contract PWNSimpleLoan_GetStateFingerprint_Test is PWNSimpleLoanTest {

    function test_shouldReturnZeroIfLoanDoesNotExist() external {
        bytes32 fingerprint = loan.getStateFingerprint(loanId);

        assertEq(fingerprint, bytes32(0));
    }

    function test_shouldUpdateStateFingerprint_whenLoanDefaulted() external {
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp - 1);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(2, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestDailyRate))
        );

        vm.warp(simpleLoan.defaultTimestamp);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(4, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestDailyRate))
        );
    }

    function testFuzz_shouldReturnCorrectStateFingerprint(
        uint256 fixedInterestAmount, uint40 accruingInterestDailyRate
    ) external {
        simpleLoan.fixedInterestAmount = fixedInterestAmount;
        simpleLoan.accruingInterestDailyRate = accruingInterestDailyRate;
        _mockLOAN(loanId, simpleLoan);

        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(2, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestDailyRate))
        );
    }

}
