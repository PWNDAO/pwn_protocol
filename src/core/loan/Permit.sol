// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPermit2Like } from "MultiToken/interfaces/IPermit2Like.sol";

function EMPTY_PERMIT() pure returns (Permit memory) {
    return Permit({
        permit: IPermit2Like.PermitTransferFrom(IPermit2Like.TokenPermissions(address(0), 0), 0, 0),
        signature: ""
    });
}

struct Permit {
    IPermit2Like.PermitTransferFrom permit;
    bytes signature;
}
