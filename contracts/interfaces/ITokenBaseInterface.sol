//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

interface ITokenBaseInterface is IERC20Upgradeable {
    event NewManager(address indexed old, address indexed updated);

    event NewReserveFactor(uint256 indexed old, uint256 indexed updated);
}
