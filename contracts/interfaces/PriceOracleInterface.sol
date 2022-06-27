//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@interest-protocol/dex/interfaces/IPair.sol";

import {AssetType} from "../lib/DataTypes.sol";

interface PriceOracleInterface {
    function getAssetPrice(
        address token,
        uint256 amount,
        AssetType assetType
    ) external view returns (uint256);
}
