// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { IERC721Receiver } from "openzeppelin/token/ERC721/IERC721Receiver.sol";

import {
    PWNLoan,
    LOANStatus,
    PWNHubTags,
    Math,
    MultiToken,
    Terms,
    IPWNBorrowerCreateHook, BORROWER_CREATE_HOOK_RETURN_VALUE,
    IPWNBorrowerCollateralRepaymentHook, BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE,
    IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE,
    IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE,
    IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE,
    IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE,
    IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE,
    IPWNProposal
} from "pwn/core/loan/PWNLoan.sol";

import { ReentrancySpy } from "test/helper/ReentrancySpy.sol";
import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";

using MultiToken for MultiToken.Asset;
using MultiToken for address;

abstract contract PWNLoanTest is Test {

    bytes32 internal constant LOANS_SLOT = bytes32(uint256(0)); // `LOANs` mapping position
    bytes32 internal constant LENDERS_REPAYMENT_HOOK_SLOT = bytes32(uint256(1)); // `lenderRepaymentHook` mapping position
    bytes32 internal constant LOAN_LOCK_SLOT = bytes32(uint256(2)); // `loanLock` mapping position

    PWNLoan loanContract;
    address hub = makeAddr("hub");
    address loanToken = makeAddr("loanToken");
    address config = makeAddr("config");
    address categoryRegistry = makeAddr("categoryRegistry");
    address feeCollector = makeAddr("feeCollector");
    address alice = makeAddr("alice");
    address proposalContract = makeAddr("proposalContract");
    IPWNInterestModule interestModule = IPWNInterestModule(makeAddr("interestModule"));
    IPWNDefaultModule defaultModule = IPWNDefaultModule(makeAddr("defaultModule"));
    IPWNLiquidationModule liquidationModule = IPWNLiquidationModule(makeAddr("liquidationModule"));
    IPWNBorrowerCreateHook borrowerCreateHook = IPWNBorrowerCreateHook(makeAddr("borrowerCreateHook"));
    IPWNBorrowerCollateralRepaymentHook borrowerCollateralRepaymentHook = IPWNBorrowerCollateralRepaymentHook(makeAddr("borrowerCollateralRepaymentHook"));
    IPWNLenderCreateHook lenderCreateHook = IPWNLenderCreateHook(makeAddr("lenderCreateHook"));
    IPWNLenderRepaymentHook lenderRepaymentHook = IPWNLenderRepaymentHook(makeAddr("lenderRepaymentHook"));
    bytes32 proposalHash = keccak256("proposalHash");
    bytes proposalData = bytes("proposalData");
    bytes signature = bytes("signature");
    uint256 loanId = 42;
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");
    Terms terms;
    PWNLoan.LOAN loan;
    PWNLoan.LOAN nonExistingLoan;
    PWNLoan.ProposalSpec proposalSpec;
    PWNLoan.LenderSpec lenderSpec;
    PWNLoan.BorrowerSpec borrowerSpec;
    T20 fungibleAsset;
    T721 nonFungibleAsset;
    ReentrancySpy reentrancySpy = new ReentrancySpy();

    event LOANCreated(uint256 indexed loanId, bytes32 indexed proposalHash, address indexed proposalContract, Terms terms, PWNLoan.LenderSpec lenderSpec, PWNLoan.BorrowerSpec borrowerSpec, bytes extra);
    event LOANRepaid(uint256 indexed loanId, uint256 repaymentAmount, uint256 indexed newPrincipal);
    event LOANRepaymentClaimed(uint256 indexed loanId, uint256 claimedAmount);
    event LOANLiquidated(uint256 indexed loanId, address indexed liquidator, uint256 liquidationAmount);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(loanToken, bytes("data"));
        vm.etch(proposalContract, bytes("data"));
        vm.etch(config, bytes("data"));

        loanContract = new PWNLoan(hub, loanToken, config, categoryRegistry);
        fungibleAsset = new T20();
        nonFungibleAsset = new T721();

        fungibleAsset.mint(lender, 1000 ether);
        fungibleAsset.mint(borrower, 1000 ether);
        fungibleAsset.mint(address(this), 1000 ether);
        fungibleAsset.mint(address(loanContract), 1000 ether);
        nonFungibleAsset.mint(borrower, 2);

        vm.prank(lender);
        fungibleAsset.approve(address(loanContract), type(uint256).max);

        vm.prank(borrower);
        fungibleAsset.approve(address(loanContract), type(uint256).max);

        vm.prank(address(this));
        fungibleAsset.approve(address(loanContract), type(uint256).max);

        vm.prank(borrower);
        nonFungibleAsset.approve(address(loanContract), 2);

        lenderSpec = PWNLoan.LenderSpec({
            createHook: IPWNLenderCreateHook(address(0)),
            createHookData: "",
            repaymentHook: IPWNLenderRepaymentHook(address(0)),
            repaymentHookData: ""
        });

        borrowerSpec = PWNLoan.BorrowerSpec({
            createHook: IPWNBorrowerCreateHook(address(0)),
            createHookData: ""
        });

        proposalSpec = PWNLoan.ProposalSpec({
            proposalContract: proposalContract,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: signature
        });

        terms = Terms({
            proposalHash: proposalHash,
            lender: lender,
            borrower: borrower,
            proposerSpecHash: bytes32(0),
            collateral: address(nonFungibleAsset).ERC721(2),
            creditAddress: address(fungibleAsset),
            principal: 100 ether,
            interestModule: interestModule,
            interestModuleProposerData: "",
            defaultModule: defaultModule,
            defaultModuleProposerData: "",
            liquidationModule: liquidationModule,
            liquidationModuleProposerData: ""
        });

        loan = PWNLoan.LOAN({
            borrower: borrower,
            lastUpdateTimestamp: uint40(block.timestamp),
            collateral: address(nonFungibleAsset).ERC721(2),
            creditAddress: address(fungibleAsset),
            principal: 100 ether,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            interestModule: interestModule,
            defaultModule: defaultModule,
            liquidationModule: liquidationModule
        });

        nonExistingLoan = PWNLoan.LOAN({
            borrower: address(0),
            lastUpdateTimestamp: 0,
            collateral: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: address(0),
                id: 0,
                amount: 0
            }),
            creditAddress: address(0),
            principal: 0,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            interestModule: IPWNInterestModule(address(0)),
            defaultModule: IPWNDefaultModule(address(0)),
            liquidationModule: IPWNLiquidationModule(address(0))
        });

        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)"),
            abi.encode(type(uint8).max)
        );

        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(0));
        vm.mockCall(config, abi.encodeWithSignature("feeCollector()"), abi.encode(feeCollector));

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        _mockHubTag(proposalContract, PWNHubTags.LOAN_PROPOSAL);
        _mockHubTag(address(interestModule), PWNHubTags.MODULE);
        _mockHubTag(address(defaultModule), PWNHubTags.MODULE);
        _mockHubTag(address(liquidationModule), PWNHubTags.MODULE);

        _mockModuleCreationHook(address(interestModule), INTEREST_MODULE_INIT_HOOK_RETURN_VALUE);
        _mockModuleCreationHook(address(defaultModule), DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE);
        _mockModuleCreationHook(address(liquidationModule), LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE);

        _mockHubTag(address(lenderCreateHook), PWNHubTags.HOOK);
        _mockHubTag(address(lenderRepaymentHook), PWNHubTags.HOOK);
        _mockHubTag(address(borrowerCreateHook), PWNHubTags.HOOK);
        _mockHubTag(address(borrowerCollateralRepaymentHook), PWNHubTags.HOOK);

        vm.mockCall(
            address(lenderCreateHook),
            abi.encodeWithSelector(IPWNLenderCreateHook.onLoanCreated.selector),
            abi.encode(LENDER_CREATE_HOOK_RETURN_VALUE)
        );
        vm.mockCall(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(IPWNLenderRepaymentHook.onLoanRepaid.selector),
            abi.encode(LENDER_REPAYMENT_HOOK_RETURN_VALUE)
        );
        vm.mockCall(
            address(borrowerCreateHook),
            abi.encodeWithSelector(IPWNBorrowerCreateHook.onLoanCreated.selector),
            abi.encode(BORROWER_CREATE_HOOK_RETURN_VALUE)
        );
        vm.mockCall(
            address(borrowerCollateralRepaymentHook),
            abi.encodeWithSelector(IPWNBorrowerCollateralRepaymentHook.onLoanRepaid.selector),
            abi.encode(BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE)
        );
        vm.mockCall(
            address(borrowerCollateralRepaymentHook),
            abi.encodeWithSelector(IERC721Receiver.onERC721Received.selector),
            abi.encode(IERC721Receiver.onERC721Received.selector)
        );
        vm.mockCall(
            address(liquidationModule),
            abi.encodeWithSelector(IERC721Receiver.onERC721Received.selector),
            abi.encode(IERC721Receiver.onERC721Received.selector)
        );

        _mockLoanTerms(terms);
        _mockLOANMint(loanId);
        _mockLOANTokenOwner(loanId, lender);
        _mockIsDefaulted(loanId, false);
        _mockInterest(loanId, 0);
    }

    // Assert

    function _assertLOANEq(PWNLoan.LOAN memory _loan1, PWNLoan.LOAN memory _loan2) internal {
        assertEq(keccak256(abi.encode(_loan1)), keccak256(abi.encode(_loan2)));
    }

    function _assertLOANEq(uint256 _loanId, PWNLoan.LOAN memory _loan) internal {
        assertEq(keccak256(abi.encode(loanContract.getLOAN(_loanId))), keccak256(abi.encode(_loan)));
    }

    // Mock

    function _mockLOAN(uint256 _loanId, PWNLoan.LOAN memory _loan) internal {
        uint256 slot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        _storeLOANWord(slot + 0, abi.encodePacked(uint56(0), _loan.lastUpdateTimestamp, _loan.borrower));
        _storeLOANWord(slot + 1, abi.encodePacked(uint88(0), _loan.collateral.assetAddress, _loan.collateral.category));
        _storeLOANWord(slot + 2, abi.encodePacked(_loan.collateral.id));
        _storeLOANWord(slot + 3, abi.encodePacked(_loan.collateral.amount));
        _storeLOANWord(slot + 4, abi.encodePacked(uint96(0), _loan.creditAddress));
        _storeLOANWord(slot + 5, abi.encodePacked(_loan.principal));
        _storeLOANWord(slot + 6, abi.encodePacked(_loan.pastAccruedInterest));
        _storeLOANWord(slot + 7, abi.encodePacked(_loan.unclaimedRepayment));
        _storeLOANWord(slot + 8, abi.encodePacked(uint96(0), _loan.interestModule));
        _storeLOANWord(slot + 9, abi.encodePacked(uint96(0), _loan.defaultModule));
        _storeLOANWord(slot + 10, abi.encodePacked(uint96(0), _loan.liquidationModule));
    }

    function _mockLoanTerms(Terms memory _terms) internal {
        vm.mockCall(proposalContract, abi.encodeWithSelector(IPWNProposal.acceptProposal.selector), abi.encode(_terms));
    }

    function _mockLOANMint(uint256 _loanId) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("mint(address)"), abi.encode(_loanId));
    }

    function _mockLOANTokenOwner(uint256 _loanId, address _owner) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", _loanId), abi.encode(_owner));
    }

    function _mockHubTag(address _contract, bytes32 _tag) internal {
        _mockHubTag(_contract, _tag, true);
    }

    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

    function _mockIsDefaulted(uint256 _loanId, bool _defaulted) internal {
        vm.mockCall(
            address(defaultModule),
            abi.encodeWithSignature("isDefaulted(address,uint256)", address(loanContract), _loanId),
            abi.encode(_defaulted)
        );
    }

    function _mockInterest(uint256 _loanId, uint256 _interest) internal {
        vm.mockCall(
            address(interestModule),
            abi.encodeWithSignature("interest(address,uint256)", address(loanContract), _loanId),
            abi.encode(_interest)
        );
    }

    function _mockLiquidation(uint256 _loanId, uint256 _liquidationAmount) internal {
        vm.mockCall(
            address(liquidationModule),
            abi.encodeWithSelector(IPWNLiquidationModule.liquidate.selector, _loanId),
            abi.encode(_liquidationAmount)
        );
    }

    function _mockModuleCreationHook(address _module, bytes32 _returnValue) internal {
        vm.mockCall(_module, abi.encodeWithSignature("onLoanCreated(uint256,bytes)"), abi.encode(_returnValue));
    }

    function _mockLockedLoanContext(uint256 _loanId, bool _locked) internal {
        vm.store(address(loanContract), bytes32(uint256(keccak256(abi.encode(_loanId, LOAN_LOCK_SLOT)))), bytes32(uint256(_locked ? 1 : 0)));
    }

    // Store

    function _storeLOANWord(uint256 wordSlot, bytes memory word) private {
        vm.store(address(loanContract), bytes32(wordSlot), _bytesToBytes32(word));
    }

    function _bytesToBytes32(bytes memory _bytes) private pure returns (bytes32 _bytes32) {
        assembly {
            _bytes32 := mload(add(_bytes, 32))
        }
    }

}


