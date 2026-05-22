// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../interfaces/IPositionManager.sol";
import "../interfaces/IPoolManager.sol";
import "../interfaces/IPool.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityAmounts.sol";
import "../libraries/FullMath.sol";
import "../libraries/FixedPoint128.sol";

contract PositionManager is IPositionManager, ERC721 {
    IPoolManager public immutable poolManager;

    uint176 private _nextTokenId = 1;

    constructor(address _poolManager) ERC721("GopherSwapPosition", "GSP") {
        poolManager = IPoolManager(_poolManager);
    }

    mapping(uint256 => PositionInfo) public positions;

    function getPositions() external view override returns (PositionInfo[] memory) {
        PositionInfo[] memory ret = new PositionInfo[](_nextTokenId - 1);
        for (uint32 i = 0; i < _nextTokenId - 1; i++) {
            ret[i] = positions[i + 1];
        }
        return ret;
    }

    function mint(MintParams calldata params)
        external
        payable
        override
        returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address _pool = poolManager.getPool(params.token0, params.token1, params.index);
        require(_pool != address(0), "Pool does not exist");
        IPool pool = IPool(_pool);

        {
            uint160 sqrtPriceX96 = pool.sqrtPriceX96();
            uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(pool.tickLower());
            uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(pool.tickUpper());

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, params.amount0Desired, params.amount1Desired
            );
        }

        bytes memory data = abi.encode(params.token0, params.token1, params.index, msg.sender);
        (amount0, amount1) = pool.mint(address(this), liquidity, data);

        _mint(params.recipient, (positionId = _nextTokenId++));
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) = pool.getPosition(address(this));

        PositionInfo storage position = positions[positionId];
        position.id = positionId;
        position.owner = params.recipient;
        position.token0 = params.token0;
        position.token1 = params.token1;
        position.index = params.index;
        position.fee = pool.fee();
        position.liquidity = liquidity;
        position.tickLower = pool.tickLower();
        position.tickUpper = pool.tickUpper();
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
    }

    modifier isAuthorized(uint256 tokenId) {
        address owner = ERC721.ownerOf(tokenId);
        require(_isAuthorized(owner, msg.sender, tokenId), "Not token owner or approved");
        _;
    }

    function burn(uint256 positionId)
        external
        override
        isAuthorized(positionId)
        returns (uint256 amount0, uint256 amount1)
    {
        PositionInfo storage position = positions[positionId];
        address _pool = poolManager.getPool(position.token0, position.token1, position.index);
        require(_pool != address(0), "Pool does not exist");

        IPool pool = IPool(_pool);
        uint128 liquidity = position.liquidity;
        require(liquidity > 0, "No liquidity to burn");

        (amount0, amount1) = pool.burn(liquidity);

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) = pool.getPosition(address(this));
        position.tokensOwed0 += uint128(amount0)
        + uint128(
            FullMath.mulDiv(feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128)
        );
        position.tokensOwed1 += uint128(amount1)
        + uint128(
            FullMath.mulDiv(feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128)
        );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity = 0;
    }

    function collect(uint256 positionId, address recipient)
        external
        override
        isAuthorized(positionId)
        returns (uint256 amount0, uint256 amount1)
    {
        PositionInfo storage position = positions[positionId];
        address _pool = poolManager.getPool(position.token0, position.token1, position.index);
        require(_pool != address(0), "Pool does not exist");

        IPool pool = IPool(_pool);
        (amount0, amount1) = pool.collect(recipient, position.tokensOwed0, position.tokensOwed1);

        position.tokensOwed0 = 0;
        position.tokensOwed1 = 0;
        if (position.liquidity == 0) {
            _burn(positionId);
        }
    }

    function mintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
        (address token0, address token1, uint32 index, address payer) =
            abi.decode(data, (address, address, uint32, address));
        address _pool = poolManager.getPool(token0, token1, index);
        require(msg.sender == _pool, "Unauthorized callback");

        if (amount0 > 0) {
            IERC20(token0).transferFrom(payer, msg.sender, amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).transferFrom(payer, msg.sender, amount1);
        }
    }
}
