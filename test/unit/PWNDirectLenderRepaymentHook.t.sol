// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNDirectLenderRepaymentHook,
    IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE
} from "pwn/periphery/hook/lender/PWNDirectLenderRepaymentHook.sol";


abstract contract PWNDirectLenderRepaymentHookTest is Test {

    PWNDirectLenderRepaymentHook hook;
    address lender = makeAddr("lender");
    address creditAddress = makeAddr("creditAddress");


    function setUp() public virtual {
        hook = new PWNDirectLenderRepaymentHook();

        vm.mockCall(creditAddress, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN REPAID                                        *|
|*----------------------------------------------------------*/

contract PWNDirectLenderRepaymentHook_OnLoanRepaid_Test is PWNDirectLenderRepaymentHookTest {

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWNDirectLenderRepaymentHook.LenderZeroAddress.selector);
        hook.onLoanRepaid(address(0), creditAddress, 1, "");

        vm.expectRevert(PWNDirectLenderRepaymentHook.CreditZeroAddress.selector);
        hook.onLoanRepaid(lender, address(0), 1, "");

        vm.expectRevert(PWNDirectLenderRepaymentHook.RepaymentZero.selector);
        hook.onLoanRepaid(lender, creditAddress, 0, "");

        vm.expectRevert(PWNDirectLenderRepaymentHook.DataNotEmpty.selector);
        hook.onLoanRepaid(lender, creditAddress, 1, abi.encode(1));
    }

    function testFuzz_shouldTransferToLender(uint256 repayment) external {
        repayment = bound(repayment, 1, type(uint256).max);

        vm.expectCall(creditAddress, abi.encodeWithSignature("transfer(address,uint256)", lender, repayment));

        hook.onLoanRepaid(lender, creditAddress, repayment, "");
    }

    function test_shouldReturnHookValue() external {
        assertEq(
            hook.onLoanRepaid(lender, creditAddress, 1, ""),
            LENDER_REPAYMENT_HOOK_RETURN_VALUE
        );
    }

}
