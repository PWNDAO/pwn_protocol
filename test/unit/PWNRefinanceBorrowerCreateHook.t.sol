// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNLoan, IPWNProduct } from "pwn/core/loan/PWNLoan.sol";
import {
    PWNRefinanceBorrowerCreateHook,
    IPWNBorrowerCreateHook, BORROWER_CREATE_HOOK_RETURN_VALUE,
    PWNHub, PWNHubTags
} from "pwn/periphery/hook/borrower/PWNRefinanceBorrowerCreateHook.sol";

using MultiToken for address;

abstract contract PWNRefinanceBorrowerCreateHookTest is Test {

    PWNRefinanceBorrowerCreateHook hook;
    address loanContract = makeAddr("loanContract");
    address borrower = makeAddr("borrower");
    address creditAddress = makeAddr("creditAddress");
    address hub = makeAddr("hub");
    MultiToken.Asset collateral;
    uint256 refinancingId = 1;
    PWNLoan.LOAN loan;


    function setUp() public virtual {
        hook = new PWNRefinanceBorrowerCreateHook(PWNHub(hub));

        collateral = makeAddr("collateral").ERC20(1000);

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
        vm.mockCall(creditAddress, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));
        vm.mockCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(creditAddress, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));

        loan = PWNLoan.LOAN({
            borrower: borrower,
            lastUpdateTimestamp: uint40(0),
            collateral: collateral,
            creditAddress: creditAddress,
            principal: 1e10,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            product: IPWNProduct(makeAddr("product"))
        });

        _mockGetLOAN(refinancingId, loan);
        _mockLOANDebt(refinancingId, 1e10);
    }

    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

    function _mockGetLOAN(uint256 _loanId, PWNLoan.LOAN memory _loan) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, _loanId), abi.encode(_loan));
    }

    function _mockLOANDebt(uint256 _loanId, uint256 _debt) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, _loanId), abi.encode(_debt));
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNRefinanceBorrowerCreateHook_OnLoanCreated_Test is PWNRefinanceBorrowerCreateHookTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNRefinanceBorrowerCreateHook.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(borrower, collateral, creditAddress, 1, abi.encode(refinancingId));
    }

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWNRefinanceBorrowerCreateHook.BorrowerZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(address(0), collateral, creditAddress, 1, abi.encode(refinancingId));

        vm.expectRevert(PWNRefinanceBorrowerCreateHook.CreditZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(borrower, collateral, address(0), 1, abi.encode(refinancingId));

        vm.expectRevert(PWNRefinanceBorrowerCreateHook.PrincipalZero.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(borrower, collateral, creditAddress, 0, abi.encode(refinancingId));
    }

    function test_shouldFail_whenLoanDoesNotMatchRefinancingLoan() external {
        loan.borrower = makeAddr("anotherBorrower");
        _mockGetLOAN(refinancingId, loan);

        vm.expectRevert(abi.encodeWithSelector(PWNRefinanceBorrowerCreateHook.BorrowerMismatch.selector));
        vm.prank(loanContract);
        hook.onLoanCreated(borrower, collateral, creditAddress, 1, abi.encode(refinancingId));

        loan.borrower = borrower;
        loan.creditAddress = makeAddr("anotherCreditAddress");
        _mockGetLOAN(refinancingId, loan);

        vm.expectRevert(abi.encodeWithSelector(PWNRefinanceBorrowerCreateHook.CreditMismatch.selector));
        vm.prank(loanContract);
        hook.onLoanCreated(borrower, collateral, creditAddress, 1, abi.encode(refinancingId));

        loan.creditAddress = creditAddress;
        loan.collateral = makeAddr("anotherCollateral").ERC20(1000);
        _mockGetLOAN(refinancingId, loan);

        vm.expectRevert(abi.encodeWithSelector(PWNRefinanceBorrowerCreateHook.CollateralMismatch.selector));
        vm.prank(loanContract);
        hook.onLoanCreated(borrower, collateral, creditAddress, 1, abi.encode(refinancingId));
    }

    function testFuzz_shouldRepayRefinancingLoan(uint256 debt) external {
        _mockLOANDebt(refinancingId, debt);

        vm.expectCall(creditAddress, abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, address(hook), debt));
        vm.expectCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)", loanContract, debt));
        vm.expectCall(loanContract, abi.encodeWithSignature("repay(uint256,uint256)", refinancingId, 0));

        vm.prank(loanContract);
        hook.onLoanCreated(borrower, collateral, creditAddress, 1, abi.encode(refinancingId));
    }

    function test_shouldReturnHookValue() external {
        vm.prank(loanContract);
        assertEq(
            hook.onLoanCreated(borrower, collateral, creditAddress, 1, abi.encode(refinancingId)),
            BORROWER_CREATE_HOOK_RETURN_VALUE
        );
    }

}
