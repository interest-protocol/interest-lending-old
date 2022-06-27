//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ManagerInterface {
    function transferAllowed(
        address iToken,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function depositAllowed(
        address,
        address,
        uint256
    ) external returns (bool);

    function withdrawAllowed(
        address,
        address,
        uint256
    ) external returns (bool);
}
