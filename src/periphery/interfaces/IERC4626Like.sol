// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface IERC4626Like {
    function asset() external view returns (address);

    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}
