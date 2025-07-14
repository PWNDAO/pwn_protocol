// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNRevokedNonce,
    PWNHubTags
} from "pwn/periphery/auxiliary/PWNRevokedNonce.sol";


abstract contract PWNRevokedNonceTest is Test {

    bytes32 internal constant REVOKED_NONCE_SLOT = bytes32(uint256(0)); // `_revokedNonce` mapping position
    bytes32 internal constant NONCE_SPACE_SLOT = bytes32(uint256(1)); // `_nonceSpace` mapping position

    PWNRevokedNonce revokedNonce;
    bytes32 accessTag = keccak256("Some nice pwn tag");
    address hub = address(0x80b);
    address alice = address(0xa11ce);

    event NonceRevoked(address indexed owner, uint256 indexed nonceSpace, uint256 indexed nonce);
    event NonceSpaceRevoked(address indexed owner, uint256 indexed nonceSpace);


    function setUp() public virtual {
        revokedNonce = new PWNRevokedNonce(hub, accessTag);
    }


    function _revokedNonceSlot(address _owner, uint256 _nonceSpace, uint256 _nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _nonce,
            keccak256(abi.encode(
                _nonceSpace,
                keccak256(abi.encode(_owner, REVOKED_NONCE_SLOT))
            ))
        ));
    }

    function _nonceSpaceSlot(address _owner) internal pure returns (bytes32) {
        return keccak256(abi.encode(_owner, NONCE_SPACE_SLOT));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonce_Test is PWNRevokedNonceTest {

    function testFuzz_shouldFail_whenNonceAlreadyRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));
        vm.store(address(revokedNonce), _revokedNonceSlot(alice, nonceSpace, nonce), bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceAlreadyRevoked.selector, alice, nonceSpace, nonce));
        vm.prank(alice);
        revokedNonce.revokeNonce(nonce);
    }

    function testFuzz_shouldStoreNonceAsRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));

        vm.prank(alice);
        revokedNonce.revokeNonce(nonce);

        assertTrue(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce));
    }

    function testFuzz_shouldEmit_NonceRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));

        vm.expectEmit();
        emit NonceRevoked(alice, nonceSpace, nonce);

        vm.prank(alice);
        revokedNonce.revokeNonce(nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCES                                         *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonces_Test is PWNRevokedNonceTest {

    uint256[] nonces;

    function testFuzz_shouldFail_whenAnyNonceAlreadyRevoked(uint256 nonceSpace, uint256 nonce) external {
        nonce = bound(nonce, 0, type(uint256).max - 1);
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));
        vm.store(address(revokedNonce), _revokedNonceSlot(alice, nonceSpace, nonce), bytes32(uint256(1)));

        nonces = new uint256[](2);
        nonces[0] = nonce;
        nonces[1] = nonce + 1;

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceAlreadyRevoked.selector, alice, nonceSpace, nonce));
        vm.prank(alice);
        revokedNonce.revokeNonces(nonces);
    }

    function testFuzz_shouldStoreNoncesAsRevoked(
        uint256 nonceSpace, uint256 nonce1, uint256 nonce2, uint256 nonce3
    ) external {
        vm.assume(nonce1 != nonce2 && nonce2 != nonce3 && nonce1 != nonce3);
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));

        nonces = new uint256[](3);
        nonces[0] = nonce1;
        nonces[1] = nonce2;
        nonces[2] = nonce3;

        vm.prank(alice);
        revokedNonce.revokeNonces(nonces);

        assertTrue(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce1));
        assertTrue(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce2));
        assertTrue(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce3));
    }

    function testFuzz_shouldEmit_NonceRevoked(
        uint256 nonceSpace, uint256 nonce1, uint256 nonce2, uint256 nonce3
    ) external {
        vm.assume(nonce1 != nonce2 && nonce2 != nonce3 && nonce1 != nonce3);
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));

        nonces = new uint256[](3);
        nonces[0] = nonce1;
        nonces[1] = nonce2;
        nonces[2] = nonce3;

        for (uint256 i; i < nonces.length; ++i) {
            vm.expectEmit();
            emit NonceRevoked(alice, nonceSpace, nonces[i]);
        }

        vm.prank(alice);
        revokedNonce.revokeNonces(nonces);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE WITH NONCE SPACE                         *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceWithNonceSpace_Test is PWNRevokedNonceTest {

    function testFuzz_shouldFail_whenNonceAlreadyRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _revokedNonceSlot(alice, nonceSpace, nonce), bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceAlreadyRevoked.selector, alice, nonceSpace, nonce));
        vm.prank(alice);
        revokedNonce.revokeNonce(nonceSpace, nonce);
    }

    function testFuzz_shouldStoreNonceAsRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.prank(alice);
        revokedNonce.revokeNonce(nonceSpace, nonce);

        assertTrue(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce));
    }

    function testFuzz_shouldEmit_NonceRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.expectEmit();
        emit NonceRevoked(alice, nonceSpace, nonce);

        vm.prank(alice);
        revokedNonce.revokeNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE WITH OWNER                               *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceWithOwner_Test is PWNRevokedNonceTest {

    address accessEnabledAddress = address(0x01);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", accessEnabledAddress, accessTag),
            abi.encode(true)
        );
    }


    function testFuzz_shouldFail_whenCallerIsDoesNotHaveAccessTag(address caller) external {
        vm.assume(caller != accessEnabledAddress);

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.AddressMissingHubTag.selector, caller, accessTag));
        vm.prank(caller);
        revokedNonce.revokeNonce(caller, 1);
    }

    function testFuzz_shouldFail_whenNonceAlreadyRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(owner), bytes32(nonceSpace));
        vm.store(address(revokedNonce), _revokedNonceSlot(owner, nonceSpace, nonce), bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceAlreadyRevoked.selector, owner, nonceSpace, nonce));
        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonce);
    }

    function testFuzz_shouldStoreNonceAsRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(owner), bytes32(nonceSpace));

        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonce);

        assertTrue(revokedNonce.isNonceRevoked(owner, nonceSpace, nonce));
    }

    function testFuzz_shouldEmit_NonceRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(owner), bytes32(nonceSpace));

        vm.expectEmit();
        emit NonceRevoked(owner, nonceSpace, nonce);

        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE WITH NONCE SPACE AND OWNER               *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceWithNonceSpaceAndOwner_Test is PWNRevokedNonceTest {

    address accessEnabledAddress = address(0x01);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", accessEnabledAddress, accessTag),
            abi.encode(true)
        );
    }


    function testFuzz_shouldFail_whenCallerIsDoesNotHaveAccessTag(address caller) external {
        vm.assume(caller != accessEnabledAddress);

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.AddressMissingHubTag.selector, caller, accessTag));
        vm.prank(caller);
        revokedNonce.revokeNonce(caller, 1, 1);
    }

    function testFuzz_shouldFail_whenNonceAlreadyRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.store(address(revokedNonce), _revokedNonceSlot(owner, nonceSpace, nonce), bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceAlreadyRevoked.selector, owner, nonceSpace, nonce));
        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonceSpace, nonce);
    }

    function testFuzz_shouldStoreNonceAsRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonceSpace, nonce);

        assertTrue(revokedNonce.isNonceRevoked(owner, nonceSpace, nonce));
    }

    function testFuzz_shouldEmit_NonceRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.expectEmit();
        emit NonceRevoked(owner, nonceSpace, nonce);

        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # IS NONCE REVOKED                                      *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_IsNonceRevoked_Test is PWNRevokedNonceTest {

    function testFuzz_shouldReturnStoredValue(uint256 nonceSpace, uint256 nonce, bool revoked) external {
        vm.store(
            address(revokedNonce),
            _revokedNonceSlot(alice, nonceSpace, nonce),
            bytes32(uint256(revoked ? 1 : 0))
        );

        assertEq(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce), revoked);
    }

}


