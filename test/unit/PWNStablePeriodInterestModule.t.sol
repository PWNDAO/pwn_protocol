// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNDefaultModule } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNStablePeriodInterestModule,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE,
    Math
} from "pwn/periphery/loan/module/interest/PWNStablePeriodInterestModule.sol";

using MultiToken for address;
using Math for uint256;

abstract contract PWNStablePeriodInterestModuleTest is Test {

    PWNStablePeriodInterestModule interestModule;
    address hub = makeAddr("hub");
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;
    PWNLoan.LOAN loan;


    function setUp() public virtual {
        interestModule = new PWNStablePeriodInterestModule(PWNHub(hub));

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

    function _mockInterestData(uint256 _loanId, uint256 _stableDeadline, uint256 _apr) internal {
        vm.store(
            address(interestModule),
            keccak256(abi.encode(_loanId, keccak256(abi.encode(loanContract, 0)))),
            bytes32(_apr << 40 | _stableDeadline)
            // 0x00...00AAAAAAFFFFFFFFFFFFFFFF
        );
    }

    function _dayInterest(uint256 principal, uint256 apr) internal pure returns (uint256) {
        return principal.mulDiv(apr * 1 days, 365 days * 10000);
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNStablePeriodInterestModule_OnLoanCreated_Test is PWNStablePeriodInterestModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNStablePeriodInterestModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(100, 100));
    }

    function test_shouldFail_whenProposerDataIsInvalid() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNStablePeriodInterestModule.InvalidProposerDataLength.selector);
        interestModule.onLoanCreated(loanId, abi.encode(uint256(1), uint256(1), "wrong data", "format"));
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(0, 100));

        vm.expectRevert(PWNStablePeriodInterestModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(80, 100));
    }

    function testFuzz_shouldStoreData(uint24 apr, uint40 stablePeriod, uint40 timestamp) external {
        vm.assume(uint256(timestamp) + uint256(stablePeriod) <= type(uint40).max);
        vm.warp(timestamp);

        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(apr, stablePeriod));

        (uint256 _apr, uint256 _stableDeadline) = interestModule.interestData(loanContract, loanId);
        assertEq(apr, _apr);
        assertEq(timestamp + stablePeriod, _stableDeadline);
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

contract PWNStablePeriodInterestModule_Interest_Test is PWNStablePeriodInterestModuleTest {

    function setUp() override public virtual {
        super.setUp();

        _mockInterestData(loanId, 365 days, 100);
    }


    function test_shouldFetchLoanData() external {
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector, loanId));

        interestModule.interest(loanContract, loanId);
    }

    function test_shouldReturnZero_whenLastUpdateTimestampIsEqualOrMoreThanNow(uint256 timestamp) external {
        loan.lastUpdateTimestamp = uint40(bound(timestamp, block.timestamp, 1e7));
        _mockGetLOAN(loanId, loan);

        assertEq(interestModule.interest(loanContract, loanId), 0);
    }

    function test_shouldReturnStableInterestWithoutPenalty_whenBeforeStablePeriodEnd() external {
        loan.pastAccruedInterest = 46 ether; // should be ignored
        loan.principal = 100 ether;
        loan.lastUpdateTimestamp = uint40(0);
        _mockGetLOAN(loanId, loan);

        vm.warp(0);

        _mockInterestData(loanId, 365 days, 100); // 1%
        assertEq(interestModule.interest(loanContract, loanId), 0);

        _mockInterestData(loanId, 365 days, 1000); // 10%
        assertEq(interestModule.interest(loanContract, loanId), 0);

        _mockInterestData(loanId, 365 days, 10000); // 100%
        assertEq(interestModule.interest(loanContract, loanId), 0);

        vm.warp(182.5 days);

        _mockInterestData(loanId, 365 days, 100); // 1%
        assertEq(interestModule.interest(loanContract, loanId), 0.5 ether);

        _mockInterestData(loanId, 365 days, 1000); // 10%
        assertEq(interestModule.interest(loanContract, loanId), 5 ether);

        _mockInterestData(loanId, 365 days, 10000); // 100%
        assertEq(interestModule.interest(loanContract, loanId), 50 ether);

        vm.warp(365 days);

        _mockInterestData(loanId, 365 days, 100); // 1%
        assertEq(interestModule.interest(loanContract, loanId), 1 ether);

        _mockInterestData(loanId, 365 days, 1000); // 10%
        assertEq(interestModule.interest(loanContract, loanId), 10 ether);

        _mockInterestData(loanId, 365 days, 10000); // 100%
        assertEq(interestModule.interest(loanContract, loanId), 100 ether);
    }

    function test_shouldReturnStableInterestWithPenalty_whenAfterStablePeriodEnd() external {
        loan.principal = 100 ether;
        loan.lastUpdateTimestamp = uint40(0);
        _mockGetLOAN(loanId, loan);

        vm.warp(6 days);

        _mockInterestData(loanId, 1 days, 100); // 1%
        assertEq(
            interestModule.interest(loanContract, loanId),
            _dayInterest(loan.principal, 100)
                + _dayInterest(loan.principal, 100)
                + _dayInterest(loan.principal, 200)
                + _dayInterest(loan.principal, 300)
                + _dayInterest(loan.principal, 400)
                + _dayInterest(loan.principal, 500)
        );

        _mockInterestData(loanId, 1 days, 1000); // 10%
        assertEq(
            interestModule.interest(loanContract, loanId),
            _dayInterest(loan.principal, 1000)
                + _dayInterest(loan.principal, 1000)
                + _dayInterest(loan.principal, 1100)
                + _dayInterest(loan.principal, 1200)
                + _dayInterest(loan.principal, 1300)
                + _dayInterest(loan.principal, 1400)
        );

        loan.lastUpdateTimestamp = uint40(1 days / 2);
        _mockGetLOAN(loanId, loan);

        _mockInterestData(loanId, 1 days, 10000); // 100%
        assertEq(
            interestModule.interest(loanContract, loanId),
            _dayInterest(loan.principal, 10000) / 2
                + _dayInterest(loan.principal, 10000)
                + _dayInterest(loan.principal, 10100)
                + _dayInterest(loan.principal, 10200)
                + _dayInterest(loan.principal, 10300)
                + _dayInterest(loan.principal, 10400)
        );
    }

    function test_shouldReturnOnlyPenalty_whenAfterStablePeriodEnd_whenLastUpdateAfterPeriodEnd() external {
        loan.principal = 100 ether;
        loan.lastUpdateTimestamp = 2 days;
        _mockGetLOAN(loanId, loan);

        vm.warp(6 days);

        _mockInterestData(loanId, 1 days, 1000); // 10%
        assertEq(
            interestModule.interest(loanContract, loanId),
            _dayInterest(loan.principal, 1100)
            + _dayInterest(loan.principal, 1200)
            + _dayInterest(loan.principal, 1300)
            + _dayInterest(loan.principal, 1400)
        );

        loan.lastUpdateTimestamp = 2.25 days;
        _mockGetLOAN(loanId, loan);

        vm.warp(5.8 days);

        _mockInterestData(loanId, 1 days, 1000); // 10%
        assertApproxEqRel(
            interestModule.interest(loanContract, loanId),
            _dayInterest(loan.principal, 1100) * 3 / 4
            + _dayInterest(loan.principal, 1200)
            + _dayInterest(loan.principal, 1300)
            + _dayInterest(loan.principal, 1400) * 8 / 10,
            0.0001e18 // 0.01% relative error
        );
    }

}