/*----------------------------------------------------------*|
|*  # CREATE                                                *|
|*----------------------------------------------------------*/

contract PWNLoan_Create_Test is PWNLoanTest {

    function testFuzz_shouldFail_whenProposalContractNotTagged_LOAN_PROPOSAL(address _proposalContract) external {
        vm.assume(_proposalContract != proposalContract);

        proposalSpec.proposalContract = _proposalContract;

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, _proposalContract, PWNHubTags.LOAN_PROPOSAL)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldCallProposalContract(
        address caller, bytes memory _proposalData, bytes32[] memory _proposalInclusionProof, bytes memory _signature
    ) external {
        proposalSpec.proposalData = _proposalData;
        proposalSpec.proposalInclusionProof = _proposalInclusionProof;
        proposalSpec.signature = _signature;

        vm.expectCall(
            proposalContract,
            abi.encodeWithSignature(
                "acceptProposal(address,bytes,bytes32[],bytes)",
                caller, _proposalData, _proposalInclusionProof, _signature
            )
        );

        vm.prank(caller);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenCallerLender_whenProposerSpecHashMismatch() external {
        borrowerSpec.createHookData = "wrong spec";
        bytes32 borrowerSpecHash = loanContract.getBorrowerSpecHash(borrowerSpec);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidProposerSpecHash.selector, borrowerSpecHash, bytes32(0))
        );
        vm.prank(lender);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenCallerBorrower_whenProposerSpecHashMismatch() external {
        lenderSpec.createHookData = "wrong spec";
        lenderSpec.repaymentHookData = "wrong spec";
        bytes32 lenderSpecHash = loanContract.getLenderSpecHash(lenderSpec);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidProposerSpecHash.selector, lenderSpecHash, bytes32(0))
        );
        vm.prank(borrower);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenInvalidCreditAsset() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", terms.creditAddress),
            abi.encode(1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNLoan.InvalidMultiTokenAsset.selector,
                uint8(MultiToken.Category.ERC20), terms.creditAddress, 0, terms.principal
            )
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenInvalidCollateralAsset() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", terms.collateral.assetAddress),
            abi.encode(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNLoan.InvalidMultiTokenAsset.selector,
                uint8(terms.collateral.category),
                terms.collateral.assetAddress,
                terms.collateral.id,
                terms.collateral.amount
            )
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldMintLOANToken() external {
        vm.expectCall(address(loanToken), abi.encodeWithSignature("mint(address)", lender));

        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldStoreLoanData() external {
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        _assertLOANEq(loanId, loan);
    }

    function test_shouldEmit_LOANCreated() external {
        vm.expectEmit();
        emit LOANCreated(loanId, proposalHash, proposalContract, terms, lenderSpec, borrowerSpec, "lil extra");

        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: "lil extra"
        });
    }

    function testFuzz_shouldStoreLenderRepaymentHook(address _hook, bytes memory _hookData) external {
        vm.assume(_hook != address(0));

        lenderSpec.repaymentHook = IPWNLenderRepaymentHook(_hook);
        lenderSpec.repaymentHookData = _hookData;

        vm.prank(lender);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        (IPWNLenderRepaymentHook hook, bytes memory hookData) = loanContract.lenderRepaymentHook(lender, loanId);
        assertEq(address(hook), _hook);
        assertEq(keccak256(hookData), keccak256(_hookData));
    }

    function testFuzz_shouldNotStoreLenderRepaymentHook_whenZero(bytes memory _hookData) external {
        lenderSpec.repaymentHook = IPWNLenderRepaymentHook(address(0));
        lenderSpec.repaymentHookData = _hookData;

        vm.prank(lender);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        (IPWNLenderRepaymentHook hook, bytes memory hookData) = loanContract.lenderRepaymentHook(lender, loanId);
        assertEq(address(hook), address(0));
        assertEq(hookData.length, 0);
    }

    // # Modules

    function test_shouldFail_whenModulesNotTaggedInHub() external {
        terms.interestModule = IPWNInterestModule(makeAddr("int mod"));
        terms.defaultModule = defaultModule;
        terms.liquidationModule = liquidationModule;
        _mockLoanTerms(terms);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(terms.interestModule), PWNHubTags.MODULE)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        terms.interestModule = interestModule;
        terms.defaultModule = IPWNDefaultModule(makeAddr("def mod"));
        terms.liquidationModule = liquidationModule;
        _mockLoanTerms(terms);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(terms.defaultModule), PWNHubTags.MODULE)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        terms.interestModule = interestModule;
        terms.defaultModule = defaultModule;
        terms.liquidationModule = IPWNLiquidationModule(makeAddr("liq mod"));
        _mockLoanTerms(terms);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(terms.liquidationModule), PWNHubTags.MODULE)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenModulesReturnWrongValue() external {
        bytes32 wrongReturn = keccak256("wrong return");

        _mockModuleCreationHook(address(interestModule), wrongReturn);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidHookReturnValue.selector, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE, wrongReturn)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        _mockModuleCreationHook(address(interestModule), INTEREST_MODULE_INIT_HOOK_RETURN_VALUE);
        _mockModuleCreationHook(address(defaultModule), wrongReturn);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidHookReturnValue.selector, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE, wrongReturn)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        _mockModuleCreationHook(address(defaultModule), DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE);
        _mockModuleCreationHook(address(liquidationModule), wrongReturn);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidHookReturnValue.selector, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE, wrongReturn)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldInitializeModules() external {
        terms.interestModuleProposerData = "interest data";
        terms.defaultModuleProposerData = "default data";
        terms.liquidationModuleProposerData = "liquidation data";
        _mockLoanTerms(terms);

        vm.expectCall(
            address(interestModule),
            abi.encodeWithSignature("onLoanCreated(uint256,bytes)", loanId, terms.interestModuleProposerData)
        );
        vm.expectCall(
            address(defaultModule),
            abi.encodeWithSignature("onLoanCreated(uint256,bytes)", loanId, terms.defaultModuleProposerData)
        );
        vm.expectCall(
            address(liquidationModule),
            abi.encodeWithSignature("onLoanCreated(uint256,bytes)", loanId, terms.liquidationModuleProposerData)
        );

        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenLoanDefaultedOnCreation() external {
        _mockIsDefaulted(loanId, true);

        vm.expectCall(
            address(defaultModule),
            abi.encodeWithSelector(IPWNDefaultModule.isDefaulted.selector, address(loanContract), loanId)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.DefaultedOnCreation.selector));
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    // # Lender transfers

    function test_shouldCallLenderCreateHook() external {
        lenderSpec.createHook = lenderCreateHook;
        lenderSpec.createHookData = "hook data";

        vm.expectCall(
            address(lenderCreateHook),
            abi.encodeWithSelector(
                IPWNLenderCreateHook.onLoanCreated.selector,
                lender, terms.creditAddress, terms.principal, lenderSpec.createHookData
            )
        );

        vm.prank(lender);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenLenderCreateHookNotTaggedInHub() external {
        lenderSpec.createHook = IPWNLenderCreateHook(makeAddr("not tagged lender create hook"));

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(lenderSpec.createHook), PWNHubTags.HOOK)
        );
        vm.prank(lender);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenLenderCreateHookReturnsWrongValue() external {
        lenderSpec.createHook = lenderCreateHook;

        bytes32 wrongReturn = keccak256("wrong return");
        vm.mockCall(
            address(lenderCreateHook),
            abi.encodeWithSelector(IPWNLenderCreateHook.onLoanCreated.selector),
            abi.encode(wrongReturn)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidHookReturnValue.selector, LENDER_CREATE_HOOK_RETURN_VALUE, wrongReturn)
        );
        vm.prank(lender);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferCredit_toBorrowerAndFeeCollector(
        uint256 fee, uint256 loanAmount
    ) external {
        fee = bound(fee, 0, 9999);
        loanAmount = bound(loanAmount, 1, 1e40);

        terms.principal = loanAmount;
        _mockLoanTerms(terms);

        fungibleAsset.mint(lender, loanAmount);

        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        uint256 feeAmount = Math.mulDiv(loanAmount, fee, 1e4);
        uint256 newAmount = loanAmount - feeAmount;

        // Fee transfer
        vm.expectCall({
            callee: terms.creditAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, feeCollector, feeAmount),
            count: feeAmount > 0 ? 1 : 0
        });
        // Updated amount transfer
        vm.expectCall(
            terms.creditAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, borrower, newAmount)
        );

        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    // # Borrower transfers

    function test_shouldCallBorrowerCreateHook() external {
        borrowerSpec.createHook = borrowerCreateHook;
        borrowerSpec.createHookData = "hook data";

        vm.expectCall(
            address(borrowerCreateHook),
            abi.encodeWithSelector(
                IPWNBorrowerCreateHook.onLoanCreated.selector,
                borrower, terms.collateral, terms.creditAddress, terms.principal, borrowerSpec.createHookData
            )
        );

        vm.prank(borrower);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenBorrowerCreateHookNotTaggedInHub() external {
        borrowerSpec.createHook = IPWNBorrowerCreateHook(makeAddr("not tagged lender create hook"));

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(borrowerSpec.createHook), PWNHubTags.HOOK)
        );
        vm.prank(borrower);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenBorrowerCreateHookReturnsWrongValue() external {
        borrowerSpec.createHook = borrowerCreateHook;

        bytes32 wrongReturn = keccak256("wrong return");
        vm.mockCall(
            address(borrowerCreateHook),
            abi.encodeWithSelector(IPWNBorrowerCreateHook.onLoanCreated.selector),
            abi.encode(wrongReturn)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidHookReturnValue.selector, BORROWER_CREATE_HOOK_RETURN_VALUE, wrongReturn)
        );
        vm.prank(borrower);
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function test_shouldTransferCollateral_fromBorrower_toVault() external {
        terms.collateral.category = MultiToken.Category.ERC20;
        terms.collateral.assetAddress = address(fungibleAsset);
        terms.collateral.id = 0;
        terms.collateral.amount = 100;
        _mockLoanTerms(terms);

        vm.expectCall(
            terms.collateral.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loanContract), terms.collateral.amount
            )
        );

        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldReturnNewLoanId(uint256 _loanId) external {
        _mockLOANMint(_loanId);
        _mockIsDefaulted(_loanId, false);

        uint256 createdLoanId = loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        assertEq(createdLoanId, _loanId);
    }

    // # Reentrancy

    function test_shouldFail_whenReenteringSameLoan() external {
        terms.interestModule = IPWNInterestModule(address(reentrancySpy));
        _mockLoanTerms(terms);

        _mockHubTag(address(reentrancySpy), PWNHubTags.MODULE);

        // Repay
        reentrancySpy.reenter(address(loanContract), abi.encodeWithSelector(PWNLoan.repay.selector, loanId, 0));
        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        // Repay with collateral
        reentrancySpy.reenter(address(loanContract), abi.encodeWithSelector(PWNLoan.repayWithCollateral.selector, loanId, borrowerCollateralRepaymentHook, ""));
        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        // Liquidate
        reentrancySpy.reenter(address(loanContract), abi.encodeWithSelector(PWNLoan.liquidate.selector, loanId, ""));
        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });

        // Claim repayment
        reentrancySpy.reenter(address(loanContract), abi.encodeWithSelector(PWNLoan.claimRepayment.selector, loanId));
        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId)
        );
        loanContract.create({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

}


/*----------------------------------------------------------*|
|*  # REPAY                                                 *|
|*----------------------------------------------------------*/

contract PWNLoan_Repay_Test is PWNLoanTest {

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, loan);
        _mockInterest(loanId, 1 ether);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loanContract), 2);
    }


    function test_shouldFail_whenReenteringLoanContext() external {
        _mockLockedLoanContext(loanId, true);
        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId));
        loanContract.repay(loanId, 0);
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        // Dead
        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanNotRunning.selector));
        loanContract.repay(loanId + 1, 0);

        // Repaid
        loan.principal = 0;
        loan.unclaimedRepayment = 1;
        _mockLOAN(loanId, loan);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanNotRunning.selector));
        loanContract.repay(loanId, 0);

        // Defaulted
        loan.principal = 1;
        loan.unclaimedRepayment = 0;
        _mockLOAN(loanId, loan);

        _mockIsDefaulted(loanId, true);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanNotRunning.selector));
        loanContract.repay(loanId, 0);
    }

    function test_shouldFail_whenRepaymentAmountHigherThanTotalDebt() external {
        uint256 debt = loanContract.getLOANDebt(loanId);
        vm.expectRevert(abi.encodeWithSelector(PWNLoan.InvalidRepaymentAmount.selector, debt + 1, debt));
        loanContract.repay(loanId, debt + 1);
    }

    function test_shouldFetchInterestFromModule() external {
        vm.expectCall(
            address(interestModule),
            abi.encodeWithSelector(IPWNInterestModule.interest.selector, address(loanContract), loanId)
        );

        loanContract.repay(loanId, 0);
    }

    function test_shouldRepayTotalDebt_whenRepaymentAmountIsZero() external {
        loanContract.repay(loanId, 0);

        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.REPAID);
    }

    function test_shouldEmit_LOANRepaid() external {
        vm.expectEmit();
        emit LOANRepaid(loanId, 10 ether, loan.principal + 1 ether - 10 ether); // Note: interest is 1 ether

        loanContract.repay(loanId, 10 ether);
    }

    // # Update state

    function test_shouldDecreaseLoanDebt() external {
        // Note: current interest is 1 ether
        loanContract.repay(loanId, 0.6 ether); // only part of accrued interest

        PWNLoan.LOAN memory updatedLoan = loanContract.getLOAN(loanId);
        assertEq(updatedLoan.principal, loan.principal);
        assertEq(updatedLoan.pastAccruedInterest, 0.4 ether); // store unpaid interest
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.RUNNING);

        // Note: interest module returns 1 ether

        loanContract.repay(loanId, 1.6 ether); // full interest + part of principal

        updatedLoan = loanContract.getLOAN(loanId);
        assertEq(updatedLoan.principal, loan.principal - 0.2 ether);
        assertEq(updatedLoan.pastAccruedInterest, 0);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.RUNNING);

        // Note: interest module returns 1 ether

        loanContract.repay(loanId, 51 ether);

        updatedLoan = loanContract.getLOAN(loanId);
        assertEq(updatedLoan.principal, loan.principal - 50.2 ether);
        assertEq(updatedLoan.pastAccruedInterest, 0);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.RUNNING);

        // Note: interest module returns 1 ether

        loanContract.repay(loanId, 0.2 ether);

        updatedLoan = loanContract.getLOAN(loanId);
        assertEq(updatedLoan.principal, loan.principal - 50.2 ether);
        assertEq(updatedLoan.pastAccruedInterest, 0.8 ether);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.RUNNING);

        // Note: interest module returns 1 ether

        loanContract.repay(loanId, 0);

        updatedLoan = loanContract.getLOAN(loanId);
        assertEq(updatedLoan.principal, 0);
        assertEq(updatedLoan.pastAccruedInterest, 0);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.REPAID);
    }

    function testFuzz_shouldUpdateLastUpdateTimestamp(uint40 timestamp) external {
        vm.warp(timestamp);

        loanContract.repay(loanId, 1);

        assertEq(loanContract.getLOAN(loanId).lastUpdateTimestamp, timestamp);
    }

    function test_shouldIncreseUnclaimedRepayment_whenTransferToVault() external {
        vm.prank(borrower);
        loanContract.repay(loanId, 10 ether);
        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, 10 ether);

        vm.prank(borrower);
        loanContract.repay(loanId, 4 ether);
        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, 14 ether);

        vm.prank(borrower);
        loanContract.repay(loanId, 50 ether);
        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, 64 ether);
    }

    function test_shouldNotIncreaseUnclaimedRepayment_whenTransferToLenderRepaymentHook() external {
        vm.prank(borrower);
        loanContract.repay(loanId, 10 ether);
        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, 10 ether);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.prank(borrower);
        loanContract.repay(loanId, 42 ether);

        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, 10 ether);
    }

    function test_shouldDeleteLoan_whenFullRepayment_whenTransferToLenderRepaymentHook() external {
        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        vm.prank(borrower);
        loanContract.repay(loanId, 0);

        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.DEAD);
        assertEq(loanContract.getLOAN(loanId).principal, 0);
        assertEq(loanContract.getLOAN(loanId).pastAccruedInterest, 0);
    }

    // # Collateral

    function test_shouldTransferCollateralToBorrower_whenFullRepayment() external {
        loanContract.repay(loanId, 0);

        assertEq(nonFungibleAsset.ownerOf(loan.collateral.id), borrower);
    }

    // # Repayment

    function testFuzz_shouldTransferRepaymentToVault_whenLenderRepaymentHookNotSet(uint256 repayment) external {
        repayment = bound(repayment, 1, loanContract.getLOANDebt(loanId));

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, IPWNLenderRepaymentHook(address(0)), "");

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loanContract), repayment
            )
        );

        vm.prank(borrower);
        loanContract.repay(loanId, repayment);
    }

    function testFuzz_shouldTransferRepaymentAndCallLenderRepaymentHook_whenSet(uint256 repayment) external {
        repayment = bound(repayment, 1, loanContract.getLOANDebt(loanId));

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "hook data");

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(lenderRepaymentHook), repayment
            )
        );
        vm.expectCall(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(
                IPWNLenderRepaymentHook.onLoanRepaid.selector, lender, loan.creditAddress, repayment, "hook data"
            )
        );

        vm.prank(borrower);
        loanContract.repay(loanId, repayment);
    }

    function testFuzz_shouldTransferRepaymentToVault_whenLenderRepaymentHookSet_whenNotTaggedInHub(uint256 repayment) external {
        repayment = bound(repayment, 1, loanContract.getLOANDebt(loanId));

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        _mockHubTag(address(lenderRepaymentHook), PWNHubTags.HOOK, false);

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loanContract), repayment
            )
        );

        uint256 vaultBalanceBefore = fungibleAsset.balanceOf(address(loanContract));

        vm.prank(borrower);
        loanContract.repay(loanId, repayment);

        assertEq(fungibleAsset.balanceOf(address(loanContract)), vaultBalanceBefore + repayment);
        assertEq(fungibleAsset.balanceOf(address(lenderRepaymentHook)), 0);
    }

    function testFuzz_shouldTransferRepaymentToVault_whenLenderRepaymentHookSet_whenWrongReturnValue(uint256 repayment) external {
        repayment = bound(repayment, 1, loanContract.getLOANDebt(loanId));

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.mockCall(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(IPWNLenderRepaymentHook.onLoanRepaid.selector),
            abi.encode(keccak256("wrong return value"))
        );

        _test_failedTransferToHook_transferToVault(repayment);
    }

    function testFuzz_shouldTransferRepaymentToVault_whenLenderRepaymentHookSet_whenReverts(uint256 repayment) external {
        repayment = bound(repayment, 1, loanContract.getLOANDebt(loanId));

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.mockCallRevert(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(IPWNLenderRepaymentHook.onLoanRepaid.selector),
            abi.encode("revert data")
        );

        _test_failedTransferToHook_transferToVault(repayment);
    }


    function _test_failedTransferToHook_transferToVault(uint256 repayment) private {
        // Expect transfer, but internal call should be reverted
        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(lenderRepaymentHook), repayment
            )
        );

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loanContract), repayment
            )
        );

        uint256 vaultBalanceBefore = fungibleAsset.balanceOf(address(loanContract));

        vm.prank(borrower);
        loanContract.repay(loanId, repayment);

        assertEq(fungibleAsset.balanceOf(address(loanContract)), vaultBalanceBefore + repayment);
        assertEq(fungibleAsset.balanceOf(address(lenderRepaymentHook)), 0);
    }

}


