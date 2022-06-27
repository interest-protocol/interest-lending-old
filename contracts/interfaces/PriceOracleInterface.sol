//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@interest-protocol/dex/interfaces/IPair.sol";

import {UnderlyingType} from "../lib/DataTypes.sol";

interface PriceOracleInterface {
    function getUnderlyingPrice(
        address token,
        uint256 amount,
        UnderlyingType underlyingType
    ) external view returns (uint256);
}
