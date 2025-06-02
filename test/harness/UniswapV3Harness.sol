// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { UniswapV3 } from "pwn/periphery/lib/UniswapV3.sol";


contract UniswapV3Harness {

    function getLPValue(
        UniswapV3.Config memory config,
        uint256 tokenId,
        bool token0Denominator
    ) external view returns (uint256 value, address denominator) {
        return UniswapV3.getLPValue(config, tokenId, token0Denominator);
    }

}
