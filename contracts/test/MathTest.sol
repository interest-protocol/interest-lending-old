// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../lib/Math.sol";

contract MathTest {
    using Math for uint256;

    function wadMul(uint256 x, uint256 y) external pure returns (uint256) {
        return x.wadMul(y);
    }

    /**
     * @dev Function ensures that the return value keeps the right mantissa
     */
    function wadDiv(uint256 x, uint256 y) external pure returns (uint256) {
        return x.wadDiv(y);
    }

    /**
     * @dev Function ensures that the return value keeps the right mantissa
     */
    function rayMul(uint256 x, uint256 y) external pure returns (uint256) {
        return x.rayMul(y);
    }

    /**
     * @dev Function ensures that the return value keeps the right mantissa
     */
    function rayDiv(uint256 x, uint256 y) external pure returns (uint256) {
        return x.rayDiv(y);
    }

    function toWad(uint256 amount, uint8 decimals)
        external
        pure
        returns (uint256)
    {
        return amount.toWad(decimals);
    }

    function toRay(uint256 amount, uint8 decimals)
        external
        pure
        returns (uint256)
    {
        return amount.toRay(decimals);
    }

    function wadToRay(uint256 x) external pure returns (uint256) {
        return x.wadToRay();
    }

    /**
     *@notice This function always rounds down
     */
    function rayToWad(uint256 x) external pure returns (uint256) {
        return x.rayToWad();
    }

    /**
     * @dev Returns the smallest of two numbers.
     * Taken from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol
     */
    function min(uint256 a, uint256 b) external pure returns (uint256) {
        return a.min(b);
    }

    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) external pure returns (uint256) {
        return a.mulDiv(b, denominator);
    }
}
