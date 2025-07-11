// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNSignatureChecker } from "pwn/core/lib/PWNSignatureChecker.sol";

import { PWNSignatureCheckerHarness } from "test/harness/PWNSignatureCheckerHarness.sol";


abstract contract PWNSignatureCheckerTest is Test {
    uint256 signerPK = uint256(93081283);
    address signer = vm.addr(signerPK);
    bytes32 digest = keccak256("Hey, anybody know a good tailor?");
    bytes signature;

    PWNSignatureCheckerHarness signatureChecker;

    function setUp() public virtual {
        signatureChecker = new PWNSignatureCheckerHarness();
    }


    function _sign(uint256 pk, bytes32 _digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _digest);
        return abi.encodePacked(r, s, v);
    }

    function _signCompact(uint256 pk, bytes32 _digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _digest);
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }
}


/*----------------------------------------------------------*|
|*  # IS VALID SIGNATURE NOW                                *|
|*----------------------------------------------------------*/

contract PWNSignatureChecker_isValidSignatureNow_Test is PWNSignatureCheckerTest {

    function test_shouldCallEIP1271Function_whenSignerIsContractAccount() external {
        vm.etch(signer, "You need clothes altered?");
        vm.mockCall(
            signer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.expectCall(
            signer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)", digest, "")
        );

        PWNSignatureChecker.isValidSignatureNow(signer, digest, "");
    }

    function test_shouldReturnFalse_whenSignerIsContractAccount_whenEIP1271FunctionCallFails() external {
        vm.etch(signer, "No. I am just looking for a man to draw on me with chalk.");
        vm.mockCallRevert(signer, abi.encodeWithSignature("isValidSignature(bytes32,bytes)"), "not today");

        assertFalse(PWNSignatureChecker.isValidSignatureNow(signer, digest, ""));
    }

    function test_shouldFail_whenSignerIsContractAccount_whenEIP1271FunctionReturnsWrongDataLength() external {
        vm.etch(signer, "No. I am just looking for a man to draw on me with chalk.");
        vm.mockCall(
            signer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encodePacked(bytes4(0x1626ba7e))
        );

        assertFalse(PWNSignatureChecker.isValidSignatureNow(signer, digest, ""));
    }

    function test_shouldFail_whenSignerIsContractAccount_whenEIP1271FunctionNotReturnsCorrectValue() external {
        vm.etch(signer, "Go see Frankie.");
        vm.mockCall(
            signer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0))
        );

        assertFalse(PWNSignatureChecker.isValidSignatureNow(signer, digest, ""));
    }

    function test_shouldReturnTrue_whenSignerIsContractAccount_whenEIP1271FunctionReturnsCorrectValue() external {
        vm.etch(signer, "My familys been going to him forever.");
        vm.mockCall(
            signer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        assertTrue(PWNSignatureChecker.isValidSignatureNow(signer, digest, ""));
    }

    function test_shouldFail_whenSignerIsEOA_whenSignatureHasWrongLength() external {
        signature = abi.encodePacked(uint256(1), uint256(2), uint256(3));

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignatureLength.selector, 96));
        signatureChecker.exposed_isValidSignatureNow(signer, digest, signature);
    }

    function test_shouldFail_whenSignerIsEOA_whenInvalidSignature() external {
        signature = abi.encodePacked(uint8(1), uint256(2), uint256(3));

        vm.expectRevert("ECDSA: invalid signature");
        signatureChecker.exposed_isValidSignatureNow(signer, digest, signature);
    }

    function test_shouldReturnTrue_whenSignerIsEOA_whenSignerIsRecoveredAddressOfSignature() external {
        signature = _sign(signerPK, digest);

        assertTrue(PWNSignatureChecker.isValidSignatureNow(signer, digest, signature));
    }

    function test_shouldSupportCompactEIP2098Signatures_whenSignerIsEOA() external {
        signature = _signCompact(signerPK, digest);

        assertTrue(PWNSignatureChecker.isValidSignatureNow(signer, digest, signature));
    }

    function test_shouldReturnFalse_whenSignerIsEOA_whenSignerIsNotRecoveredAddressOfSignature() external {
        signature = _sign(1, digest);

        assertFalse(PWNSignatureChecker.isValidSignatureNow(signer, digest, signature));
    }

}
