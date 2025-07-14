// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNAaveLenderHook,
    IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE,
    IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE,
    IAaveLike, PWNHub, PWNHubTags
} from "pwn/periphery/hook/lender/PWNAaveLenderHook.sol";


abstract contract PWNAaveLenderHookTest is Test {

    PWNAaveLenderHook hook;
    address loanContract = makeAddr("loanContract");
    address lender = makeAddr("lender");
    address creditAddress = makeAddr("creditAddress");
    address aToken = makeAddr("aToken");
    address pool = makeAddr("pool");
    address hub = makeAddr("hub");
    IAaveLike.ReserveData reserveData;


    function setUp() public virtual {
        hook = new PWNAaveLenderHook(PWNHub(hub), IAaveLike(pool));

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
        vm.mockCall(pool, abi.encodeWithSelector(IAaveLike.supply.selector), abi.encode(""));
        vm.mockCall(pool, abi.encodeWithSelector(IAaveLike.withdraw.selector), abi.encode(0)); // not using the return value
        _mockHealthFactor(1.5e18);
        vm.mockCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(creditAddress, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));
        vm.mockCall(aToken, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));

        reserveData.aTokenAddress = aToken;
        vm.mockCall(pool, abi.encodeWithSelector(IAaveLike.getReserveData.selector), abi.encode(reserveData));
    }


    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

    function _mockHealthFactor(uint256 healthFactor) internal {
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IAaveLike.getUserAccountData.selector, lender),
            abi.encode(0, 0, 0, 0, 0, healthFactor)
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNAaveLenderHook_OnLoanCreated_Test is PWNAaveLenderHookTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNAaveLenderHook.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, "");
    }

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWNAaveLenderHook.LenderZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(address(0), creditAddress, 1, "");

        vm.expectRevert(PWNAaveLenderHook.CreditZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, address(0), 1, "");

        vm.expectRevert(PWNAaveLenderHook.PrincipalZero.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 0, "");

        vm.expectRevert(PWNAaveLenderHook.DataNotEmpty.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, abi.encode(1));
    }

    function testFuzz_shouldTranseferATokensFromLender(uint256 principal) external {
        principal = bound(principal, 1, type(uint256).max);

        vm.expectCall(aToken, abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, address(hook), principal));

        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, principal, "");
    }

    function testFuzz_shouldFail_whenHealthFactorIsBelowMin(uint256 healthFactor) external {
        healthFactor = bound(healthFactor, 0, hook.MIN_HEALTH_FACTOR() - 1);
        _mockHealthFactor(healthFactor);

        vm.expectRevert(
            abi.encodeWithSelector(PWNAaveLenderHook.HealthFactorBelowMin.selector, healthFactor, hook.MIN_HEALTH_FACTOR())
        );
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, "");
    }

    function testFuzz_shouldWithdrawFromPool(uint256 principal) external {
        principal = bound(principal, 1, type(uint256).max);

        vm.expectCall(pool, abi.encodeWithSelector(IAaveLike.withdraw.selector, creditAddress, principal, lender));

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

contract PWNAaveLenderHook_OnLoanRepaid_Test is PWNAaveLenderHookTest {

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWNAaveLenderHook.LenderZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(address(0), creditAddress, 1, "");

        vm.expectRevert(PWNAaveLenderHook.CreditZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, address(0), 1, "");

        vm.expectRevert(PWNAaveLenderHook.RepaymentZero.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, 0, "");

        vm.expectRevert(PWNAaveLenderHook.DataNotEmpty.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, 1, abi.encode(1));
    }

    function testFuzz_shouldSupplyToPool(uint256 repayment) external {
        repayment = bound(repayment, 1, type(uint256).max);

        vm.expectCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)", pool, repayment));
        vm.expectCall(pool, abi.encodeWithSelector(IAaveLike.supply.selector, creditAddress, repayment, lender, 0));

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
