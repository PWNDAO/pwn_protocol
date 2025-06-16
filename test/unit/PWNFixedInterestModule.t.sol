// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNDefaultModule } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNFixedInterestModule,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE,
    Math
} from "pwn/periphery/loan/module/interest/PWNFixedInterestModule.sol";

using MultiToken for address;
using Math for uint256;

abstract contract PWNFixedInterestModuleTest is Test {

    PWNFixedInterestModule interestModule;
    address hub = makeAddr("hub");
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;
    PWNLoan.LOAN loan;


    function setUp() public virtual {
        interestModule = new PWNFixedInterestModule(PWNHub(hub));

        loan = PWNLoan.LOAN({
            borrower: makeAddr("borrower"),
            lastUpdateTimestamp: uint40(0),
            collateral: makeAddr("collateral").ERC721(2),
            creditAddress: makeAddr("creditAddress"),
            principal: 100 ether,
            pastAccruedInterest: 0,
            unclaimedRepayment: 0,
            interestModule: IPWNInterestModule(interestModule),
            defaultModule: IPWNDefaultModule(makeAddr("defaultModule")),
            liquidationModule: IPWNLiquidationModule(makeAddr("liquidationModule"))
        });

        _mockGetLOAN(loanId, loan);
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, true);
    }


    function _mockHubTag(address _contract, bytes32 _tag, bool _set) internal {
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", _contract, _tag), abi.encode(_set));
    }

    function _mockGetLOAN(uint256 _loanId, PWNLoan.LOAN memory _loan) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, _loanId), abi.encode(_loan));
    }

    function _mockInterestData(uint256 _loanId, uint256 _loanStart, uint256 _fixationDeadline, uint256 _apr) internal {
        vm.store(
            address(interestModule),
            keccak256(abi.encode(_loanId, keccak256(abi.encode(loanContract, 0)))),
            bytes32(_apr << 80 | _fixationDeadline << 40 | _loanStart)
            // 0x00...00AAAAAAFFFFFFFFFFFFFFFFSSSSSSSSSSSSSSSS
        );
    }

    function _dayInterest(uint256 principal, uint256 apr) internal pure returns (uint256) {
        return principal.mulDiv(apr * 1 days, 365 days * 10000);
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNFixedInterestModule_OnLoanCreated_Test is PWNFixedInterestModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNFixedInterestModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(100, 100));
    }

    function test_shouldFail_whenProposerDataIsInvalid() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNFixedInterestModule.InvalidProposerDataLength.selector);
        interestModule.onLoanCreated(loanId, abi.encode(uint256(1), uint256(1), "wrong data", "format"));
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(0, 100));

        vm.expectRevert(PWNFixedInterestModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(80, 100));
    }

    function testFuzz_shouldStoreData(uint24 apr, uint40 fixationPeriod, uint40 timestamp) external {
        vm.assume(uint256(timestamp) + uint256(fixationPeriod) <= type(uint40).max);
        vm.warp(timestamp);

        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(apr, fixationPeriod));

        (uint256 _apr, uint256 _fixationDeadline) = interestModule.interestData(loanContract, loanId);
        assertEq(apr, _apr);
        assertEq(timestamp + fixationPeriod, _fixationDeadline);
    }

    function test_shouldReturnInitHookValue() external {
        vm.prank(loanContract);
        bytes32 result = interestModule.onLoanCreated(loanId, abi.encode(100, 100));

        assertEq(result, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE);
    }

}


/*----------------------------------------------------------*|
|*  # INTEREST                                              *|
|*----------------------------------------------------------*/

contract PWNFixedInterestModule_Interest_Test is PWNFixedInterestModuleTest {

    function setUp() override public virtual {
        super.setUp();

        _mockInterestData(loanId, 0, 365 days, 100);
    }


    function test_shouldFetchLoanData() external {
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));

        interestModule.interest(loanContract, loanId);
    }

    function test_shouldReturnZero_whenLastUpdateTimestampIsInFuture() external {
        loan.lastUpdateTimestamp = uint40(block.timestamp + 1);
        _mockGetLOAN(loanId, loan);

        assertEq(interestModule.interest(loanContract, loanId), 0);
    }

    function testFuzz_shouldReturnInterest_whenLastUpdateTimestampIsEqualToLoanStart_whenBeforeFixationPeriodEnd(uint256 timestamp) external {
        vm.warp(bound(timestamp, 0, 365 days));

        _mockInterestData(loanId, 0, 365 days, 100);
        assertEq(interestModule.interest(loanContract, loanId), 1 ether);

        _mockInterestData(loanId, 0, 365 days, 1000);
        assertEq(interestModule.interest(loanContract, loanId), 10 ether);

        _mockInterestData(loanId, 0, 365 days, 10000);
        assertEq(interestModule.interest(loanContract, loanId), 100 ether);
    }

    function testFuzz_shouldReturnZero_whenLastUpdateTimestmapIsGreaterThanLoanStart_whenBeforeFixationPeriodEnd(uint256 timestamp) external {
        vm.warp(bound(timestamp, 0, 365 days));

        _mockInterestData(loanId, 1, 365 days + 1, 100);
        assertEq(interestModule.interest(loanContract, loanId), 0);
    }

    function test_shouldReturnInterest_whenLastUpdateTimestampIsEqualToLoanStart_whenAfterFixationPeriodEnd() external {
        loan.lastUpdateTimestamp = uint40(0);
        _mockGetLOAN(loanId, loan);
        _mockInterestData(loanId, 0, 365 days, 100);

        vm.warp(368 days); // +3 days

        uint256 interest = 1 ether + _dayInterest(loan.principal, 100) + _dayInterest(loan.principal, 200) + _dayInterest(loan.principal, 300);
        assertEq(interestModule.interest(loanContract, loanId), interest);
    }

    function test_shouldReturnInterest_whenLastUpdateTimestmapIsGreaterThanLoanStart_whenAfterFixationPeriodEnd() external {
        loan.lastUpdateTimestamp = uint40(1);
        _mockGetLOAN(loanId, loan);
        _mockInterestData(loanId, 0, 365 days, 100);

        vm.warp(368 days); // +3 days

        uint256 interest = _dayInterest(loan.principal, 100) + _dayInterest(loan.principal, 200) + _dayInterest(loan.principal, 300);
        assertEq(interestModule.interest(loanContract, loanId), interest);
    }

    function test_shouldReturnInterest_whenLastUpdateTimestmapIsGreaterThanFixationPeriod_whenAfterFixationPeriodEnd() external {
        loan.lastUpdateTimestamp = uint40(366 days);
        _mockGetLOAN(loanId, loan);
        _mockInterestData(loanId, 0, 365 days, 100);

        vm.warp(368 days); // +2 days

        uint256 interest = _dayInterest(loan.principal, 200) + _dayInterest(loan.principal, 300);
        assertEq(interestModule.interest(loanContract, loanId), interest);

        vm.warp(368.5 days); // +2.5 days

        interest = _dayInterest(loan.principal, 200) + _dayInterest(loan.principal, 300) + _dayInterest(loan.principal, 400) / 2;
        assertEq(interestModule.interest(loanContract, loanId), interest);
    }

}
