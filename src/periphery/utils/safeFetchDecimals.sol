// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


function safeFetchDecimals(address asset) view returns (uint256) {
    (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSignature("decimals()"));
    if (!success || returndata.length == 0) {
        return 0;
    }
    return abi.decode(returndata, (uint256));
}
