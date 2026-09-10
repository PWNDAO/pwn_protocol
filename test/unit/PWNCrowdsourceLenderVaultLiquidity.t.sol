// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNCrowdsourceLenderVault, PWNLoan, PWNInstallmentsProduct, IAaveLike, Math
} from "pwn/periphery/crowdsource/PWNCrowdsourceLenderVault.sol";
import { PWNProposalManager } from "pwn/core/loan/PWNProposalManager.sol";
import { T20 } from "test/helper/T20.sol";


contract LiquidityCallbackToken is T20 {
    address internal callbackTarget;
    bytes internal callbackData;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    function setCallback(address target, bytes memory data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function _beforeTokenTransfer(address from, address, uint256) internal override {
        if (from == callbackTarget && callbackTarget != address(0)) {
            callbackAttempted = true;
            (callbackSucceeded,) = callbackTarget.call(callbackData);
        }
    }
}


contract PWNCrowdsourceLenderVaultLiquidity_Test is Test {
    using Math for uint256;
    PWNCrowdsourceLenderVault internal vault;
    T20 internal credit;
    T20 internal collateral;
    address internal loanContract = makeAddr("loanContract");
    address internal aave = makeAddr("aave");
    address internal borrower = makeAddr("borrower");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal debt;

    function setUp() public {
        credit = new LiquidityCallbackToken();
        collateral = new T20();
        IAaveLike.ReserveData memory reserve;
        vm.mockCall(aave, abi.encodeWithSelector(IAaveLike.getReserveData.selector), abi.encode(reserve));
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNProposalManager.makeProposalAcceptable.selector), abi.encode(bytes32(0)));
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLenderSpecHash.selector), abi.encode(bytes32(0)));
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector), abi.encode(uint8(2)));
        vm.mockCall(loanContract, abi.encodeWithSelector(bytes4(keccak256("loanLock(uint256)"))), abi.encode(false));

        PWNCrowdsourceLenderVault.Terms memory terms;
        terms.creditAddress = address(credit);
        terms.collateralAddress = address(collateral);
        vault = new PWNCrowdsourceLenderVault(
            PWNLoan(loanContract), PWNInstallmentsProduct(makeAddr("product")), IAaveLike(aave), "Vault", "VLT", terms
        );

        _deposit(alice, 25 ether);
        _deposit(bob, 75 ether);
        debt = 80 ether;
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector), abi.encode(debt));
        vm.prank(loanContract);
        vault.onLoanCreated(1, address(vault), address(credit), debt, "");
        vm.prank(loanContract);
        credit.transferFrom(address(vault), borrower, debt);
    }

    function _deposit(address lender, uint256 assets) internal {
        credit.mint(lender, assets);
        vm.startPrank(lender);
        credit.approve(address(vault), assets);
        vault.deposit(assets, lender);
        vm.stopPrank();
    }

    function _repay(uint256 assets) internal {
        debt -= assets;
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector), abi.encode(debt));
        vm.prank(borrower);
        credit.transfer(address(vault), assets);
        vault.onLoanRepaid(address(vault), address(credit), assets, "");
    }

    function test_cannotWithdrawAgainWithoutNewLiquidity() external {
        assertEq(vault.maxWithdraw(alice), 5 ether);
        vm.prank(alice);
        vault.withdraw(5 ether, alice, alice);

        assertEq(vault.maxWithdraw(alice), 0, "withdrawal must consume the allocated liquidity");
        vm.expectRevert("ERC4626: withdraw more than max");
        vm.prank(alice);
        vault.withdraw(1, alice, alice);
        assertEq(vault.maxWithdraw(bob), 15 ether, "another lender's allocation must be preserved");
    }

    function test_cannotRedeemAgainWithoutNewLiquidity() external {
        uint256 shares = vault.maxRedeem(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(vault.maxRedeem(alice), 0, "redemption must consume the allocated liquidity");
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_transferCannotRefreshWithdrawnAllowance() external {
        vm.startPrank(alice);
        vault.withdraw(vault.maxWithdraw(alice), alice, alice);
        vault.transfer(borrower, vault.balanceOf(alice));
        vm.stopPrank();

        assertEq(vault.maxWithdraw(borrower), 0, "a new owner must not reclaim spent liquidity");
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_withdrawAndRedeemConsumeTheSameAllowance() external {
        vm.startPrank(alice);
        vault.withdraw(2 ether, alice, alice);
        vault.redeem(vault.maxRedeem(alice), alice, alice);
        vm.stopPrank();

        assertEq(credit.balanceOf(alice), 5 ether);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_newRepaymentUsesCurrentSharesAndPreservesUnclaimedCash() external {
        vm.prank(alice);
        vault.withdraw(5 ether, alice, alice);

        // Alice now owns 20/95 shares. Only the new 19 tokens are allocated again.
        _repay(19 ether);
        assertEq(vault.maxWithdraw(alice), 4 ether);
        assertEq(vault.maxWithdraw(bob), 30 ether); // previous 15 + new 15

        vm.prank(bob);
        vault.withdraw(30 ether, bob, bob);
        assertEq(vault.maxWithdraw(alice), 4 ether);
        assertEq(vault.maxWithdraw(bob), 0);

        vm.prank(alice);
        vault.withdraw(4 ether, alice, alice);
        assertEq(credit.balanceOf(address(vault)), 0);
        assertEq(credit.balanceOf(alice) + credit.balanceOf(bob), 39 ether);
    }

    function test_multipleRepaymentsBeforeFirstWithdrawal() external {
        _repay(4 ether);
        _repay(8 ether);
        assertEq(vault.maxWithdraw(alice), 8 ether);
        assertEq(vault.maxWithdraw(bob), 24 ether);

        vm.prank(bob);
        vault.withdraw(24 ether, bob, bob);
        assertEq(vault.maxWithdraw(alice), 8 ether);
    }

    function test_directDonationAddsOnlyNewLiquidity() external {
        vm.prank(alice);
        vault.withdraw(5 ether, alice, alice);
        credit.mint(address(vault), 19 ether);

        assertEq(vault.maxWithdraw(alice), 4 ether);
        assertEq(vault.maxWithdraw(bob), 30 ether);
    }

    function test_partialTransferCarriesOnlyRemainingAllowance() external {
        vm.startPrank(alice);
        vault.withdraw(2 ether, alice, alice);
        vault.transfer(borrower, vault.balanceOf(alice) / 2);
        vm.stopPrank();

        assertEq(vault.maxWithdraw(alice), 1.5 ether);
        assertEq(vault.maxWithdraw(borrower), 1.5 ether);
        assertEq(vault.maxWithdraw(bob), 15 ether);

        vm.prank(borrower);
        vault.withdraw(1.5 ether, borrower, borrower);
        assertEq(vault.maxWithdraw(alice), 1.5 ether);
        assertEq(vault.maxWithdraw(borrower), 0);
    }

    function test_transferBeforeFirstWithdrawalAllocatesToBothOwners() external {
        vm.prank(alice);
        vault.transfer(borrower, 10 ether);

        assertEq(vault.maxWithdraw(alice), 3 ether);
        assertEq(vault.maxWithdraw(borrower), 2 ether);
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_transferFromMovesAllowanceAndDoesNotRefreshIt() external {
        vm.startPrank(alice);
        vault.withdraw(2 ether, alice, alice);
        vault.approve(borrower, vault.balanceOf(alice));
        vm.stopPrank();
        uint256 shares = vault.balanceOf(alice);
        vm.prank(borrower);
        vault.transferFrom(alice, borrower, shares);

        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxWithdraw(borrower), 3 ether);
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_delegatedWithdrawalConsumesOwnersAllowance() external {
        vm.prank(alice);
        vault.approve(borrower, 5 ether);
        vm.prank(borrower);
        vault.withdraw(5 ether, borrower, alice);

        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxWithdraw(bob), 15 ether);
        assertEq(vault.allowance(alice, borrower), 0);
    }

    function test_failedWithdrawalDoesNotConsumeAllowance() external {
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(borrower);
        vault.withdraw(5 ether, borrower, alice);

        assertEq(vault.maxWithdraw(alice), 5 ether);
        assertEq(vault.maxWithdraw(bob), 15 ether);
        assertEq(credit.balanceOf(address(vault)), 20 ether);
    }

    function test_zeroAndSelfTransfersPreserveAllowance() external {
        vm.startPrank(alice);
        vault.transfer(bob, 0);
        vault.transfer(alice, vault.balanceOf(alice));
        vault.withdraw(0, alice, alice);
        vault.redeem(0, alice, alice);
        vm.stopPrank();

        assertEq(vault.maxWithdraw(alice), 5 ether);
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_outgoingTokenCallbackCannotReallocateCash() external {
        vm.prank(alice);
        vault.approve(address(credit), type(uint256).max);
        LiquidityCallbackToken(address(credit)).setCallback(
            address(vault), abi.encodeWithSelector(vault.transferFrom.selector, alice, borrower, 1 ether)
        );

        vm.prank(alice);
        vault.withdraw(5 ether, alice, alice);

        assertTrue(LiquidityCallbackToken(address(credit)).callbackAttempted());
        assertFalse(LiquidityCallbackToken(address(credit)).callbackSucceeded());
        assertEq(vault.balanceOf(borrower), 0);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_lockedLoanCannotAllocatePrincipalDuringFunding() external {
        // Reproduce the cash balance between the create hook and principal transfer.
        credit.mint(address(vault), debt);
        vm.mockCall(loanContract, abi.encodeWithSelector(bytes4(keccak256("loanLock(uint256)"))), abi.encode(true));

        vm.expectRevert("PWNCrowdsourceLenderVault: loan context locked");
        vm.prank(alice);
        vault.transfer(borrower, 1 ether);
        vm.expectRevert("PWNCrowdsourceLenderVault: loan context locked");
        vm.prank(alice);
        vault.withdraw(1 ether, alice, alice);

        credit.burn(address(vault), debt);
        vm.mockCall(loanContract, abi.encodeWithSelector(bytes4(keccak256("loanLock(uint256)"))), abi.encode(false));
        assertEq(vault.maxWithdraw(alice), 5 ether);
        assertEq(vault.maxWithdraw(bob), 15 ether);
    }

    function test_lockedLoanCannotEndBeforeRepaymentArrives() external {
        vm.mockCall(loanContract, abi.encodeWithSelector(bytes4(keccak256("loanLock(uint256)"))), abi.encode(true));
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector), abi.encode(uint8(0)));
        uint256 shares = vault.balanceOf(alice);
        vm.expectRevert("PWNCrowdsourceLenderVault: loan context locked");
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        assertEq(vault.balanceOf(alice), 25 ether);
    }

    function test_fullRepaymentReleasesAllRemainingShares() external {
        vm.prank(alice);
        vault.withdraw(5 ether, alice, alice);
        _repay(debt);
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector), abi.encode(uint8(0)));

        vm.startPrank(alice);
        vault.redeem(vault.balanceOf(alice), alice, alice);
        vm.stopPrank();
        vm.startPrank(bob);
        vault.redeem(vault.balanceOf(bob), bob, bob);
        vm.stopPrank();

        assertEq(vault.totalSupply(), 0);
        assertEq(credit.balanceOf(address(vault)), 0);
        assertEq(credit.balanceOf(alice), 25 ether);
        assertEq(credit.balanceOf(bob), 75 ether);
    }

    function test_defaultReleasesCashAndCollateralDespiteSpentAllowance() external {
        vm.prank(alice);
        vault.withdraw(5 ether, alice, alice);
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector), abi.encode(uint8(4)));
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.liquidate.selector), "");
        collateral.mint(address(vault), 95 ether);

        vm.startPrank(alice);
        vault.redeem(vault.balanceOf(alice), alice, alice);
        vm.stopPrank();
        vm.startPrank(bob);
        vault.redeem(vault.balanceOf(bob), bob, bob);
        vm.stopPrank();

        assertEq(vault.totalSupply(), 0);
        assertLe(credit.balanceOf(address(vault)), 1);
        assertLe(collateral.balanceOf(address(vault)), 1);
        assertEq(collateral.balanceOf(alice), 20 ether);
        assertEq(collateral.balanceOf(bob), 75 ether);
    }

    function testFuzz_repeatedWithdrawalsAndTransfersCannotExceedAllocation(uint256 seed) external {
        address owner = alice;
        address receiver = makeAddr("receiver");
        for (uint256 i; i < 24; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            vm.startPrank(owner);
            if (seed % 3 == 0) {
                address nextOwner = owner == alice ? borrower : alice;
                vault.transfer(nextOwner, vault.balanceOf(owner));
                owner = nextOwner;
            } else if (seed % 3 == 1) {
                vault.withdraw(bound(seed, 0, vault.maxWithdraw(owner)), receiver, owner);
            } else {
                vault.redeem(bound(seed, 0, vault.maxRedeem(owner)), receiver, owner);
            }
            vm.stopPrank();
            assertLe(credit.balanceOf(receiver), 5 ether);
            assertEq(vault.maxWithdraw(bob), 15 ether);
        }
    }

    function testFuzz_repaymentAllowanceUsesSharesAtReceipt(uint256 repayment) external {
        repayment = bound(repayment, 1, debt - 1);
        vm.prank(alice);
        vault.withdraw(5 ether, alice, alice);
        _repay(repayment);

        uint256 aliceAllocation = repayment.mulDiv(20, 95);
        uint256 bobAllocation = Math.min(75 ether, 15 ether + repayment.mulDiv(75, 95));
        // The fixed-point accumulator rounds down by at most one asset unit at this scale.
        assertApproxEqAbs(vault.maxWithdraw(alice), aliceAllocation, 1);
        assertApproxEqAbs(vault.maxWithdraw(bob), bobAllocation, 1);
        uint256 aliceMax = vault.maxWithdraw(alice);
        vm.prank(alice);
        vault.withdraw(aliceMax, alice, alice);
        assertEq(vault.maxWithdraw(alice), 0);
        assertApproxEqAbs(vault.maxWithdraw(bob), bobAllocation, 1);
        assertLe(aliceMax + vault.maxWithdraw(bob), 15 ether + repayment);
    }
}
