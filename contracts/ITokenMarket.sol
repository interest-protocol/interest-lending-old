//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/InterestRateModelInterface.sol";
import "./interfaces/ITokenMarketInterface.sol";
import "./interfaces/ManagerInterface.sol";
import "./interfaces/PriceOracleInterface.sol";

import {ZeroAmountNotAllowed, DepositNotAllowed, WithdrawNotAllowed, NotEnoughCash, InvalidBorrowRate} from "./lib/Errors.sol";
import "./lib/Math.sol";

import "./ITokenBase.sol";

contract ITokenMarket is Initializable, ITokenBase, ITokenMarketInterface {
    /*///////////////////////////////////////////////////////////////
                              LIBS
    //////////////////////////////////////////////////////////////*/

    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*///////////////////////////////////////////////////////////////
                              STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract that calculates the interest rate for borrowing and lending.
     */
    InterestRateModelInterface public interestRateModel;

    /*///////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice It initializes the parent contract {ITokenBase}. Tt also sets the interest rate model.
     */
    //solhint-disable-next-line func-name-mixedcase
    function __ITokenMarket_ini(
        IERC20MetadataUpgradeable _asset,
        ManagerInterface _manager,
        PriceOracleInterface _oracle,
        InterestRateModelInterface _interestRateModel
    ) external initializer {
        __ITokenBase_init(_asset, _manager, _oracle);
        interestRateModel = _interestRateModel;
    }

    /*///////////////////////////////////////////////////////////////
                            MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier accrue() {
        _accrue();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            IERC4626
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the amount of {asset} managed by this contract.
     */
    function totalAssets() external view returns (uint256) {
        (uint256 newTotalBorrows, uint256 newTotalReserves, ) = _accrueLogic(
            _blocksDelta()
        );
        return _getCash() + newTotalBorrows + newTotalReserves;
    }

    /// @notice The amount of shares that the vault would
    /// exchange for the amount of assets provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToShares(uint256 assets)
        public
        view
        returns (uint256 shares)
    {
        shares = assets.wadDiv(exchangeRate());
    }

    /// @notice The amount of assets that the vault would
    /// exchange for the amount of shares provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToAssets(uint256 shares)
        public
        view
        returns (uint256 assets)
    {
        assets = shares.wadMul(exchangeRate());
    }

    /// @notice Total number of underlying assets that can
    /// be deposited by `owner` into the Vault, where `owner`
    /// corresponds to the input parameter `receiver` of a
    /// `deposit` call.
    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their deposit at the current block, given
    /// current on-chain conditions.
    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares)
    {
        shares = convertToShares(assets);
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their mint at the current block, given
    /// current on-chain conditions.
    function previewMint(uint256 shares)
        external
        view
        returns (uint256 assets)
    {
        assets = convertToAssets(shares);
    }

    /// @notice Total number of underlying shares that can be minted
    /// for `owner`, where `owner` corresponds to the input
    /// parameter `receiver` of a `mint` call.
    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Total number of underlying assets that can be
    /// withdrawn from the Vault by `owner`, where `owner`
    /// corresponds to the input parameter of a `withdraw` call.
    function maxWithdraw(address owner)
        external
        view
        returns (uint256 maxAssets)
    {
        maxAssets = convertToAssets(balanceOf(owner)).min(_getCash());
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their withdrawal at the current block,
    /// given current on-chain conditions.
    function previewWithdraw(uint256 assets)
        external
        view
        returns (uint256 shares)
    {
        shares = convertToShares(assets).min(convertToShares(_getCash()));
    }

    /// @notice Total number of underlying shares that can be
    /// redeemed from the Vault by `owner`, where `owner` corresponds
    /// to the input parameter of a `redeem` call.
    function maxRedeem(address owner)
        external
        view
        returns (uint256 maxShares)
    {
        maxShares = balanceOf(owner).min(convertToShares(_getCash()));
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their redeemption at the current block,
    /// given current on-chain conditions.
    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 assets)
    {
        assets = convertToAssets(shares).min(_getCash());
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current per-block borrow interest rate for this cToken
     * @return The borrow interest rate per block, scaled by 1e18
     */
    function borrowRatePerBlock() public view returns (uint256) {
        return
            interestRateModel.getBorrowRatePerBlock(
                asset,
                _getCash(),
                _totalBorrows,
                _totalReserves
            );
    }

    /**
     * @notice Returns the current per-block supply interest rate for this cToken
     * @return The supply interest rate per block, scaled by 1e18
     */
    function supplyRatePerBlock() public view returns (uint256) {
        return
            interestRateModel.getSupplyRatePerBlock(
                asset,
                _getCash(),
                _totalBorrows,
                _totalReserves,
                reserveFactorMantissa
            );
    }

    /**
     * @dev Returns key data about an `account` in order for the {manager} to calculate its solvency.
     *
     * @param account The address of a user
     */
    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256 iTokenBalance,
            uint256 borrowBalance,
            uint256 rate // exchangeRate
        )
    {
        uint256 _totalSupply = totalSupply();
        iTokenBalance = balanceOf(account);

        (
            uint256 newTotalBorrows,
            uint256 newTotalReserves,
            uint256 newBorrowIndex
        ) = _accrueView();

        LoanTerms memory terms = _loanTermsOf[account];

        borrowBalance = terms.principal == 0
            ? 0
            : (terms.principal * newBorrowIndex) / terms.index;

        rate = _totalSupply == 0
            ? _initialExchangeRateMantissa
            : (_getCash() + newTotalBorrows - newTotalReserves).wadMul(
                _totalSupply
            );
    }

    /**
     * @notice It returns the key information related to the global loan
     */
    function loanData()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return _accrueView();
    }

    /**
     * @notice It returns the current amout of underlying an `account` is borrowing.
     */
    function borrowBalanceOf(address account) external view returns (uint256) {
        LoanTerms memory terms = _loanTermsOf[account];

        if (terms.principal == 0) return 0;

        (, , uint256 newBorrowIndex) = _accrueView();

        return (terms.principal * newBorrowIndex) / terms.index;
    }

    /**
     * @notice It returns the current exchange rate
     */
    function exchangeRate() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return _initialExchangeRateMantissa;

        (uint256 newTotalBorrows, uint256 newTotalReserves, ) = _accrueView();

        return
            (_getCash() + newTotalBorrows - newTotalReserves).wadMul(
                _totalSupply
            );
    }

    /*///////////////////////////////////////////////////////////////
       IMPURE FUNCTIONS - Must have accrue + nonReentrant modifiers
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows a {msg.sender} to deposit assets. Follows {IERC4626}
     *
     * @dev This function calls {_accrue} before its execution and has the {nonReentrant modifier}
     */
    function deposit(uint256 assets, address receiver)
        external
        accrue
        nonReentrant
        returns (uint256 shares)
    {
        _deposit(
            receiver,
            assets,
            (shares = assets.wadDiv(_unsafeExchangeRate()))
        );
    }

    /**
     * @notice Allows a {msg.sender} to deposit assets. Follows {IERC4626}
     *
     * @dev This function calls {_accrue} before its execution and has the {nonReentrant modifier}
     */
    function mint(uint256 shares, address receiver)
        external
        accrue
        nonReentrant
        returns (uint256 assets)
    {
        _deposit(
            receiver,
            (assets = shares.wadMul(_unsafeExchangeRate())),
            shares
        );
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external accrue nonReentrant returns (uint256 shares) {
        _withdraw(
            receiver,
            owner,
            assets,
            (shares = assets.wadDiv(_unsafeExchangeRate()))
        );
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external accrue nonReentrant returns (uint256 assets) {
        _withdraw(
            receiver,
            owner,
            (assets = shares.wadMul(_unsafeExchangeRate())),
            shares
        );
    }

    /*///////////////////////////////////////////////////////////////
                              Internal
    //////////////////////////////////////////////////////////////*/

    function _getCash() internal view returns (uint256) {
        return IERC20Upgradeable(asset).balanceOf(address(this));
    }

    function _safeBorrowRatePerBlock() internal view returns (uint256 rate) {
        if ((rate = borrowRatePerBlock()) >= BORROW_RATE_MAX_MANTISSA)
            revert InvalidBorrowRate();
    }

    function _blocksDelta() internal view returns (uint256) {
        unchecked {
            return block.number - accrualBlockNumber;
        }
    }

    function _unsafeExchangeRate() internal view returns (uint256) {
        uint256 _totalSupply = totalSupply();

        return
            _totalSupply == 0
                ? _initialExchangeRateMantissa
                : (_getCash() + _totalBorrows - _totalReserves).wadMul(
                    _totalSupply
                );
    }

    function _deposit(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal {
        if (0 > shares || 0 > assets) revert ZeroAmountNotAllowed();

        address sender = _msgSender();

        // Make sure minting is allowed
        if (!manager.depositAllowed(address(this), sender, receiver, assets))
            revert DepositNotAllowed();

        // Get assets from {msg.sender}
        IERC20Upgradeable(asset).safeTransferFrom(
            sender,
            address(this),
            assets
        );

        _mint(receiver, shares);

        emit Deposit(sender, receiver, assets, shares);
    }

    function _withdraw(
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal {
        if (0 > assets || 0 > shares) revert ZeroAmountNotAllowed();

        if (!manager.withdrawAllowed(address(this), owner, receiver, assets))
            revert WithdrawNotAllowed();

        if (assets > _getCash()) revert NotEnoughCash();

        address sender = _msgSender();

        if (sender != owner) {
            _spendAllowance(owner, sender, shares);
        }

        _burn(owner, shares);

        IERC20Upgradeable(asset).safeTransfer(receiver, assets);

        emit Withdraw(sender, receiver, assets, shares);
    }

    /**
     * @notice This function applies a simple interest rate to the following state  {totalBorrows}, {totalReserves}, {index}.
     *
     * @param blocksDelta The number of blocks since the last accrual;
     */
    function _accrueLogic(uint256 blocksDelta)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 prevTotalborrow,
            uint256 prevReserves,
            uint256 prevBorrowIndex
        ) = (_totalBorrows, _totalReserves, _borrowIndex);

        uint256 interest = blocksDelta * _safeBorrowRatePerBlock();
        uint256 interestAccumulated = interest.wadMul(prevTotalborrow);

        return (
            interestAccumulated + prevTotalborrow,
            interestAccumulated.wadMul(reserveFactorMantissa) + prevReserves,
            interest.wadMul(prevBorrowIndex) + prevBorrowIndex
        );
    }

    /**
     * @notice This function applies a simple interest rate to the following state  {totalBorrows}, {totalReserves}, {index}.
     * @return uint256, uint256, uint256 The updated totalBorrows, totalReserves and index
     */
    function _accrueView()
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 blocksDelta = _blocksDelta();
        return
            blocksDelta == 0
                ? (_totalBorrows, _totalReserves, _borrowIndex)
                : _accrueLogic(blocksDelta);
    }

    /**
     * @notice This function updates the {totalBorrows}, {totalReserves}, {index} and {accrualBlockNumber} by calculating a simple interest rate to the loan.
     */
    function _accrue() internal {
        uint256 blocksDelta = _blocksDelta();

        // Total Borrow is up to date
        if (blocksDelta == 0) return;

        (uint256 borrows, uint256 reserves, uint256 index) = _accrueLogic(
            blocksDelta
        );

        accrualBlockNumber = block.number;
        _totalBorrows = borrows;
        _totalReserves = reserves;
        _borrowIndex = index;

        emit Accrue(borrows, reserves, index);
    }
}