/*----------------------------------------------------------*|
|*  # REPAY WITH COLLATERAL                                 *|
|*----------------------------------------------------------*/

contract PWNLoan_RepayWithCollateral_Test is PWNLoanTest {

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, loan);
        _mockInterest(loanId, 1 ether);

        // Move collateral to vault
        vm.startPrank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loanContract), 2);
        fungibleAsset.approve(address(borrowerCollateralRepaymentHook), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(borrowerCollateralRepaymentHook));
        fungibleAsset.approve(address(loanContract), type(uint256).max);
        fungibleAsset.mint(address(borrowerCollateralRepaymentHook), 1000 ether);
    }


    function test_shouldFail_whenReenteringLoanContext() external {
        _mockLockedLoanContext(loanId, true);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId));
        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, borrowerCollateralRepaymentHook, "");
    }

    function testFuzz_shouldFail_whenCallerNotBorrower(address caller) external {
        vm.assume(caller != borrower);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.CallerNotBorrower.selector));
        vm.prank(caller);
        loanContract.repayWithCollateral(loanId, borrowerCollateralRepaymentHook, "");
    }

    function test_shouldFail_whenZeroBorrowerCollateralRepaymentHook() external {
        vm.expectRevert(abi.encodeWithSelector(PWNLoan.HookZeroAddress.selector));
        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, IPWNBorrowerCollateralRepaymentHook(address(0)), "");
    }

    function test_shouldTransferCollateralAndCallBorrowerCollateralRepaymentHook() external {
        vm.expectCall(
            loan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loanContract), address(borrowerCollateralRepaymentHook), loan.collateral.id, ""
            )
        );
        vm.expectCall(
            address(borrowerCollateralRepaymentHook),
            abi.encodeWithSelector(
                IPWNBorrowerCollateralRepaymentHook.onLoanRepaid.selector,
                borrower, loan.collateral, loan.creditAddress, loanContract.getLOANDebt(loanId), "hook data"
            )
        );

        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, borrowerCollateralRepaymentHook, "hook data");
    }

    function test_shouldFail_whenBorrowerCollateralRepaymentHookNotTaggedInHub() external {
        IPWNBorrowerCollateralRepaymentHook hook = IPWNBorrowerCollateralRepaymentHook(makeAddr("not tagged hook"));

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(hook), PWNHubTags.HOOK)
        );
        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, hook, "");
    }

    function test_shouldFail_whenBorrowerCollateralRepaymentHookReturnsWrongValue() external {
        bytes32 wrongReturn = keccak256("wrong return");
        vm.mockCall(
            address(borrowerCollateralRepaymentHook),
            abi.encodeWithSelector(IPWNBorrowerCollateralRepaymentHook.onLoanRepaid.selector),
            abi.encode(wrongReturn)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidHookReturnValue.selector, BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE, wrongReturn)
        );
        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, borrowerCollateralRepaymentHook, "");
    }

    function test_shouldFail_whenBorrowerCollateralRepaymentHookReverts() external {
        vm.mockCallRevert(
            address(borrowerCollateralRepaymentHook),
            abi.encodeWithSelector(IPWNBorrowerCollateralRepaymentHook.onLoanRepaid.selector),
            abi.encode("revert data")
        );

        vm.expectRevert(abi.encode("revert data"));
        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, borrowerCollateralRepaymentHook, "");
    }

    function test_shouldTransferRepaymentFromBorrowerHookToVault_whenLenderRepaymentHookNotSet() external {
        uint256 repayment = loanContract.getLOANDebt(loanId);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, IPWNLenderRepaymentHook(address(0)), "");

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(borrowerCollateralRepaymentHook), address(loanContract), repayment
            )
        );

        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, borrowerCollateralRepaymentHook, "");
    }

    function test_shouldTransferRepaymentFromBorrowerHookToLenderHook_whenLenderRepaymentHookIsSet() external {
        uint256 repayment = loanContract.getLOANDebt(loanId);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(borrowerCollateralRepaymentHook), address(lenderRepaymentHook), repayment
            )
        );

        vm.prank(borrower);
        loanContract.repayWithCollateral(loanId, borrowerCollateralRepaymentHook, "");
    }

}


