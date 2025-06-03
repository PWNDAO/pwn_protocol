// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    MultiToken,
    IERC165,
    IERC721Receiver,
    IERC1155Receiver,
    PWNVault
} from "pwn/core/loan/PWNVault.sol";

import { PWNVaultHarness } from "test/harness/PWNVaultHarness.sol";
import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";


abstract contract PWNVaultTest is Test {

    PWNVaultHarness vault;
    address token = makeAddr("token");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    T20 t20;
    T721 t721;

    event VaultPull(MultiToken.Asset asset, address indexed origin);
    event VaultPush(MultiToken.Asset asset, address indexed beneficiary);
    event VaultPushFrom(MultiToken.Asset asset, address indexed origin, address indexed beneficiary);

    constructor() {
        vm.etch(token, bytes("data"));
    }

    function setUp() public virtual {
        vault = new PWNVaultHarness();
        t20 = new T20();
        t721 = new T721();
    }

}


/*----------------------------------------------------------*|
|*  # PULL                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Pull_Test is PWNVaultTest {

    function test_shouldCallTransferFrom_fromOrigin_toVault() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        vm.expectCall(
            address(t721),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", alice, address(vault), 42)
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 0);
        vault.pull(asset, alice);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("ownerOf(uint256)"),
            abi.encode(alice)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 0);
        vault.pull(asset, alice);
    }

    function test_shouldFail_whenSameSourceAndDestination() external {
        t721.mint(address(vault), 42);

        vm.expectRevert(abi.encodeWithSelector(PWNVault.VaultTransferSameSourceAndDestination.selector, address(vault)));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 0);
        vault.pull(asset, address(vault));
    }

    function test_shouldEmitEvent_VaultPull() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 0);

        vm.expectEmit(true, true, true, true);
        emit VaultPull(asset, alice);

        vault.pull(asset, alice);
    }

}


/*----------------------------------------------------------*|
|*  # PUSH                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Push_Test is PWNVaultTest {

    function test_shouldCallSafeTransferFrom_fromVault_toBeneficiary() external {
        t721.mint(address(vault), 42);

        vm.expectCall(
            address(t721),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", address(vault), alice, 42, "")
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);
        vault.push(asset, alice);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("ownerOf(uint256)"),
            abi.encode(address(vault))
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 0);
        vault.push(asset, alice);
    }

    function test_shouldFail_whenSameSourceAndDestination() external {
        t721.mint(address(vault), 42);

        vm.expectRevert(abi.encodeWithSelector(PWNVault.VaultTransferSameSourceAndDestination.selector, address(vault)));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 0);
        vault.push(asset, address(vault));
    }

    function test_shouldEmitEvent_VaultPush() external {
        t721.mint(address(vault), 42);

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);

        vm.expectEmit(true, true, true, true);
        emit VaultPush(asset, alice);

        vault.push(asset, alice);
    }

}


/*----------------------------------------------------------*|
|*  # PUSH FROM                                             *|
|*----------------------------------------------------------*/

contract PWNVault_PushFrom_Test is PWNVaultTest {

    function test_shouldCallSafeTransferFrom_fromOrigin_toBeneficiary() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        vm.expectCall(
            address(t721),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", alice, bob, 42, "")
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);
        vault.pushFrom(asset, alice, bob);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("ownerOf(uint256)"),
            abi.encode(alice)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 0);
        vault.pushFrom(asset, alice, bob);
    }

    function test_shouldFail_whenSameSourceAndDestination() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        vm.expectRevert(abi.encodeWithSelector(PWNVault.VaultTransferSameSourceAndDestination.selector, alice));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 0);
        vault.pushFrom(asset, alice, alice);
    }

    function test_shouldEmitEvent_VaultPushFrom() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);

        vm.expectEmit(true, true, true, false);
        emit VaultPushFrom(asset, alice, bob);

        vault.pushFrom(asset, alice, bob);
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
