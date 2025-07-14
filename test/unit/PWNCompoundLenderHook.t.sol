// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNCompoundLenderHook,
    IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE,
    IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE,
    ICometLike, PWNHub, PWNHubTags
} from "pwn/periphery/hook/lender/PWNCompoundLenderHook.sol";


abstract contract PWNCompoundLenderHookTest is Test {

    PWNCompoundLenderHook hook;
    address loanContract = makeAddr("loanContract");
    address lender = makeAddr("lender");
    address creditAddress = makeAddr("creditAddress");
    address pool = makeAddr("pool");
    address hub = makeAddr("hub");


    function setUp() public virtual {
        hook = new PWNCompoundLenderHook(PWNHub(hub), ICometLike(pool));

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
        vm.mockCall(pool, abi.encodeWithSelector(ICometLike.supplyFrom.selector), abi.encode(""));
        vm.mockCall(pool, abi.encodeWithSelector(ICometLike.withdrawFrom.selector), abi.encode(""));
        vm.mockCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(creditAddress, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));
    }


    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNCompoundLenderHook_OnLoanCreated_Test is PWNCompoundLenderHookTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNCompoundLenderHook.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, "");
    }

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWNCompoundLenderHook.LenderZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(address(0), creditAddress, 1, "");

        vm.expectRevert(PWNCompoundLenderHook.CreditZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, address(0), 1, "");

        vm.expectRevert(PWNCompoundLenderHook.PrincipalZero.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 0, "");

        vm.expectRevert(PWNCompoundLenderHook.DataNotEmpty.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, abi.encode(1));
    }

    function testFuzz_shouldWithdrawFromPool(uint256 principal) external {
        principal = bound(principal, 1, type(uint256).max);

        vm.expectCall(
            pool,
            abi.encodeWithSelector(ICometLike.withdrawFrom.selector, lender, lender, creditAddress, principal)
        );

        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, principal, "");
    }

    function test_shouldReturnHookValue() external {
        vm.prank(loanContract);
        assertEq(
            hook.onLoanCreated(lender, creditAddress, 1, ""),
            LENDER_CREATE_HOOK_RETURN_VALUE
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN REPAID                                        *|
|*----------------------------------------------------------*/

contract PWNCompoundLenderHook_OnLoanRepaid_Test is PWNCompoundLenderHookTest {

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWNCompoundLenderHook.LenderZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(address(0), creditAddress, 1, "");

        vm.expectRevert(PWNCompoundLenderHook.CreditZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, address(0), 1, "");

        vm.expectRevert(PWNCompoundLenderHook.RepaymentZero.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, 0, "");

        vm.expectRevert(PWNCompoundLenderHook.DataNotEmpty.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, 1, abi.encode(1));
    }

    function testFuzz_shouldSupplyToPool(uint256 repayment) external {
        repayment = bound(repayment, 1, type(uint256).max);

        vm.expectCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)", pool, repayment));
        vm.expectCall(
            pool,
            abi.encodeWithSelector(ICometLike.supplyFrom.selector, address(hook), lender, creditAddress, repayment)
        );

        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, repayment, "");
    }

    function test_shouldReturnHookValue() external {
        vm.prank(loanContract);
        assertEq(
            hook.onLoanRepaid(lender, creditAddress, 1, ""),
            LENDER_REPAYMENT_HOOK_RETURN_VALUE
        );
    }

}