/*----------------------------------------------------------*|
|*  # TRY CALL LENDER REPAYMENT HOOK                        *|
|*----------------------------------------------------------*/

contract PWNLoan_TryCallLenderRepaymentHook_Test is PWNLoanTest {

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, loan);
    }


    function testFuzz_shouldFail_whenCallerNotLoanContract(address caller) external {
        vm.assume(caller != address(loanContract));

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.CallerNotVault.selector));
        vm.prank(caller);
        loanContract.tryCallLenderRepaymentHook(
            PWNLoan.LenderRepaymentHookData(lenderRepaymentHook, ""),
            borrower, lender, loan.creditAddress, 1 ether
        );
    }

    function test_shouldFail_whenLenderRepaymentHookIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(PWNLoan.HookZeroAddress.selector));
        vm.prank(address(loanContract));
        loanContract.tryCallLenderRepaymentHook(
            PWNLoan.LenderRepaymentHookData(IPWNLenderRepaymentHook(address(0)), ""),
            borrower, lender, loan.creditAddress, 1 ether
        );
    }

    function test_shouldFail_whenLenderRepaymentHookNotTaggedInHub() external {
        _mockHubTag(address(lenderRepaymentHook), PWNHubTags.HOOK, false);

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, address(lenderRepaymentHook), PWNHubTags.HOOK)
        );
        vm.prank(address(loanContract));
        loanContract.tryCallLenderRepaymentHook(
            PWNLoan.LenderRepaymentHookData(lenderRepaymentHook, ""),
            borrower, lender, loan.creditAddress, 1 ether
        );
    }

    function test_shouldFail_whenLenderRepaymentHookReverts() external {
        vm.mockCallRevert(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(IPWNLenderRepaymentHook.onLoanRepaid.selector),
            abi.encode("revert data")
        );

        vm.expectRevert(abi.encode("revert data"));
        vm.prank(address(loanContract));
        loanContract.tryCallLenderRepaymentHook(
            PWNLoan.LenderRepaymentHookData(lenderRepaymentHook, ""),
            borrower, lender, loan.creditAddress, 1 ether
        );
    }

    function test_shouldFail_whenLenderRepaymentHookReturnsWrongValue() external {
        bytes32 wrongReturn = keccak256("wrong return");
        vm.mockCall(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(IPWNLenderRepaymentHook.onLoanRepaid.selector),
            abi.encode(wrongReturn)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNLoan.InvalidHookReturnValue.selector, LENDER_REPAYMENT_HOOK_RETURN_VALUE, wrongReturn)
        );
        vm.prank(address(loanContract));
        loanContract.tryCallLenderRepaymentHook(
            PWNLoan.LenderRepaymentHookData(lenderRepaymentHook, ""),
            borrower, lender, loan.creditAddress, 1 ether
        );
    }

    function testFuzz_shouldTransferRepaymentAndCallLenderRepaymentHook(uint256 repayment) external {
        repayment = bound(repayment, 1, loanContract.getLOANDebt(loanId));

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(lenderRepaymentHook), repayment
            )
        );
        vm.expectCall(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(
                IPWNLenderRepaymentHook.onLoanRepaid.selector, lender, loan.creditAddress, repayment, "hook data"
            )
        );

        vm.prank(address(loanContract));
        loanContract.tryCallLenderRepaymentHook(
            PWNLoan.LenderRepaymentHookData(lenderRepaymentHook, "hook data"),
            borrower, lender, loan.creditAddress, repayment
        );
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM REPAYMENT                                       *|
|*----------------------------------------------------------*/

