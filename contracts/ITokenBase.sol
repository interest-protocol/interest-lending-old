//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/interfaces/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./errors/ITokenBaseErrors.sol";

import "./interfaces/ITokenBaseInterface.sol";
import "./interfaces/ManagerInterface.sol";

import {LoanTerms} from "./lib/DataTypes.sol";

//solhint-disable var-name-mixedcase
//solhint-disable max-states-count
contract ITokenBase is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ITokenBaseInterface
{
    /*//////////////////////////////////////////////////////////////
                              ERC20 METADATA
    //////////////////////////////////////////////////////////////*/

    string public name;
    string public symbol;
    //solhint-disable-next-line const-name-snakecase
    uint8 public constant decimals = 8;

    /*//////////////////////////////////////////////////////////////
                              ERC20 State
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                              EIP-2612 State
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant _TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    bytes32 private _CACHED_DOMAIN_SEPARATOR;
    uint256 private _CACHED_CHAIN_ID;
    bytes32 private _HASHED_NAME;
    bytes32 private _HASHED_VERSION;

    mapping(address => uint256) public nonces;

    /*///////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sanity check to make sure the borrow rate is not very high (.0005% / block). Token from Compound.
     */
    uint256 internal constant BORROW_RATE_MAX_MANTISSA = 0.0005e16;

    /**
     * @notice Contract which manages interaction between I Tokens.
     */
    ManagerInterface public manager;

    /**
     * @notice Block number that interest was last accrued at
     */

    uint256 public accrualBlockNumber;

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
        ManagerInterface _manager
    ) internal onlyInitializing {
        // Sets the owner to the {msg.sender}
        __Ownable_init();

        string memory _name = string(abi.encodePacked("I", _asset.name()));

        // Global state
        name = _name;
        symbol = string(abi.encodePacked("i", _asset.symbol()));

        manager = _manager;
        accrualBlockNumber = block.number;

        _borrowIndex = 1 ether;
        _status = 1;

        _HASHED_NAME = keccak256(bytes(_name));
        _HASHED_VERSION = keccak256(bytes("1"));
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator(
            _TYPE_HASH,
            _HASHED_NAME,
            _HASHED_VERSION
        );
    }

    /*//////////////////////////////////////////////////////////////
                        NonReentrancy Modifier
    //////////////////////////////////////////////////////////////*/

    // Basic nonreentrancy guard
    uint256 private _status;
    modifier nonReentrant() {
        if (_status != 1) revert ITokenBase__Reentrancy();
        _status = 2;
        _;
        _status = 1;
    }

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 Logic
    //////////////////////////////////////////////////////////////*/

    ///@notice Returns the DOMAIN_SEPARATOR
    //solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == _CACHED_CHAIN_ID
                ? _CACHED_DOMAIN_SEPARATOR
                : _computeDomainSeparator(
                    _TYPE_HASH,
                    _HASHED_NAME,
                    _HASHED_VERSION
                );
    }

    ///@notice Makes a new DOMAIN_SEPARATOR if the chainid changes.
    function _computeDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    typeHash,
                    nameHash,
                    versionHash,
                    block.chainid,
                    address(this)
                )
            );
    }

    // standard permit function
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        //solhint-disable-next-line not-rely-on-time
        if (block.timestamp > deadline) revert ITokenBase__PermitExpired();
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            owner,
                            spender,
                            value,
                            nonces[owner]++,
                            deadline
                        )
                    )
                )
            );

            address recoveredAddress = ecrecover(digest, v, r, s);

            if (recoveredAddress == address(0) || recoveredAddress != owner)
                revert ITokenBase__InvalidSignature();

            allowance[owner][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 Logic
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev ERC20 standard approve.
     *
     * @param spender Address that will be allowed to spend in behalf o the `msg.sender`
     * @param amount The number of tokens the `spender` can spend from the `msg.sender`
     * @return bool true if successful
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

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
    ) external nonReentrant returns (bool) {
        if (!manager.transferAllowed(address(this), from, to, amount))
            revert ITokenBase__TransferNotAllowed();

        _spendAllowance(from, msg.sender, amount);

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /**
     * @notice Standard {ERC20} {transfer} with additional checks.
     * We verify that the `from` and `to` are different accounts and that the  manager allows this market tokens to be transferred.
     *
     * @dev The {nonReentrant} modifier is applied to prevent reentrancy attacks.
     */
    function transfer(address to, uint256 amount)
        external
        nonReentrant
        returns (bool)
    {
        address from = _msgSender();

        if (!manager.transferAllowed(address(this), from, to, amount))
            revert ITokenBase__TransferNotAllowed();

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _blocksDelta() internal view returns (uint256) {
        unchecked {
            return block.number - accrualBlockNumber;
        }
    }

    /**
     * @notice Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowed = allowance[owner][spender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[owner][spender] = allowed - amount;
    }

    /**
     * @notice Creates new tokens for an account.
     */
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Deploys tokens from an account.
     */
    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;

        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
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
