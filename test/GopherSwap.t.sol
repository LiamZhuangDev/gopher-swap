// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

import {IPool} from "../interfaces/IPool.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {SwapRouter} from "../src/SwapRouter.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GopherSwapTest is Test {
    PoolManager public poolManager;
    SwapRouter public swapRouter;
    PositionManager public positionManager;

    MockToken public tokenA;
    MockToken public tokenB;
    MockToken public token0;
    MockToken public token1;

    address public lp = makeAddr("lp");
    address public trader = makeAddr("trader");

    uint24 public constant FEE = 3_000;
    int24 public constant TICK_LOWER = -60;
    int24 public constant TICK_UPPER = 60;
    uint160 public constant SQRT_PRICE_X96 = 79_228_162_514_264_337_593_543_950_336;

    function setUp() public {
        poolManager = new PoolManager();
        swapRouter = new SwapRouter(poolManager);
        positionManager = new PositionManager(address(poolManager));

        tokenA = new MockToken("Token A", "TKNA");
        tokenB = new MockToken("Token B", "TKNB");
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        token0.mint(lp, 10_000 ether);
        token1.mint(lp, 10_000 ether);
        token0.mint(trader, 100 ether);
        token1.mint(trader, 100 ether);
    }

    function test_DeploysProtocolContractsWithExpectedWiring() public view {
        assertEq(address(swapRouter.poolManager()), address(poolManager));
        assertEq(address(positionManager.poolManager()), address(poolManager));
        assertEq(positionManager.name(), "GopherSwapPosition");
        assertEq(positionManager.symbol(), "GSP");
    }

    function test_CreatesAndInitializesPool() public {
        address poolAddress = _createPool();
        IPool pool = IPool(poolAddress);

        assertEq(pool.factory(), address(poolManager));
        assertEq(pool.token0(), address(token0));
        assertEq(pool.token1(), address(token1));
        assertEq(pool.fee(), FEE);
        assertEq(pool.tickLower(), TICK_LOWER);
        assertEq(pool.tickUpper(), TICK_UPPER);
        assertEq(pool.sqrtPriceX96(), SQRT_PRICE_X96);
        assertEq(pool.tick(), 0);
        assertEq(poolManager.getPool(address(token0), address(token1), 0), poolAddress);

        IPoolManager.Pair[] memory pairs = poolManager.getPairs();
        assertEq(pairs.length, 1);
        assertEq(pairs[0].token0, address(token0));
        assertEq(pairs[0].token1, address(token1));

        IPoolManager.PoolInfo[] memory pools = poolManager.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0].pool, poolAddress);
        assertEq(pools[0].index, 0);
    }

    function test_MintsLiquidityPosition() public {
        address poolAddress = _createPool();

        vm.startPrank(lp);
        token0.approve(address(positionManager), type(uint256).max);
        token1.approve(address(positionManager), type(uint256).max);
        (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            positionManager.mint(_mintParams(lp, 1_000 ether, 1_000 ether));
        vm.stopPrank();

        assertEq(positionManager.ownerOf(positionId), lp);
        assertGt(liquidity, 0);
        assertGt(amount0, 0);
        assertGt(amount1, 0);
        assertEq(IPool(poolAddress).liquidity(), liquidity);
        assertEq(token0.balanceOf(poolAddress), amount0);
        assertEq(token1.balanceOf(poolAddress), amount1);

        IPositionManager.PositionInfo[] memory positions = positionManager.getPositions();
        assertEq(positions.length, 1);
        assertEq(positions[0].id, positionId);
        assertEq(positions[0].owner, lp);
        assertEq(positions[0].liquidity, liquidity);
    }

    function test_SwapsExactInputThroughRouter() public {
        address poolAddress = _createPool();
        _mintLiquidity(lp, 1_000 ether, 1_000 ether);

        uint256 traderToken0Before = token0.balanceOf(trader);
        uint256 traderToken1Before = token1.balanceOf(trader);
        uint256 poolToken0Before = token0.balanceOf(poolAddress);

        uint32[] memory indexPath = new uint32[](1);
        indexPath[0] = 0;

        vm.startPrank(trader);
        token0.approve(address(swapRouter), type(uint256).max);
        uint256 amountOut = swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                indexPath: indexPath,
                recipient: trader,
                deadline: block.timestamp,
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(-1)
            })
        );
        vm.stopPrank();

        assertGt(amountOut, 0);
        assertLt(token0.balanceOf(trader), traderToken0Before);
        assertGt(token1.balanceOf(trader), traderToken1Before);
        assertGt(token0.balanceOf(poolAddress), poolToken0Before);
    }

    function test_RevertsWhenCreatingPoolWithUnsortedTokens() public {
        vm.assume(address(token0) < address(token1));

        vm.expectRevert("token0 must be less than token1");
        poolManager.createPool(
            IPoolManager.CreatePoolParams({
                token0: address(token1),
                token1: address(token0),
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                sqrtPriceX96: SQRT_PRICE_X96
            })
        );
    }

    function _createPool() private returns (address pool) {
        pool = poolManager.createPool(
            IPoolManager.CreatePoolParams({
                token0: address(token0),
                token1: address(token1),
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                sqrtPriceX96: SQRT_PRICE_X96
            })
        );
    }

    function _mintLiquidity(address recipient, uint256 amount0Desired, uint256 amount1Desired)
        private
        returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        vm.startPrank(recipient);
        token0.approve(address(positionManager), type(uint256).max);
        token1.approve(address(positionManager), type(uint256).max);
        (positionId, liquidity, amount0, amount1) =
            positionManager.mint(_mintParams(recipient, amount0Desired, amount1Desired));
        vm.stopPrank();
    }

    function _mintParams(address recipient, uint256 amount0Desired, uint256 amount1Desired)
        private
        view
        returns (IPositionManager.MintParams memory)
    {
        return IPositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            index: 0,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            recipient: recipient,
            deadline: block.timestamp
        });
    }
}
