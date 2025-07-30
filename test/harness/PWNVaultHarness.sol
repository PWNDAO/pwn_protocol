// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNVault, MultiToken, Asset, Permit } from "pwn/core/loan/PWNVault.sol";


contract PWNVaultHarness is PWNVault {

    constructor(address _permit2) PWNVault(_permit2) {}

    function pull(Asset memory asset, address origin, Permit memory permit) external {
        _pull(asset, origin, permit);
    }

    function push(Asset memory asset, address beneficiary) external {
        _push(asset, beneficiary);
    }

    function pushFrom(Asset memory asset, address origin, address beneficiary, Permit memory permit) external {
        _pushFrom(asset, origin, beneficiary, permit);
    }

}
