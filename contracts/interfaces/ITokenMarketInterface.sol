//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ITokenMarketInterface {
    event Accrue(
        uint256 totalBorrows,
        uint256 totalReserves,
        uint256 borrowIndex
    );
}
