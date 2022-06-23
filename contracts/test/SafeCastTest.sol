// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../lib/SafeCast.sol";

contract SafeCastTest {
    using SafeCastLib for *;

    function toUint128(uint256 x) external pure returns (uint128) {
        return x.toUint128();
    }

    function toUint64(uint256 x) external pure returns (uint64) {
        return x.toUint64();
    }

    function toUint256(int256 x) external pure returns (uint256) {
        return x.toUint256();
    }
}
