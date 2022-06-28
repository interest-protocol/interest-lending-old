//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/interfaces/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IERC4626.sol";
import "./interfaces/ManagerInterface.sol";
import "./interfaces/PriceOracleInterface.sol";

import {LoanTerms} from "./lib/DataTypes.sol";
import {InvalidReceiver, TransferNotAllowed} from "./lib/Errors.sol";

abstract contract ITokenBase is
    Initializable,
    ReentrancyGuardUpgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IERC4626
{
    /*///////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sanity check to make sure the borrow rate is not very high (.0005% / block). Token from Compound.
     */
    uint256 internal constant BORROW_RATE_MAX_MANTISSA = 0.0005e16;

    /**
     * @notice Share of seized collateral that is added to reserves.
     */
    uint256 internal constant PROTOCOL_SEIZE_SHARE_MANTISSA = 0.28e18; //2.8%

    /**
     * @notice Contract which manages interaction between I Tokens.
     */
    ManagerInterface public manager;

    /**
     * @notice Contrac that calculates the price of the asset asset in USD
     */
    PriceOracleInterface public oracle;

    /**
     * @notice The asset held by this IToken.
     */
    address public asset;
    /**
     * @notice Block number that interest was last accrued at
     */
    uint256 public accrualBlockNumber;

    /**
     * @notice Percentage of the borrow rate kept by the protocol as reserves.
     */
    uint256 public reserveFactorMantissa;

    /**
     * @notice Maps an account to it's loan terms
     */
    mapping(address => LoanTerms) internal _loanTermsOf;

    /**
     * @notice Accumulator of the total interest rate earned by this contract since day 0
     */
    uint256 internal _borrowIndex;

    /**
     * @notice Total amount of outstanding borrows of the asset in this market
     */
    uint256 internal _totalBorrows;

    /**
     * @notice Total amount of reserves of the asset held in this market
     */
    uint256 internal _totalReserves;

    /**
     * @notice The initial exchangeRate when the totalSupply is 0 ADD 8
     */
    uint256 internal _initialExchangeRateMantissa;

    /*///////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initializes the following contracts:
     * - {EIP712} domain separator
     * - {ERC20} name and symbol
     * - Sets the owner to the caller of this function
     */
    //solhint-disable-next-line func-name-mixedcase
    function __ITokenBase_init(
        IERC20MetadataUpgradeable _asset,
        ManagerInterface _manager,
        PriceOracleInterface _oracle
    ) internal onlyInitializing {
        // Sets the name to "IToken USD Coin"
        string memory _name = string(
            abi.encodePacked("IToken ", _asset.name())
        );

        __ERC20Permit_init(_name);

        // Sets the symbol to "iUSDC"
        __ERC20_init(_name, string(abi.encodePacked("i", _asset.symbol())));

        // Sets the owner to the {msg.sender}
        __Ownable_init();

        __ReentrancyGuard_init();

        // Global state
        asset = address(_asset);
        manager = _manager;
        oracle = _oracle;
        accrualBlockNumber = block.number;
        _borrowIndex = 1 ether;

        unchecked {
            _initialExchangeRateMantissa = 10**(_asset.decimals() + 8) * 2;
        }
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice {ERC20} decimal function overriden to 8.
     */
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /*///////////////////////////////////////////////////////////////
                              ERC20 modified
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Standard {ERC20} {transferFrom} with additional checks.
     * We verify that the `from` and `to` are different accounts and that the  manager allows this market tokens to be transferred.
     *
     * @dev The {nonReentrant} modifier is applied to prevent reentrancy attacks.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        if (!manager.transferAllowed(address(this), from, to, amount))
            revert TransferNotAllowed();

        if (from == to) revert InvalidReceiver(to);

        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @notice Standard {ERC20} {transfer} with additional checks.
     * We verify that the `from` and `to` are different accounts and that the  manager allows this market tokens to be transferred.
     *
     * @dev The {nonReentrant} modifier is applied to prevent reentrancy attacks.
     */
    function transfer(address to, uint256 amount)
        public
        override
        nonReentrant
        returns (bool)
    {
        address from = _msgSender();

        if (!manager.transferAllowed(address(this), from, to, amount))
            revert TransferNotAllowed();

        if (from == to) revert InvalidReceiver(to);

        _transfer(from, to, amount);
        return true;
    }

    /*///////////////////////////////////////////////////////////////
                              OWNER ONLY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the owner to update the {reserveFactorMantissa}
     */
    function updateReserveFactorMantissa(uint256 factor) external onlyOwner {
        reserveFactorMantissa = factor;
    }

    /**
     * @notice Allows the owner to update the {reserveFactorMantissa}
     */
    function updateManager(ManagerInterface _manager) external onlyOwner {
        manager = _manager;
    }

    /*///////////////////////////////////////////////////////////////
                              HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev A hook to guard the address that can update the implementation of this contract. It must be the owner.
     */
    function _authorizeUpgrade(address)
        internal
        view
        override
        onlyOwner
    //solhint-disable-next-line no-empty-blocks
    {

    }
}
