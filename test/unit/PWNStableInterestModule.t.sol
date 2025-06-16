// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNDefaultModule } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNStableInterestModule,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE
} from "pwn/periphery/loan/module/interest/PWNStableInterestModule.sol";

using MultiToken for address;

abstract contract PWNStableInterestModuleTest is Test {

    PWNStableInterestModule interestModule;
    address hub = makeAddr("hub");
    address loanContract = makeAddr("loanContract");
    uint256 loanId = 1;
    PWNLoan.LOAN loan;


    function setUp() public virtual {
        interestModule = new PWNStableInterestModule(PWNHub(hub));

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

    function _mockInterestData(uint256 _loanId, uint24 _apr) internal {
        vm.store(
            address(interestModule),
            keccak256(abi.encode(_loanId, keccak256(abi.encode(loanContract, 0)))),
            bytes32(uint256(_apr) << 8 | 1) // 0x00...00AAAAAAII
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNStableInterestModule_OnLoanCreated_Test is PWNStableInterestModuleTest {

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        _mockHubTag(loanContract, PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(PWNStableInterestModule.CallerNotActiveLoan.selector);
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(100));
    }

    function test_shouldFail_whenProposerDataIsInvalid() external {
        vm.prank(loanContract);
        vm.expectRevert(PWNStableInterestModule.InvalidProposerDataLength.selector);
        interestModule.onLoanCreated(loanId, abi.encode(uint256(1), uint256(1), "wrong data", "format"));
    }

    function test_shouldFail_whenLoanAlreadyInitialized() external {
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(0));

        vm.expectRevert(PWNStableInterestModule.LoanAlreadyInitialized.selector);
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(0));
    }

    function testFuzz_shouldStoreAPR(uint24 apr) external {
        vm.prank(loanContract);
        interestModule.onLoanCreated(loanId, abi.encode(apr));

        assertEq(interestModule.apr(loanContract, loanId), apr);
    }

    function test_shouldReturnInitHookValue() external {
        vm.prank(loanContract);
        bytes32 result = interestModule.onLoanCreated(loanId, abi.encode(100));

        assertEq(result, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE);
    }

}


/*----------------------------------------------------------*|
|*  # INTEREST                                              *|
|*----------------------------------------------------------*/

contract PWNStableInterestModule_Interest_Test is PWNStableInterestModuleTest {

    function setUp() override public virtual {
        super.setUp();

        _mockInterestData(loanId, 100);
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

    function test_shouldCalculateInterest() external {
        loan.pastAccruedInterest = 46 ether; // should be ignored
        loan.principal = 100 ether;
        loan.lastUpdateTimestamp = uint40(0);
        _mockGetLOAN(loanId, loan);

        vm.warp(0);

        _mockInterestData(loanId, 100); // 1%
        assertEq(interestModule.interest(loanContract, loanId), 0);

        _mockInterestData(loanId, 1000); // 10%
        assertEq(interestModule.interest(loanContract, loanId), 0);

        _mockInterestData(loanId, 10000); // 100%
        assertEq(interestModule.interest(loanContract, loanId), 0);

        vm.warp(182.5 days);

        _mockInterestData(loanId, 100); // 1%
        assertEq(interestModule.interest(loanContract, loanId), 0.5 ether);

        _mockInterestData(loanId, 1000); // 10%
        assertEq(interestModule.interest(loanContract, loanId), 5 ether);

        _mockInterestData(loanId, 10000); // 100%
        assertEq(interestModule.interest(loanContract, loanId), 50 ether);

        vm.warp(365 days);

        _mockInterestData(loanId, 100); // 1%
        assertEq(interestModule.interest(loanContract, loanId), 1 ether);

        _mockInterestData(loanId, 1000); // 10%
        assertEq(interestModule.interest(loanContract, loanId), 10 ether);

        _mockInterestData(loanId, 10000); // 100%
        assertEq(interestModule.interest(loanContract, loanId), 100 ether);
    }

}


/*----------------------------------------------------------*|
|*  # APR                                                   *|
|*----------------------------------------------------------*/

contract PWNStableInterestModule_Apr_Test is PWNStableInterestModuleTest {

    function test_shouldReturnStoredApr(uint24 apr) external {
        _mockInterestData(loanId, apr);

        assertEq(interestModule.apr(loanContract, loanId), apr);
    }

}