contract PWNLoan_ClaimRepayment_Test is PWNLoanTest {

    function setUp() override public {
        super.setUp();

        loan.unclaimedRepayment = 100 ether;
        _mockLOAN(loanId, loan);
    }


    function test_shouldFail_whenReenteringLoanContext() external {
        _mockLockedLoanContext(loanId, true);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId));
        vm.prank(lender);
        loanContract.claimRepayment(loanId);
    }

    function testFuzz_shouldFail_whenCallerNotLender(address caller) external {
        vm.assume(caller != lender);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.CallerNotLOANTokenHolder.selector));
        vm.prank(caller);
        loanContract.claimRepayment(loanId);
    }

    function test_shouldFail_whenNothingToClaim() external {
        loan.unclaimedRepayment = 0;
        _mockLOAN(loanId, loan);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.NothingToClaim.selector));
        vm.prank(lender);
        loanContract.claimRepayment(loanId);
    }

    function test_shouldTransferRepaymentToLender() external {
        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, loan.unclaimedRepayment)
        );

        vm.prank(lender);
        loanContract.claimRepayment(loanId);
    }

    function test_shouldDeleteUnclaimedRepayment_whenLoanNotFullyRepaid() external {
        loan.principal = 1;
        _mockLOAN(loanId, loan);

        // Check that LOAN token is not burned
        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId), 0);

        vm.prank(lender);
        loanContract.claimRepayment(loanId);

        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, 0);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.RUNNING);
    }

    function test_shouldDeleteLoan_whenLoanFullyRepaid() external {
        loan.principal = 0;
        _mockLOAN(loanId, loan);

        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        vm.prank(lender);
        loanContract.claimRepayment(loanId);

        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.DEAD);
        _assertLOANEq(loanId, nonExistingLoan); // Loan should be deleted
    }

    function test_shouldEmit_LOANRepaymentClaimed() external {
        vm.expectEmit();
        emit LOANRepaymentClaimed(loanId, loan.unclaimedRepayment);

        vm.prank(lender);
        loanContract.claimRepayment(loanId);
    }

}


