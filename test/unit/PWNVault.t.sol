// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken, Asset, Category } from "MultiToken/MultiToken.sol";

import {
    IERC165,
    IERC721Receiver,
    IERC1155Receiver,
    PWNVault
} from "pwn/core/loan/PWNVault.sol";
import { Permit, IPermit2Like } from "pwn/core/loan/Permit.sol";

import { PWNVaultHarness } from "test/harness/PWNVaultHarness.sol";
import { T20 } from "test/helper/T20.sol";
import { DummyPermit2 } from "test/helper/DummyPermit2.sol";

using MultiToken for address;

abstract contract PWNVaultTest is Test {

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address permit2 = address(new DummyPermit2());
    uint256 amount = 42 ether;
    T20 t20 = new T20();
    Asset asset = address(t20).ERC20(amount);
    Permit permit = Permit({
        permit: IPermit2Like.PermitTransferFrom(IPermit2Like.TokenPermissions(address(t20), amount), 2, 3),
        signature: "signature"
    });

    PWNVaultHarness vault = new PWNVaultHarness(permit2);

    event VaultPull(Asset asset, address indexed origin);
    event VaultPush(Asset asset, address indexed beneficiary);
    event VaultPushFrom(Asset asset, address indexed origin, address indexed beneficiary);

    function setUp() public virtual {
        t20.mint(alice, amount);
        vm.prank(alice);
        t20.approve(permit2, type(uint256).max);
    }

}


/*----------------------------------------------------------*|
|*  # PULL                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Pull_Test is PWNVaultTest {

    function test_shouldCallTransferFrom_fromOrigin_toVault_whenEmptyPermit() external {
        permit.signature = "";

        vm.expectCall(
            permit2,
            abi.encodeWithSelector(IPermit2Like.transferFrom.selector, alice, address(vault), amount, address(t20))
        );

        vault.pull(asset, alice, permit);
    }

    function test_shouldCallPermit2Transfer_fromOrigin_toVault_whenPermit() external {
        permit.signature = "signature";

        vm.expectCall(
            permit2,
            abi.encodeWithSelector(
                IPermit2Like.permitTransferFrom.selector,
                permit.permit, IPermit2Like.SignatureTransferDetails(address(vault), amount), alice, permit.signature
            )
        );

        vault.pull(asset, alice, permit);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            address(t20),
            abi.encodeWithSignature("balanceOf(address)", address(vault)),
            abi.encode(0)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        vault.pull(asset, alice, permit);
    }

    function test_shouldFail_whenSameSourceAndDestination() external {
        t20.mint(address(vault), amount);

        vm.expectRevert(abi.encodeWithSelector(PWNVault.VaultTransferSameSourceAndDestination.selector, address(vault)));
        vault.pull(asset, address(vault), permit);
    }

    function test_shouldEmitEvent_VaultPull() external {
        vm.expectEmit();
        emit VaultPull(asset, alice);

        vault.pull(asset, alice, permit);
    }

}


/*----------------------------------------------------------*|
|*  # PUSH                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Push_Test is PWNVaultTest {

    function setUp() public override virtual {
        super.setUp();
        t20.mint(address(vault), amount);
    }


    function test_shouldCallSafeTransferFrom_fromVault_toBeneficiary() external {
        vm.expectCall(
            address(t20),
            abi.encodeWithSignature("transfer(address,uint256)", alice, amount)
        );

        vault.push(asset, alice);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            address(t20),
            abi.encodeWithSignature("balanceOf(address)", alice),
            abi.encode(0)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        vault.push(asset, alice);
    }

    function test_shouldFail_whenSameSourceAndDestination() external {
        vm.expectRevert(abi.encodeWithSelector(PWNVault.VaultTransferSameSourceAndDestination.selector, address(vault)));
        vault.push(asset, address(vault));
    }

    function test_shouldEmitEvent_VaultPush() external {
        vm.expectEmit();
        emit VaultPush(asset, alice);

        vault.push(asset, alice);
    }

}


/*----------------------------------------------------------*|
|*  # PUSH FROM                                             *|
|*----------------------------------------------------------*/

