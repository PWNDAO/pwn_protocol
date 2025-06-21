// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNInterestModule } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNDefaultModule } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import {
    PWNClaimLiquidationModule,
    IERC721Receiver, IERC1155Receiver, IERC165,
    PWNLoan,
    IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE
} from "pwn/periphery/loan/module/liquidation/PWNClaimLiquidationModule.sol";

using MultiToken for address;

abstract contract PWNClaimLiquidationModuleTest is Test {

    PWNClaimLiquidationModule liquidationModule;
    address loanContract = makeAddr("loanContract");
    address loanToken = makeAddr("loanToken");
    address liquidator = makeAddr("liquidator");
    MultiToken.Asset collateral = makeAddr("collateral").ERC721(44);
    uint256 loanId = 1;


    function setUp() public virtual {
        liquidationModule = new PWNClaimLiquidationModule();

        vm.mockCall(loanContract, abi.encodeWithSignature("loanToken()"), abi.encode(loanToken));
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId), abi.encode(liquidator));
        vm.mockCall(
            collateral.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode("")
        );
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNClaimLiquidationModule_OnLoanCreated_Test is PWNClaimLiquidationModuleTest {

    function test_shouldReturnInitHookValue() external {
        assertEq(liquidationModule.onLoanCreated(loanId, ""), LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE);
    }

}


/*----------------------------------------------------------*|
|*  # LIQUIDATE                                             *|
|*----------------------------------------------------------*/

contract PWNClaimLiquidationModule_Liquidate_Test is PWNClaimLiquidationModuleTest {

    function test_shouldFail_whenLiquidatorIsNotLoanOwner() external {
        address loanOwner = makeAddr("loanOwner");
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId), abi.encode(loanOwner));

        vm.expectCall(loanContract, abi.encodeWithSignature("loanToken()"));
        vm.expectCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId));

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNClaimLiquidationModule.LiquidatorNotLoanOwner.selector,
                loanOwner, liquidator, loanContract, loanId
            )
        );
        vm.prank(loanContract);
        liquidationModule.liquidate(loanId, liquidator, 0, address(0), collateral, "");
    }

    function test_shouldFail_whenDataIsNotEmpty() external {
        vm.expectRevert(PWNClaimLiquidationModule.LiquidationDataNotEmpty.selector);
        vm.prank(loanContract);
        liquidationModule.liquidate(loanId, liquidator, 0, address(0), collateral, "data");
    }

    function test_shouldTransferCollateralToLiquidator() external {
        vm.expectCall(
            collateral.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(liquidationModule), liquidator, collateral.id)
        );

        vm.prank(loanContract);
        liquidationModule.liquidate(loanId, liquidator, 0, address(0), collateral, "");
    }

    function test_shouldReturnZero() external {
        vm.prank(loanContract);
        uint256 result = liquidationModule.liquidate(loanId, liquidator, 0, address(0), collateral, "");
        assertEq(result, 0);
    }

}


/*----------------------------------------------------------*|
|*  # RECEIVED HOOKS                                        *|
|*----------------------------------------------------------*/

contract PWNClaimLiquidationModule_ReceivedHooks_Test is PWNClaimLiquidationModuleTest {

    function test_shouldReturnSelector_whenERC721Received() external {
        bytes4 selector = liquidationModule.onERC721Received(
            address(0), address(0), 0, ""
        );
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    function test_shouldReturnSelector_whenERC1155Received() external {
        bytes4 selector = liquidationModule.onERC1155Received(
            address(0), address(0), 0, 0, ""
        );
        assertEq(selector, IERC1155Receiver.onERC1155Received.selector);
    }

    function test_shouldReturnSelector_whenERC1155BatchReceived() external {
        bytes4 selector = liquidationModule.onERC1155BatchReceived(
            address(0), address(0), new uint256[](0), new uint256[](0), ""
        );
        assertEq(selector, IERC1155Receiver.onERC1155BatchReceived.selector);
    }

}


/*----------------------------------------------------------*|
|*  # SUPPORTED INTERFACES                                  *|
|*----------------------------------------------------------*/

contract PWNClaimLiquidationModule_SupportedInterfaces_Test is PWNClaimLiquidationModuleTest {

    function test_shouldSupportIPWNLiquidationModule() external {
        assertTrue(liquidationModule.supportsInterface(type(IPWNLiquidationModule).interfaceId));
    }

    function test_shouldSupportIERC165() external {
        assertTrue(liquidationModule.supportsInterface(type(IERC165).interfaceId));
    }

    function test_shouldSupportIERC721Receiver() external {
        assertTrue(liquidationModule.supportsInterface(type(IERC721Receiver).interfaceId));
    }

    function test_shouldSupportIERC1155Receiver() external {
        assertTrue(liquidationModule.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

}
