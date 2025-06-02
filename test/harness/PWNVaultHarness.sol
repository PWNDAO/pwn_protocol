// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNVault, MultiToken } from "pwn/core/loan/PWNVault.sol";


contract PWNVaultHarness is PWNVault {

    function pull(MultiToken.Asset memory asset, address origin) external {
        _pull(asset, origin);
    }

    function push(MultiToken.Asset memory asset, address beneficiary) external {
        _push(asset, beneficiary);
    }

    function pushFrom(MultiToken.Asset memory asset, address origin, address beneficiary) external {
        _pushFrom(asset, origin, beneficiary);
    }

}
