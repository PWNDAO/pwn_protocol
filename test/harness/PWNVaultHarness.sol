// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNVault, MultiToken, Asset } from "pwn/core/loan/PWNVault.sol";


contract PWNVaultHarness is PWNVault {

    function pull(Asset memory asset, address origin) external {
        _pull(asset, origin);
    }

    function push(Asset memory asset, address beneficiary) external {
        _push(asset, beneficiary);
    }

    function pushFrom(Asset memory asset, address origin, address beneficiary) external {
        _pushFrom(asset, origin, beneficiary);
    }

}
