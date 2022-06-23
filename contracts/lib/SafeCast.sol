// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

library SafeCastLib {
    function toUint128(uint256 x) internal pure returns (uint128 y) {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            if iszero(lt(x, shl(128, 1))) {
                revert(0, 0)
            }
            y := x
        }
    }

    function toUint64(uint256 x) internal pure returns (uint64 y) {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            if iszero(lt(x, shl(64, 1))) {
                revert(0, 0)
            }
            y := x
        }
    }

    function toUint256(int256 x) internal pure returns (uint256 y) {
        //solhint-disable reason-string
        require(x >= 0);
        y = uint256(x);
    }
}
