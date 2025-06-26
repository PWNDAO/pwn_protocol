// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";

import { PWNOpenLiquidationModule } from "pwn/periphery/loan/module/liquidation/PWNOpenLiquidationModule.sol";

import {
    MultiToken,
    BaseIntegrationTest,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    PWNSimpleProposal
} from "test/integration/BaseIntegrationTest.t.sol";


contract PWNOpenLiquidationIntegrationTest is BaseIntegrationTest {

    PWNOpenLiquidationModule liquidationModule = new PWNOpenLiquidationModule();
    address liquidator = makeAddr("liquidator");

    function setUp() override virtual public {
        super.setUp();

        __d.simpleProposal = new PWNSimpleProposal(
            address(__d.hub),
            address(__d.revokedNonce),
            address(__d.config),
            address(__d.utilizedCredit),
            address(__d.stableInterestModule),
            address(__d.durationDefaultModule),
            address(liquidationModule)
        );

        vm.startPrank(__e.protocolTimelock);
        __d.hub.setTag(address(liquidationModule), PWNHubTags.MODULE, true);
        __d.hub.setTag(address(__d.simpleProposal), PWNHubTags.LOAN_PROPOSAL, true);
        __d.hub.setTag(address(__d.simpleProposal), PWNHubTags.NONCE_MANAGER, true);
        vm.stopPrank();

        credit.mint(liquidator, simpleProposal.creditAmount);

        vm.prank(liquidator);
        credit.approve(address(liquidationModule), type(uint256).max);
    }

    function test_shouldLiquidateDefaultedLoan() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        assertEq(t1155.balanceOf(liquidator, simpleProposal.collateralId), 0);
        assertEq(t1155.balanceOf(address(__d.loan), simpleProposal.collateralId), simpleProposal.collateralAmount);
        assertEq(credit.balanceOf(liquidator), simpleProposal.creditAmount);
        assertEq(credit.balanceOf(lender), 0);

        // Default the LOAN
        vm.warp(block.timestamp + 2 days);

        // Liquidate the LOAN
        vm.prank(liquidator);
        __d.loan.liquidate(loanId, "");

        // Claim the liquidation
        vm.prank(lender);
        __d.loan.claimRepayment(loanId);

        assertEq(t1155.balanceOf(liquidator, simpleProposal.collateralId), simpleProposal.collateralAmount);
        assertEq(t1155.balanceOf(address(__d.loan), simpleProposal.collateralId), 0);
        assertEq(credit.balanceOf(liquidator), 0);
        assertEq(credit.balanceOf(lender), simpleProposal.creditAmount);
    }

}
