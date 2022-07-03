// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ITokenBaseERC20ReentrancyTransfer is ERC20 {
    ERC20 public market;

    //solhint-disable-next-line no-empty-blocks
    constructor(
        ERC20 _market,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        market = _market;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
        market.transfer(address(this), 0);
    }
}

contract ITokenBaseERC20ReentrancyTransferFrom is ERC20 {
    ERC20 public market;

    //solhint-disable-next-line no-empty-blocks
    constructor(
        ERC20 _market,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        market = _market;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
        market.transferFrom(address(this), address(this), 0);
    }
}
