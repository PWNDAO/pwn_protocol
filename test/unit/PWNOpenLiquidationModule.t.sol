// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import {
    PWNOpenLiquidationModule,
    PWNLoan,
    IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE
} from "pwn/periphery/loan/module/liquidation/PWNOpenLiquidationModule.sol";

using MultiToken for address;

abstract contract PWNOpenLiquidationModuleTest is Test {

    PWNOpenLiquidationModule liquidationModule;
    address loanContract = makeAddr("loanContract");
    address loanToken = makeAddr("loanToken");
    address liquidator = makeAddr("liquidator");
    address creditAddress = makeAddr("creditAddress");
    MultiToken.Asset collateral = makeAddr("collateral").ERC721(44);
    uint256 loanId = 1;


    function setUp() public virtual {
        liquidationModule = new PWNOpenLiquidationModule();

        vm.mockCall(loanContract, abi.encodeWithSignature("loanToken()"), abi.encode(loanToken));
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId), abi.encode(liquidator));
        vm.mockCall(creditAddress, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));
        vm.mockCall(creditAddress, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(creditAddress, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));
        vm.mockCall(collateral.assetAddress, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(""));
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNOpenLiquidationModule_OnLoanCreated_Test is PWNOpenLiquidationModuleTest {

    function test_shouldReturnInitHookValue() external {
        assertEq(liquidationModule.onLoanCreated(loanId, ""), LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE);
    }

}


/*----------------------------------------------------------*|
|*  # LIQUIDATE                                             *|
|*----------------------------------------------------------*/

contract PWNOpenLiquidationModule_Liquidate_Test is PWNOpenLiquidationModuleTest {

    function test_shouldFail_whenDataIsNotEmpty() external {
        vm.expectRevert(PWNOpenLiquidationModule.LiquidationDataNotEmpty.selector);
        vm.prank(loanContract);
        liquidationModule.liquidate(loanId, liquidator, 1, creditAddress, collateral, "data");
    }

    function testFuzz_shouldTransferDebtFromLiquidator(uint256 debt) external {
        debt = bound(debt, 1, type(uint256).max);

        vm.expectCall(
            creditAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", liquidator, address(liquidationModule), debt)
        );

        vm.prank(loanContract);
        liquidationModule.liquidate(loanId, liquidator, debt, creditAddress, collateral, "");
    }

    function testFuzz_shouldApproveDebtAmountToLoanContract(uint256 debt) external {
        debt = bound(debt, 1, type(uint256).max);

        vm.expectCall(
            creditAddress,
            abi.encodeWithSignature("approve(address,uint256)", loanContract, debt)
        );

        vm.prank(loanContract);
        liquidationModule.liquidate(loanId, liquidator, debt, creditAddress, collateral, "");
    }

    function test_shouldTransferCollateralToLiquidator() external {
        vm.expectCall(
            collateral.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(liquidationModule), liquidator, collateral.id)
        );

        vm.prank(loanContract);
        liquidationModule.liquidate(loanId, liquidator, 1, creditAddress, collateral, "");
    }

    function testFuzz_shouldReturnDebtAmount(uint256 debt) external {
        debt = bound(debt, 1, type(uint256).max);

        vm.prank(loanContract);
        uint256 result = liquidationModule.liquidate(loanId, liquidator, debt, creditAddress, collateral, "");
        assertEq(result, debt);
    }

}