/*----------------------------------------------------------*|
|*  # LIQUIDATE                                             *|
|*----------------------------------------------------------*/

contract PWNLoan_Liquidate_Test is PWNLoanTest {

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, loan);
        _mockIsDefaulted(loanId, true);
        _mockLiquidation(loanId, 67 ether);

        vm.startPrank(address(liquidationModule));
        fungibleAsset.mint(address(liquidationModule), 100 ether); // Mocked liquidation amount
        fungibleAsset.approve(address(loanContract), type(uint256).max);
        vm.stopPrank();

        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loanContract), 2);
    }


    function test_shouldFail_whenReenteringLoanContext() external {
        _mockLockedLoanContext(loanId, true);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanContextLocked.selector, loanId));
        loanContract.liquidate(loanId, "");
    }

    function test_shouldFail_whenLoanIsNotDefaulted() external {
        _mockIsDefaulted(loanId, false);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.LoanNotDefaulted.selector));
        loanContract.liquidate(loanId, "");
    }

    function test_shouldEmit_LOANLiquidated() external {
        vm.expectEmit();
        emit LOANLiquidated(loanId, address(liquidationModule), 67 ether);

        loanContract.liquidate(loanId, "");
    }

    // # Collateral

    function test_shouldTransferCollateralToLiquidationModule() external {
        vm.expectCall(
            loan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loanContract), address(liquidationModule), loan.collateral.id, ""
            )
        );

        loanContract.liquidate(loanId, "");
    }

    // # Liquidation Module

    function test_shouldCallLiquidationModule() external {
        address liquidator = makeAddr("liquidator");
        uint256 debt = loanContract.getLOANDebt(loanId);

        vm.expectCall(
            address(liquidationModule),
            abi.encodeWithSelector(
                IPWNLiquidationModule.liquidate.selector,
                loanId, liquidator, debt, loan.creditAddress, loan.collateral, "module data"
            )
        );

        vm.prank(liquidator);
        loanContract.liquidate(loanId, "module data");
    }

    function test_shouldFail_whenLiquidationModuleCallReverts() external {
        vm.mockCallRevert(
            address(liquidationModule),
            abi.encodeWithSelector(IPWNLiquidationModule.liquidate.selector),
            abi.encode("revert data")
        );

        vm.expectRevert(abi.encode("revert data"));
        loanContract.liquidate(loanId, "");
    }

    // # Liquidation Amount - Transfer

    function testFuzz_shouldTransferLiquidationAmountToVault_whenLenderRepaymentHookNotSet(uint256 liquidationAmount) external {
        liquidationAmount = bound(liquidationAmount, 1, 100 ether); // Mocked liquidation amount
        _mockLiquidation(loanId, liquidationAmount);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, IPWNLenderRepaymentHook(address(0)), "");

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(liquidationModule), address(loanContract), liquidationAmount
            )
        );

        loanContract.liquidate(loanId, "");
    }

    function testFuzz_shouldTransferLiquidationAmountToVault_whenLenderRepaymentHookSet_whenReverts(uint256 liquidationAmount) external {
        liquidationAmount = bound(liquidationAmount, 1, 100 ether); // Mocked liquidation amount
        _mockLiquidation(loanId, liquidationAmount);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.mockCallRevert(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(IPWNLenderRepaymentHook.onLoanRepaid.selector),
            abi.encode("revert data")
        );

        _test_failedTransferToHook_transferToVault(liquidationAmount);
    }

    function testFuzz_shouldTransferLiquidationAmountToVault_whenLenderRepaymentHookSet_whenWrongReturnValue(uint256 liquidationAmount) external {
        liquidationAmount = bound(liquidationAmount, 1, 100 ether); // Mocked liquidation amount
        _mockLiquidation(loanId, liquidationAmount);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.mockCall(
            address(lenderRepaymentHook),
            abi.encodeWithSelector(IPWNLenderRepaymentHook.onLoanRepaid.selector),
            abi.encode("wrong return value")
        );

        _test_failedTransferToHook_transferToVault(liquidationAmount);
    }

    function testFuzz_shouldTransferLiquidationAmountToLenderRepaymentHook_whenLenderRepaymentHookSet(uint256 liquidationAmount) external {
        liquidationAmount = bound(liquidationAmount, 1, 100 ether); // Mocked liquidation amount
        _mockLiquidation(loanId, liquidationAmount);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(liquidationModule), address(lenderRepaymentHook), liquidationAmount
            )
        );

        loanContract.liquidate(loanId, "");
    }

    function test_shouldNotTransferLiquidationAmount_whenZero() external {
        _mockLiquidation(loanId, 0);

        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            0
        );

        loanContract.liquidate(loanId, "");
    }

    // # State updates

    function testFuzz_shouldUpdateLastUpdateTimestamp(uint40 timestamp) external {
        vm.warp(timestamp);

        loanContract.liquidate(loanId, "");

        assertEq(loanContract.getLOAN(loanId).lastUpdateTimestamp, timestamp);
    }

    function testFuzz_shouldDeleteAnyDebt(uint256 liquidationAmount) external {
        liquidationAmount = bound(liquidationAmount, 0, 100 ether);
        _mockLiquidation(loanId, liquidationAmount);
        loan.principal = 100 ether;
        loan.pastAccruedInterest = 50 ether;
        _mockLOAN(loanId, loan);

        loanContract.liquidate(loanId, "");

        PWNLoan.LOAN memory updatedLoan = loanContract.getLOAN(loanId);
        assertEq(updatedLoan.principal, 0);
        assertEq(updatedLoan.pastAccruedInterest, 0);
    }

    function testFuzz_shouldIncreseUnclaimedRepayment_whenTransferToVault(uint256 liquidationAmount) external {
        liquidationAmount = bound(liquidationAmount, 1, 100 ether);
        _mockLiquidation(loanId, liquidationAmount);

        loanContract.liquidate(loanId, "");

        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, loan.unclaimedRepayment + liquidationAmount);
    }

    function testFuzz_shouldNotIncreaseUnclaimedRepayment_whenTransferToLenderRepaymentHook(uint256 liquidationAmount) external {
        liquidationAmount = bound(liquidationAmount, 1, 100 ether);
        _mockLiquidation(loanId, liquidationAmount);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        loanContract.liquidate(loanId, "");

        assertEq(loanContract.getLOAN(loanId).unclaimedRepayment, loan.unclaimedRepayment);
    }

    function test_shouldDeleteLoan_whenZeroUnclaimedRepayment_whenTransferToLenderRepaymentHook() external {
        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "");

        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        loanContract.liquidate(loanId, "");

        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.DEAD);
    }


    function _test_failedTransferToHook_transferToVault(uint256 liquidationAmount) private {
        vm.expectCall( // reverts
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(liquidationModule), address(lenderRepaymentHook), liquidationAmount
            )
        );
        vm.expectCall(
            loan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(liquidationModule), address(loanContract), liquidationAmount
            )
        );

        uint256 vaultBalanceBefore = fungibleAsset.balanceOf(address(loanContract));

        loanContract.liquidate(loanId, "");

        assertEq(fungibleAsset.balanceOf(address(loanContract)), vaultBalanceBefore + liquidationAmount);
        assertEq(fungibleAsset.balanceOf(address(lenderRepaymentHook)), 0);
    }


}


