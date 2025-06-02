// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { safeFetchDecimals } from "pwn/periphery/utils/safeFetchDecimals.sol";


contract SafeFetchDecimalsTest is Test {

    address asset = makeAddr("asset");


    function testFuzz_shouldFetchDecimals_whenImplemented(uint256 _decimals) external {
        vm.mockCall(
            asset,
            abi.encodeWithSignature("decimals()"),
            abi.encode(_decimals)
        );

        uint256 decimals = safeFetchDecimals(asset);

        assertEq(decimals, _decimals);
    }

    function test_shouldReturnZero_whenContract_whenNotImplemented() external {
        vm.etch(asset, "bytes");

        uint256 decimals = safeFetchDecimals(asset);

        assertEq(decimals, 0);
    }

    function test_shouldReturnZero_whenNotContract() external {
        uint256 decimals = safeFetchDecimals(asset);

        assertEq(decimals, 0);
    }

}
