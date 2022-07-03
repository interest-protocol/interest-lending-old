// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../TestITokenBase.sol";

contract TestITokenBaseV2 is TestITokenBase {
    function version() external pure returns (string memory) {
        return "V2";
    }
}