/*----------------------------------------------------------*|
|*  # GET LOAN                                              *|
|*----------------------------------------------------------*/

contract PWNLoan_GetLOAN_Test is PWNLoanTest {

    function test_shouldReturnStoredLOAN() external {
        _mockLOAN(loanId, loan);
        PWNLoan.LOAN memory storedLoan = loanContract.getLOAN(loanId);
        _assertLOANEq(storedLoan, loan);

        loan.principal = 1030921031 ether;
        loan.unclaimedRepayment = 88888 ether;
        loan.borrower = address(0x1234567890123456789012345678901234567890);

        _mockLOAN(loanId, loan);
        storedLoan = loanContract.getLOAN(loanId);
        _assertLOANEq(storedLoan, loan);
    }

    function test_shouldReturnEmptyLOAN_whenLoanDoesNotExist() external {
        PWNLoan.LOAN memory storedLoan = loanContract.getLOAN(loanId + 1);
        _assertLOANEq(storedLoan, nonExistingLoan);
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN STATUS                                       *|
|*----------------------------------------------------------*/

contract PWNLoan_GetLOANStatus_Test is PWNLoanTest {

    function test_shouldReturnLoanStatus() external {
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.DEAD); // Non-existing loan

        _mockLOAN(loanId, loan);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.RUNNING); // Running loan

        _mockIsDefaulted(loanId, true);
        loan.principal = 5;
        _mockLOAN(loanId, loan);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.DEFAULTED); // Defaulted loan

        loan.principal = 0;
        loan.unclaimedRepayment = 1;
        _mockLOAN(loanId, loan);
        assertEq(loanContract.getLOANStatus(loanId), LOANStatus.REPAID); // Repaid loan (even if default module returns true)
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN DEBT                                         *|
|*----------------------------------------------------------*/

contract PWNLoan_GetLOANDebt_Test is PWNLoanTest {

    function test_shouldReturnLoanDebt() external {
        loan.principal = 100 ether;
        loan.unclaimedRepayment = 10 ether; // should be ignored
        loan.pastAccruedInterest = 5 ether;
        _mockLOAN(loanId, loan);
        _mockInterest(loanId, 7 ether);

        assertEq(loanContract.getLOANDebt(loanId), 112 ether); // principal + pastAccruedInterest + newly accrued interest
    }

}


/*----------------------------------------------------------*|
|*  # LENDER SPEC HASH                                      *|
|*----------------------------------------------------------*/

contract PWNLoan_GetLenderSpecHash_Test is PWNLoanTest {

    function test_shouldReturnLenderSpecHash() external {
        lenderSpec.createHookData = "createHookData";
        lenderSpec.repaymentHookData = "repaymentHookData";
        assertEq(keccak256(abi.encode(lenderSpec)), loanContract.getLenderSpecHash(lenderSpec));
    }

    function test_shouldReturnZero_whenLenderSpecIsEmpty() external {
        PWNLoan.LenderSpec memory emptyLenderSpec;
        assertEq(loanContract.getLenderSpecHash(emptyLenderSpec), bytes32(0));
    }

}


/*----------------------------------------------------------*|
|*  # BORROWER SPEC HASH                                    *|
|*----------------------------------------------------------*/

contract PWNLoan_GetBorrowerSpecHash_Test is PWNLoanTest {

    function test_shouldReturnBorrowerSpecHash() external {
        borrowerSpec.createHookData = "createHookData";
        assertEq(keccak256(abi.encode(borrowerSpec)), loanContract.getBorrowerSpecHash(borrowerSpec));
    }

    function test_shouldReturnZero_whenBorrowerSpecIsEmpty() external {
        PWNLoan.BorrowerSpec memory emptyBorrowerSpec;
        assertEq(loanContract.getBorrowerSpecHash(emptyBorrowerSpec), bytes32(0));
    }

}


/*----------------------------------------------------------*|
|*  # UPDATE LENDER REPAYMENT HOOK                          *|
|*----------------------------------------------------------*/

contract PWNLoan_UpdateLenderRepaymentHook_Test is PWNLoanTest {

    function test_shouldFail_whenNewHookIsNotTagged() external {
        _mockHubTag(address(lenderRepaymentHook), PWNHubTags.HOOK, false);

        vm.expectRevert(abi.encodeWithSelector(PWNLoan.AddressMissingHubTag.selector, lenderRepaymentHook, PWNHubTags.HOOK));
        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "new repayment hook data");
    }

    function test_shouldUpdateLenderRepaymentHook() external {
        _mockHubTag(address(lenderRepaymentHook), PWNHubTags.HOOK);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, lenderRepaymentHook, "new repayment hook data");

        (IPWNLenderRepaymentHook hook, bytes memory data) = loanContract.lenderRepaymentHook(lender, loanId);
        assertEq(address(hook), address(lenderRepaymentHook));
        assertEq(keccak256(data), keccak256("new repayment hook data"));

        // Rewrite to new hook
        IPWNLenderRepaymentHook newHook = IPWNLenderRepaymentHook(makeAddr("newHook"));
        _mockHubTag(address(newHook), PWNHubTags.HOOK);

        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, newHook, "");

        (hook, data) = loanContract.lenderRepaymentHook(lender, loanId);
        assertEq(address(hook), address(newHook));
        assertEq(keccak256(data), keccak256(""));

        // Remove hook
        vm.prank(lender);
        loanContract.updateLenderRepaymentHook(loanId, IPWNLenderRepaymentHook(address(0)), "");

        (hook, data) = loanContract.lenderRepaymentHook(lender, loanId);
        assertEq(address(hook), address(0));
        assertEq(keccak256(data), keccak256(""));
    }

}


