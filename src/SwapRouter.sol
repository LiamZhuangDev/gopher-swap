// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../interfaces/ISwapRouter.sol";
import "../interfaces/IPoolManager.sol";
import "../interfaces/IPool.sol";

contract SwapRouter is ISwapRouter {
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function _parseRevertReason(bytes memory reason) private pure returns (int256, int256) {
        if (reason.length != 64) {
            if (reason.length < 68) {
                revert("Swap failed with unknown reason");
            }

            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (int256, int256));
    }

    function _swap(
        IPool pool,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes memory data
    ) private returns (int256 amount0, int256 amount1) {
        try pool.swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, data) returns (
            int256 amt0, int256 amt1
        ) {
            return (amt0, amt1);
        } catch (bytes memory reason) {
            _parseRevertReason(reason);
        }
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256 amountOut) {
        uint256 amountIn = params.amountIn;
        bool zeroForOne = params.tokenIn < params.tokenOut;

        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddr = poolManager.getPool(params.tokenIn, params.tokenOut, params.indexPath[i]);
            require(poolAddr != address(0), "Pool does not exist");

            IPool pool = IPool(poolAddr);
            bytes memory data = abi.encode(params.tokenIn, params.tokenOut, params.indexPath[i], params.recipient);

            (int256 amt0, int256 amt1) =
                _swap(pool, params.recipient, zeroForOne, int256(amountIn), params.sqrtPriceLimitX96, data);
            amountIn -= uint256(zeroForOne ? amt0 : amt1);
            amountOut += uint256(zeroForOne ? -amt1 : -amt0);

            if (amountIn == 0) {
                break;
            }
        }

        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");

        return amountOut;
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256 amountIn) {
        uint256 amountOut = params.amountOut;
        bool zeroForOne = params.tokenIn < params.tokenOut;

        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddr = poolManager.getPool(params.tokenIn, params.tokenOut, params.indexPath[i]);
            require(poolAddr != address(0), "Pool does not exist");

            IPool pool = IPool(poolAddr);
            bytes memory data = abi.encode(params.tokenIn, params.tokenOut, params.indexPath[i], params.recipient);

            (int256 amt0, int256 amt1) =
                _swap(pool, params.recipient, zeroForOne, -int256(amountOut), params.sqrtPriceLimitX96, data);
            amountOut -= uint256(zeroForOne ? -amt1 : -amt0);
            amountIn += uint256(zeroForOne ? amt0 : amt1);

            if (amountOut == 0) {
                break;
            }
        }

        require(amountIn <= params.amountInMaximum, "Excessive input amount");

        return amountIn;
    }

    function swapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        (address tokenIn, address tokenOut, uint32 index, address payer) =
            abi.decode(data, (address, address, uint32, address));
        address poolAddr = poolManager.getPool(tokenIn, tokenOut, index);
        require(msg.sender == poolAddr, "Unauthorized callback");

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        // if (payer == address(0)) {
        //     assembly {
        //         let ptr := mload(0x40)
        //         mstore(ptr, amount0Delta)
        //         mstore(add(ptr, 0x20), amount1Delta)
        //         revert(ptr, 0x40)
        //     }
        // }

        if (amountToPay > 0) {
            IERC20(tokenIn).transferFrom(payer, poolAddr, amountToPay);
        }
    }
}
