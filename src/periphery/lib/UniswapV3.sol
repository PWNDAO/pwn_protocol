// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { PoolAddress } from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import { PositionValue } from "@uniswap/v3-periphery/contracts/libraries/PositionValue.sol";


library UniswapV3 {
    using SafeCast for uint256;

    struct Config {
        INonfungiblePositionManager positionManager;
        address factory;
    }

    /**
     * @notice Get the value of a Uniswap V3 LP token denominated in token0 or token1.
     * @param tokenId The token ID of the LP token.
     * @param token0Denominator Whether to use token0 as the denominator.
     * @param config The Uniswap configuration.
     * @return value The value of the LP token.
     * @return denominator The address of the token used as the denominator. Token0, if token0Denominator is true, otherwise token1.
     */
    function getLPValue(
        Config memory config,
        uint256 tokenId,
        bool token0Denominator
    ) internal view returns (uint256 value, address denominator) {
        // get LP pool price as a tick
        (,, address token0, address token1, uint24 fee,,,,,,,) = config.positionManager.positions(tokenId);
        address pool = PoolAddress.computeAddress(config.factory, PoolAddress.getPoolKey(token0, token1, fee));
        (int24 tick, ) = OracleLibrary.getBlockStartingTickAndLiquidity(pool);

        // get LP token amounts
        (uint256 amount0, uint256 amount1) = PositionValue
            .total(config.positionManager, tokenId, TickMath.getSqrtRatioAtTick(tick));

        // get LP value with tokenA denomination
        value = token0Denominator ?
            amount0 + OracleLibrary.getQuoteAtTick(tick, amount1.toUint128(), token1, token0) :
            amount1 + OracleLibrary.getQuoteAtTick(tick, amount0.toUint128(), token0, token1);

        denominator = token0Denominator ? token0 : token1;
    }

}