/*----------------------------------------------------------*|
|*  # LOAN METADATA URI                                     *|
|*----------------------------------------------------------*/

contract PWNLoan_LoanMetadataUri_Test is PWNLoanTest {

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
            abi.encodeWithSignature("loanMetadataUri(address)", loanContract)
        );

        loanContract.loanMetadataUri();
    }

    function test_shouldReturnCorrectValue() external {
        string memory _tokenUri = loanContract.loanMetadataUri();

        assertEq(tokenUri, _tokenUri);
    }

}


/*----------------------------------------------------------*|
|*  # ERC5646                                               *|
|*----------------------------------------------------------*/

contract PWNLoan_GetStateFingerprint_Test is PWNLoanTest {

    function test_shouldReturnZeroIfLoanDoesNotExist() external {
        bytes32 fingerprint = loanContract.getStateFingerprint(loanId);

        assertEq(fingerprint, bytes32(0));
    }

    function test_shouldUpdateStateFingerprint_whenLoanDefaulted() external {
        _mockLOAN(loanId, loan);

        _mockIsDefaulted(loanId, false);
        assertEq(
            loanContract.getStateFingerprint(loanId),
            keccak256(abi.encode(2, loan.lastUpdateTimestamp, loan.pastAccruedInterest, loan.principal, loan.unclaimedRepayment))
        );

        _mockIsDefaulted(loanId, true);
        assertEq(
            loanContract.getStateFingerprint(loanId),
            keccak256(abi.encode(4, loan.lastUpdateTimestamp, loan.pastAccruedInterest, loan.principal, loan.unclaimedRepayment))
        );
    }

    function testFuzz_shouldReturnCorrectStateFingerprint(
        uint40 lastUpdateTimestamp,
        uint256 pastAccruedInterest,
        uint256 principal,
        uint256 unclaimedRepayment
    ) external {
        vm.assume(principal > 0);

        loan.lastUpdateTimestamp = lastUpdateTimestamp;
        loan.pastAccruedInterest = pastAccruedInterest;
        loan.principal = principal;
        loan.unclaimedRepayment = unclaimedRepayment;
        _mockLOAN(loanId, loan);

        assertEq(
            loanContract.getStateFingerprint(loanId),
            keccak256(abi.encode(2, loan.lastUpdateTimestamp, loan.pastAccruedInterest, loan.principal, loan.unclaimedRepayment))
        );
    }

}
