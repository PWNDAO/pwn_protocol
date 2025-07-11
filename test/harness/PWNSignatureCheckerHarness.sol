// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNSignatureChecker } from "pwn/core/lib/PWNSignatureChecker.sol";


contract PWNSignatureCheckerHarness {

    function exposed_isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) external view returns (bool) {
        return PWNSignatureChecker.isValidSignatureNow(signer, hash, signature);
    }

}
