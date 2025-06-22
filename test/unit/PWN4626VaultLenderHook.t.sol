// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWN4626VaultLenderHook,
    IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE,
    IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE,
    IERC4626Like, PWNHub, PWNHubTags
} from "pwn/periphery/loan/hook/lender/PWN4626VaultLenderHook.sol";


abstract contract PWN4626VaultLenderHookTest is Test {

    PWN4626VaultLenderHook hook;
    address loanContract = makeAddr("loanContract");
    address lender = makeAddr("lender");
    address creditAddress = makeAddr("creditAddress");
    address vault = makeAddr("vault");
    address hub = makeAddr("hub");


    function setUp() public virtual {
        hook = new PWN4626VaultLenderHook(PWNHub(hub));

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
        vm.mockCall(vault, abi.encodeWithSelector(IERC4626Like.asset.selector), abi.encode(creditAddress));
        vm.mockCall(vault, abi.encodeWithSelector(IERC4626Like.deposit.selector), abi.encode(""));
        vm.mockCall(vault, abi.encodeWithSelector(IERC4626Like.withdraw.selector), abi.encode(""));
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

contract PWN4626VaultLenderHook_OnLoanCreated_Test is PWN4626VaultLenderHookTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWN4626VaultLenderHook.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, abi.encode(vault));
    }

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWN4626VaultLenderHook.LenderZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(address(0), creditAddress, 1, abi.encode(vault));

        vm.expectRevert(PWN4626VaultLenderHook.CreditZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, address(0), 1, abi.encode(vault));

        vm.expectRevert(PWN4626VaultLenderHook.PrincipalZero.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 0, abi.encode(vault));

        vm.expectRevert(PWN4626VaultLenderHook.InvalidLenderDataLength.selector);
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, abi.encode(vault, 1));
    }

    function test_shouldFail_whenVaultAssetDoesNotMatchCreditAsset() external {
        address diffAsset = makeAddr("diffAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC4626Like.asset.selector), abi.encode(diffAsset));

        vm.expectRevert(abi.encodeWithSelector(PWN4626VaultLenderHook.InvalidVaultAsset.selector, creditAddress, diffAsset));
        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, 1, abi.encode(vault));
    }

    function testFuzz_shouldWithdrawFromVault(uint256 principal) external {
        principal = bound(principal, 1, type(uint256).max);

        vm.expectCall(vault, abi.encodeWithSelector(IERC4626Like.withdraw.selector, principal, lender, lender));

        vm.prank(loanContract);
        hook.onLoanCreated(lender, creditAddress, principal, abi.encode(vault));
    }

    function test_shouldReturnHookValue() external {
        vm.prank(loanContract);
        assertEq(
            hook.onLoanCreated(lender, creditAddress, 1, abi.encode(vault)),
            LENDER_CREATE_HOOK_RETURN_VALUE
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN REPAID                                        *|
|*----------------------------------------------------------*/

contract PWN4626VaultLenderHook_OnLoanRepaid_Test is PWN4626VaultLenderHookTest {

    function test_shouldFail_whenMissingInputs() external {
        vm.expectRevert(PWN4626VaultLenderHook.LenderZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(address(0), creditAddress, 1, abi.encode(vault));

        vm.expectRevert(PWN4626VaultLenderHook.CreditZeroAddress.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, address(0), 1, abi.encode(vault));

        vm.expectRevert(PWN4626VaultLenderHook.RepaymentZero.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, 0, abi.encode(vault));

        vm.expectRevert(PWN4626VaultLenderHook.InvalidLenderDataLength.selector);
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, 1, abi.encode(vault, 1));
    }

    function test_shouldFail_whenVaultAssetDoesNotMatchCreditAsset() external {
        address diffAsset = makeAddr("diffAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC4626Like.asset.selector), abi.encode(diffAsset));

        vm.expectRevert(abi.encodeWithSelector(PWN4626VaultLenderHook.InvalidVaultAsset.selector, creditAddress, diffAsset));
        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, 1, abi.encode(vault));
    }

    function testFuzz_shouldDepositToVault(uint256 repayment) external {
        repayment = bound(repayment, 1, type(uint256).max);

        vm.expectCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)", vault, repayment));
        vm.expectCall(vault, abi.encodeWithSelector(IERC4626Like.deposit.selector, repayment, lender));

        vm.prank(loanContract);
        hook.onLoanRepaid(lender, creditAddress, repayment, abi.encode(vault));
    }

    function test_shouldReturnHookValue() external {
        vm.prank(loanContract);
        assertEq(
            hook.onLoanRepaid(lender, creditAddress, 1, abi.encode(vault)),
            LENDER_REPAYMENT_HOOK_RETURN_VALUE
        );
    }

}
