// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import { IPermit2Like } from "MultiToken/interfaces/IPermit2Like.sol";


contract DummyPermit2 {

    function permitTransferFrom(
        IPermit2Like.PermitTransferFrom memory permit,
        IPermit2Like.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata /* signature */
    ) external {
        IERC20(permit.permitted.token).transferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        IERC20(token).transferFrom(from, to, amount);
    }

}
