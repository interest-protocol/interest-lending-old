// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../ITokenBase.sol";

interface IERC20Mintable {
    function mint(address account, uint256 amount) external;
}

contract TestITokenBase is Initializable, ITokenBase {
    function initialize(
        IERC20MetadataUpgradeable _asset,
        ManagerInterface _manager
    ) external initializer {
        __ITokenBase_init(_asset, _manager);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function reentrancyMint(IERC20Mintable asset) external nonReentrant {
        asset.mint(address(this), 10 ether);
    }
}
