// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import {
    PWNDurationDefaultModule,
    PWNHub,
    PWNHubTags,
    IPWNDefaultModule, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE
} from "pwn/periphery/loan/module/default/PWNDurationDefaultModule.sol";

using MultiToken for address;

abstract contract PWNDurationDefaultModuleTest is Test {

    PWNDurationDefaultModule defaultModule;
    address hub = makeAddr("hub");
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;


    function setUp() public virtual {
        defaultModule = new PWNDurationDefaultModule(PWNHub(hub));

        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
    }


    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

    function _mockDefaultData(uint256 _loanId, uint256 _defaultTimestamp) internal {
        vm.store(
            address(defaultModule),
            keccak256(abi.encode(_loanId, keccak256(abi.encode(loanContract, 0)))),
            bytes32(_defaultTimestamp)
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNDurationDefaultModule_OnLoanCreated_Test is PWNDurationDefaultModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNDurationDefaultModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days));
    }

    function test_shouldFail_whenProposerDataIsInvalid() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNDurationDefaultModule.InvalidProposerDataLength.selector);
        defaultModule.onLoanCreated(loanId, abi.encode(uint256(1), uint256(1), "wrong data", "format"));
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days));

        vm.expectRevert(PWNDurationDefaultModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(1 days));
    }

    function testFuzz_shouldFail_whenDurationTooShort(uint256 duration) external {
        duration = bound(duration, 0, defaultModule.MIN_DURATION() - 1);

        vm.prank(loanContract);
        vm.expectRevert(PWNDurationDefaultModule.DurationTooShort.selector);
        defaultModule.onLoanCreated(loanId, abi.encode(duration));
    }

    function testFuzz_shouldStoreData(uint256 duration) external {
        duration = bound(duration, defaultModule.MIN_DURATION(), type(uint256).max - 100 days);

        vm.warp(100 days);

        vm.prank(loanContract);
        defaultModule.onLoanCreated(loanId, abi.encode(duration));

        assertEq(defaultModule.defaultTimestamp(loanContract, loanId), 100 days + duration);
    }

    function test_shouldReturnInitHookValue() external {
        vm.prank(loanContract);
        bytes32 result = defaultModule.onLoanCreated(loanId, abi.encode(1 days));

        assertEq(result, DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE);
    }

}


/*----------------------------------------------------------*|
|*  # IS DEFAULTED                                          *|
|*----------------------------------------------------------*/

contract PWNDurationDefaultModule_IsDefaulted_Test is PWNDurationDefaultModuleTest {

    function testFuzz_shouldReturnFalse_whenDefaultTimestampInTheFuture(uint256 timestamp) external {
        _mockDefaultData(loanId, 100 days);
        vm.warp(bound(timestamp, 0, 100 days - 1));

        assertFalse(defaultModule.isDefaulted(loanContract, loanId));
    }

    function testFuzz_shouldReturnTrue_whenDefaultTimestampInThePast(uint256 timestamp) external {
        _mockDefaultData(loanId, 100 days);
        vm.warp(bound(timestamp, 100 days, type(uint256).max));

        assertTrue(defaultModule.isDefaulted(loanContract, loanId));
    }

}
