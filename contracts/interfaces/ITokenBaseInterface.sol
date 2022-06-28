//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./IERC4626.sol";

interface ITokenBaseInterface is IERC4626 {
    event NewManager(address indexed old, address indexed updated);

    event NewReserveFactor(uint256 indexed old, uint256 indexed updated);
}
