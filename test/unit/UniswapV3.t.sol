// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test, console2 } from "forge-std/Test.sol";

import {
    UniswapV3,
    INonfungiblePositionManager
} from "pwn/periphery/lib/UniswapV3.sol";

import { UniswapV3Harness } from "test/harness/UniswapV3Harness.sol";


abstract contract UniswapV3Test is Test {

    UniswapV3Harness uniswap;
    UniswapV3.Config config;

    INonfungiblePositionManager uniswapNFTPositionManager = INonfungiblePositionManager(makeAddr("uniswapNFTPositionManager"));
    address uniswapV3Factory = makeAddr("uniswapV3Factory");

    uint256 tokenId = 420;
    address token0 = makeAddr("token0");
    address token1 = makeAddr("token1");
    uint24 fee = 3000;
    address pool = 0xb44E273AE4071AA4a0F2b05ee96f20BB6FfD568b;

    function setUp() public virtual {
        uniswap = new UniswapV3Harness();

        config = UniswapV3.Config({
            positionManager: uniswapNFTPositionManager,
            factory: uniswapV3Factory
        });

        vm.mockCall(address(uniswapNFTPositionManager), abi.encodeWithSignature("factory()"), abi.encode(uniswapV3Factory));
    }


    function _mockPosition(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 tokensOwed0,
        uint256 tokensOwed1
    ) internal {
        vm.mockCall(
            address(uniswapNFTPositionManager),
            abi.encodeWithSelector(INonfungiblePositionManager.positions.selector, tokenId),
            abi.encode(0, 0, token0, token1, fee, tickLower, tickUpper, liquidity, 0, 0, tokensOwed0, tokensOwed1)
        );
    }

    function _mockPool(address _pool, int24 currentTick) internal {
        vm.mockCall(_pool, abi.encodeWithSignature("slot0()"), abi.encode(0, currentTick, 0, 2, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("observations(uint256)"), abi.encode(block.timestamp - 1, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("liquidity()"), abi.encode(0)); // need to not revert
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal0X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal1X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("ticks(int24)"), abi.encode(0, 0, 0, 0, 0, 0, 0, 0));
    }

}


/*----------------------------------------------------------*|
|*  # GET LP VALUE                                          *|
|*----------------------------------------------------------*/

contract UniswapV3_GetLPValue_Test is UniswapV3Test {

    function test_underRange() external {
        _mockPosition(100_000, 200_000, 100e6, 0, 0);

        _mockPool(pool, 10_000);
        (uint256 token0Amount1, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount1, ) = uniswap.getLPValue(config, tokenId, false);

        _mockPool(pool, 50_000);
        (uint256 token0Amount2, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount2, ) = uniswap.getLPValue(config, tokenId, false);

        assertEq(token0Amount1, token0Amount2);
        assertLt(token1Amount1, token1Amount2);
    }

    function test_aboveRange() external {
        _mockPosition(100_000, 200_000, 100e6, 0, 0);

        _mockPool(pool, 210_000);
        (uint256 token0Amount1, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount1, ) = uniswap.getLPValue(config, tokenId, false);

        _mockPool(pool, 250_000);
        (uint256 token0Amount2, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount2, ) = uniswap.getLPValue(config, tokenId, false);

        assertGt(token0Amount1, token0Amount2);
        assertEq(token1Amount1, token1Amount2);
    }

    function test_inRange() external {
        _mockPosition(100_000, 200_000, 100e6, 0, 0);

        _mockPool(pool, 110_000);
        (uint256 token0Amount1, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount1, ) = uniswap.getLPValue(config, tokenId, false);

        _mockPool(pool, 180_000);
        (uint256 token0Amount2, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount2, ) = uniswap.getLPValue(config, tokenId, false);

        assertGt(token0Amount1, token0Amount2);
        assertLt(token1Amount1, token1Amount2);
    }

    function test_shouldIncludeFees() external {
        _mockPool(pool, 110_000);

        _mockPosition(100_000, 200_000, 100e6, 0, 0);
        (uint256 token0Amount1, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount1, ) = uniswap.getLPValue(config, tokenId, false);

        _mockPosition(100_000, 200_000, 100e6, 10e18, 8e5);
        (uint256 token0Amount2, ) = uniswap.getLPValue(config, tokenId, true);
        (uint256 token1Amount2, ) = uniswap.getLPValue(config, tokenId, false);

        assertLt(token0Amount1 + 10e18, token0Amount2);
        assertLt(token1Amount1 + 8e5, token1Amount2);
    }

}
