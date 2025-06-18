// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNInterestModule } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNLinearDebtLimitDefaultModule,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    SafeCast,
    IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE
} from "pwn/periphery/loan/module/default/PWNLinearDebtLimitDefaultModule.sol";

using MultiToken for address;

abstract contract PWNLinearDebtLimitDefaultModuleTest is Test {

    PWNLinearDebtLimitDefaultModule defaultModule;
    address hub = makeAddr("hub");
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;


    function setUp() public virtual {
        defaultModule = new PWNLinearDebtLimitDefaultModule(PWNHub(hub));

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
        _mockLOANDebt(loanId, 100 ether);
    }


    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

    function _mockDefaultData(uint256 _loanId, uint256 _defaultTimestamp, uint216 _debtLimitTangent) internal {
        vm.store(
            address(defaultModule),
            keccak256(abi.encode(_loanId, keccak256(abi.encode(loanContract, 0)))),
            bytes32(uint256(_debtLimitTangent) << 40 | uint256(uint40(_defaultTimestamp)))
        );
    }

    function _mockLOANDebt(uint256 _loanId, uint256 _debt) internal {
        vm.mockCall(
            loanContract,
            abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, _loanId),
            abi.encode(_debt)
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNLinearDebtLimitDefaultModule_OnLoanCreated_Test is PWNLinearDebtLimitDefaultModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNLinearDebtLimitDefaultModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days, 10 days));
    }

    function test_shouldFail_whenProposerDataIsInvalid() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNLinearDebtLimitDefaultModule.InvalidProposerDataLength.selector);
        defaultModule.onLoanCreated(loanId, abi.encode(uint256(1), uint256(1), "wrong data", "format"));
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days, 10 days));

        vm.expectRevert(PWNLinearDebtLimitDefaultModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days, 10 days));
    }

    function testFuzz_shouldFail_whenDurationTooShort(uint256 duration) external {
        duration = bound(duration, 0, defaultModule.MIN_DURATION() - 1);

        vm.prank(loanContract);
        vm.expectRevert(PWNLinearDebtLimitDefaultModule.DurationTooShort.selector);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days, duration));
    }

    function testFuzz_shouldFail_whenPostponementBiggerThanDuration(uint256 postponement, uint256 duration) external {
        duration = bound(duration, defaultModule.MIN_DURATION(), type(uint256).max);
        postponement = bound(postponement, duration, type(uint256).max);

        vm.prank(loanContract);
        vm.expectRevert(PWNLinearDebtLimitDefaultModule.PostponementBiggerThanDuration.selector);
        defaultModule.onLoanCreated(loanId, abi.encode(postponement, duration));
    }

    function test_shouldFetchCurrentDebt() external {
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector, loanId));

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days, 10 days));
    }

    function testFuzz_shouldStoreDefaultDate(uint256 duration) external {
        duration = bound(duration, defaultModule.MIN_DURATION(), type(uint40).max - 100 days);

        vm.warp(100 days);

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(0, duration));

        (uint40 defaultTimestamp, ) = defaultModule.defaultData(loanContract, loanId);
        assertEq(uint256(defaultTimestamp), 100 days + duration);
    }

    function testFuzz_shouldStoreDebtLimitTangent(uint256 duration) external {
        duration = bound(duration, 1 days + 1, type(uint40).max);
        _mockLOANDebt(loanId, 100 ether);
        vm.warp(0);

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days, duration));

        ( , uint216 debtLimitTangent) = defaultModule.defaultData(loanContract, loanId);
        assertEq(uint256(debtLimitTangent), 100 ether * 10 ** defaultModule.DEBT_LIMIT_TANGENT_DECIMALS() / (duration - 1 days));
    }

    function test_shouldReturnInitHookValue() external {
        vm.prank(loanContract);
        bytes32 result = defaultModule.onLoanCreated(loanId, abi.encode(1 days, 10 days));

        assertEq(result, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE);
    }

}


/*----------------------------------------------------------*|
|*  # IS DEFAULTED                                          *|
|*----------------------------------------------------------*/

contract PWNLinearDebtLimitDefaultModule_IsDefaulted_Test is PWNLinearDebtLimitDefaultModuleTest {

    function testFuzz_shouldReturnTrue_whenDefaultTimestampInThePast(uint256 timestamp) external {
        _mockDefaultData(loanId, 100 days, 1e8);
        vm.warp(bound(timestamp, 100 days, type(uint256).max));

        assertTrue(defaultModule.isDefaulted(loanContract, loanId));
    }

    function test_shouldReturnTrue_whenDebtExceedsLimit() external {
        _mockDefaultData(loanId, 100_000, 1e8);

        vm.warp(1_000);

        _mockLOANDebt(loanId, 99_000);
        assertTrue(defaultModule.isDefaulted(loanContract, loanId));

        _mockLOANDebt(loanId, 99_000 - 1);
        assertFalse(defaultModule.isDefaulted(loanContract, loanId));

        vm.warp(30_000);

        _mockLOANDebt(loanId, 70_000);
        assertTrue(defaultModule.isDefaulted(loanContract, loanId));

        _mockLOANDebt(loanId, 70_000 - 1);
        assertFalse(defaultModule.isDefaulted(loanContract, loanId));

        vm.warp(80_000);

        _mockLOANDebt(loanId, 20_000);
        assertTrue(defaultModule.isDefaulted(loanContract, loanId));

        _mockLOANDebt(loanId, 20_000 - 1);
        assertFalse(defaultModule.isDefaulted(loanContract, loanId));

        vm.warp(95_000);

        _mockLOANDebt(loanId, 5_000);
        assertTrue(defaultModule.isDefaulted(loanContract, loanId));

        _mockLOANDebt(loanId, 5_000 - 1);
        assertFalse(defaultModule.isDefaulted(loanContract, loanId));
    }

}


/*----------------------------------------------------------*|
|*  # DEBT LIMIT                                            *|
|*----------------------------------------------------------*/

contract PWNLinearDebtLimitDefaultModule_DebtLimit_Test is PWNLinearDebtLimitDefaultModuleTest {

    function test_shouldReturnZero_whenDefaultTimestampInThePast() external {
        _mockDefaultData(loanId, 100 days, 1e8);
        vm.warp(101 days);

        assertEq(defaultModule.debtLimit(loanContract, loanId), 0);
    }

    function test_shouldReturnZero_whenDefaultDataNotSet() external {
        assertEq(defaultModule.debtLimit(loanContract, loanId), 0);
    }

    function test_shouldReturnCorrectDebtLimit() external {
        _mockDefaultData(loanId, 100 days, uint216(uint256(100 ether) * 1e8 / 100 days));

        vm.warp(1 days);
        assertApproxEqAbs(defaultModule.debtLimit(loanContract, loanId), 99 ether, 1);

        vm.warp(20 days);
        assertApproxEqAbs(defaultModule.debtLimit(loanContract, loanId), 80 ether, 1);

        vm.warp(74 days);
        assertApproxEqAbs(defaultModule.debtLimit(loanContract, loanId), 26 ether, 1);

        vm.warp(99 days);
        assertApproxEqAbs(defaultModule.debtLimit(loanContract, loanId), 1 ether, 1);
    }

}