/*----------------------------------------------------------*|
|*  # IS NONCE USABLE                                       *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_IsNonceUsable_Test is PWNRevokedNonceTest {

    function testFuzz_shouldReturnFalse_whenNonceSpaceIsNotEqualToCurrentNonceSpace(
        uint256 currentNonceSpace,
        uint256 nonceSpace,
        uint256 nonce
    ) external {
        vm.assume(nonceSpace != currentNonceSpace);

        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(currentNonceSpace));

        assertFalse(revokedNonce.isNonceUsable(alice, nonceSpace, nonce));
    }

    function testFuzz_shouldReturnFalse_whenNonceIsRevoked(uint256 nonce) external {
        vm.store(address(revokedNonce), _revokedNonceSlot(alice, 0, nonce), bytes32(uint256(1)));

        assertFalse(revokedNonce.isNonceUsable(alice, 0, nonce));
    }

    function testFuzz_shouldReturnTrue__whenNonceSpaceIsEqualToCurrentNonceSpace_whenNonceIsNotRevoked(
        uint256 nonceSpace, uint256 nonce
    ) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));

        assertTrue(revokedNonce.isNonceUsable(alice, nonceSpace, nonce));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE SPACE                                    *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceSpace_Test is PWNRevokedNonceTest {

    function testFuzz_shouldIncrementCurrentNonceSpace(uint256 nonceSpace) external {
        nonceSpace = bound(nonceSpace, 0, type(uint256).max - 1);
        bytes32 nonceSpaceSlot = _nonceSpaceSlot(alice);
        vm.store(address(revokedNonce), nonceSpaceSlot, bytes32(nonceSpace));

        vm.prank(alice);
        revokedNonce.revokeNonceSpace();

        assertEq(revokedNonce.currentNonceSpace(alice), nonceSpace + 1);
    }

    function testFuzz_shouldEmit_NonceSpaceRevoked(uint256 nonceSpace) external {
        nonceSpace = bound(nonceSpace, 0, type(uint256).max - 1);
        bytes32 nonceSpaceSlot = _nonceSpaceSlot(alice);
        vm.store(address(revokedNonce), nonceSpaceSlot, bytes32(nonceSpace));

        vm.expectEmit();
        emit NonceSpaceRevoked(alice, nonceSpace);

        vm.prank(alice);
        revokedNonce.revokeNonceSpace();
    }

    function testFuzz_shouldReturnNewNonceSpace(uint256 nonceSpace) external {
        nonceSpace = bound(nonceSpace, 0, type(uint256).max - 1);
        bytes32 nonceSpaceSlot = _nonceSpaceSlot(alice);
        vm.store(address(revokedNonce), nonceSpaceSlot, bytes32(nonceSpace));

        vm.prank(alice);
        uint256 currentNonceSpace = revokedNonce.revokeNonceSpace();

        assertEq(currentNonceSpace, nonceSpace + 1);
    }

}


/*----------------------------------------------------------*|
|*  # CURRENT NONCE SPACE                                   *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_CurrentNonceSpace_Test is PWNRevokedNonceTest {

    function testFuzz_shouldReturnCurrentNonceSpace(uint256 nonceSpace) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));

        uint256 currentNonceSpace = revokedNonce.currentNonceSpace(alice);

        assertEq(currentNonceSpace, nonceSpace);
    }

}