contract PWNVault_PushFrom_Test is PWNVaultTest {

    function test_shouldCallTransferFrom_fromOrigin_toBeneficiary_whenEmptyPermit() external {
        permit.signature = "";

        vm.expectCall(
            permit2,
            abi.encodeWithSelector(IPermit2Like.transferFrom.selector, alice, bob, amount, address(t20))
        );

        vault.pushFrom(asset, alice, bob, permit);
    }

    function test_shouldCallPermit2Transfer_fromOrigin_toBeneficiary_whenPermit() external {
        permit.signature = "signature";

        vm.expectCall(
            permit2,
            abi.encodeWithSelector(
                IPermit2Like.permitTransferFrom.selector,
                permit.permit, IPermit2Like.SignatureTransferDetails(bob, amount), alice, permit.signature
            )
        );

        vault.pushFrom(asset, alice, bob, permit);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            address(t20),
            abi.encodeWithSignature("balanceOf(address)", bob),
            abi.encode(0)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        vault.pushFrom(asset, alice, bob, permit);
    }

    function test_shouldFail_whenSameSourceAndDestination() external {
        vm.expectRevert(abi.encodeWithSelector(PWNVault.VaultTransferSameSourceAndDestination.selector, alice));
        vault.pushFrom(asset, alice, alice, permit);
    }

    function test_shouldEmitEvent_VaultPushFrom() external {
        vm.expectEmit();
        emit VaultPushFrom(asset, alice, bob);

        vault.pushFrom(asset, alice, bob, permit);
    }

}


/*----------------------------------------------------------*|
|*  # ERC721/1155 RECEIVED HOOKS                            *|
|*----------------------------------------------------------*/

contract PWNVault_ReceivedHooks_Test is PWNVaultTest {

    function test_shouldReturnCorrectValue_whenOperatorIsVault_onERC721Received() external {
        bytes4 returnValue = vault.onERC721Received(address(vault), address(0), 0, "");

        assertTrue(returnValue == IERC721Receiver.onERC721Received.selector);
    }

    function test_shouldFail_whenOperatorIsNotVault_onERC721Received() external {
        vm.expectRevert(abi.encodeWithSelector(PWNVault.UnsupportedTransferFunction.selector));
        vault.onERC721Received(address(0), address(0), 0, "");
    }

    function test_shouldReturnCorrectValue_whenOperatorIsVault_onERC1155Received() external {
        bytes4 returnValue = vault.onERC1155Received(address(vault), address(0), 0, 0, "");

        assertTrue(returnValue == IERC1155Receiver.onERC1155Received.selector);
    }

    function test_shouldFail_whenOperatorIsNotVault_onERC1155Received() external {
        vm.expectRevert(abi.encodeWithSelector(PWNVault.UnsupportedTransferFunction.selector));
        vault.onERC1155Received(address(0), address(0), 0, 0, "");
    }

    function test_shouldFail_whenOnERC1155BatchReceived() external {
        uint256[] memory ids;
        uint256[] memory values;

        vm.expectRevert(abi.encodeWithSelector(PWNVault.UnsupportedTransferFunction.selector));
        vault.onERC1155BatchReceived(address(0), address(0), ids, values, "");
    }

}


/*----------------------------------------------------------*|
|*  # SUPPORTS INTERFACE                                    *|
|*----------------------------------------------------------*/

contract PWNVault_SupportsInterface_Test is PWNVaultTest {

    function test_shouldReturnTrue_whenIERC165() external {
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId));
    }

    function test_shouldReturnTrue_whenIERC721Receiver() external {
        assertTrue(vault.supportsInterface(type(IERC721Receiver).interfaceId));
    }

    function test_shouldReturnTrue_whenIERC1155Receiver() external {
        assertTrue(vault.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

}
