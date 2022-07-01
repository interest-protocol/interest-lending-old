//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./IERC4626.sol";

interface ITokenMarketInterface is IERC4626 {
    event Accrue(
        uint256 totalBorrows,
        uint256 totalReserves,
        uint256 borrowIndex
    );

    event Borrow(
        address indexed borrower,
        address indexed receiver,
        uint256 assets
    );

    event Repay(
        address indexed payer,
        address indexed borrower,
        uint256 assets
    );

    event Liquidate(
        address indexed liquidator,
        address indexed borrower,
        uint256 repayAmount,
        uint256 seizedAmount,
        address indexed collateralMarket,
        address borrowMarket
    );

    event AddReserves(
        address indexed donor,
        uint256 amount,
        uint256 newReserves
    );

    function getCash() external view returns (uint256);

    function seize(
        address liquidator,
        address borrower,
        uint256 assets
    ) external;

    function accrueMarket() external;
}
