// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface ICometLike {
    function allow(address manager, bool isAllowed) external;

    function supply(address asset, uint amount) external;
    function supplyFrom(address from, address dst, address asset, uint amount) external;

    function withdraw(address asset, uint amount) external;
    function withdrawFrom(address src, address to, address asset, uint amount) external;
}
