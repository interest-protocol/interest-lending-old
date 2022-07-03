//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./errors/ITokenMarketErrors.sol";

import "./interfaces/InterestRateModelInterface.sol";
import "./interfaces/ITokenMarketInterface.sol";
import "./interfaces/ManagerInterface.sol";

import "./lib/Math.sol";

import "./ITokenBase.sol";
import "hardhat/console.sol";

/**
 * @notice The term assets refers to the underlying token stored in this contract. The term shares refers to the token of this contract itself that is used to keep track of how many assets a user owns.
 */
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
     * @notice The asset held by this IToken.
     */
    address public asset;

    /**
     * @notice Contract that calculates the interest rate for borrowing and lending.
     */
    InterestRateModelInterface public interestRateModel;

    /**
     * @notice Percentage of the borrow rate kept by the protocol as reserves.
     */
    uint256 public reserveFactorMantissa;

    /**
     * @notice Sanity check to make sure the borrow rate is not very high (.0005% / block). Token from Compound.
     */
    uint256 internal constant RESERVE_FACTOR_MAX_MANTISSA = 0.3e18;

    /**
     * @notice Share of seized collateral that is added to reserves.
     */
    uint256 internal constant PROTOCOL_SEIZE_SHARE_MANTISSA = 0.28e18; //2.8%

    /**
     * @notice Total amount of reserves of the asset held in this market
     */
    uint256 internal _totalReserves;

    /**
     * @notice The initial exchangeRate when the totalSupply is 0 ADD 8
     */
    uint256 internal _initialExchangeRateMantissa;

    uint256 internal _totalReservesShares;

    /*///////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice It initializes the parent contract {ITokenBase}. Tt also sets the interest rate model.
     */
    //solhint-disable-next-line func-name-mixedcase
    function initialize(
        IERC20MetadataUpgradeable _asset,
        ManagerInterface _manager,
        InterestRateModelInterface _interestRateModel
    ) external initializer {
        __ITokenBase_init(_asset, _manager);

        asset = address(_asset);
        interestRateModel = _interestRateModel;
        reserveFactorMantissa = 0.2e18;

        unchecked {
            _initialExchangeRateMantissa = 10**(_asset.decimals() + 8) * 2;
        }
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
        (uint256 newTotalBorrows, , ) = _accrueView();
        return _getCash() + newTotalBorrows;
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
    function maxDeposit(address) external view returns (uint256) {
        ///@notice This market has no limit.
        return
            IERC20Upgradeable(asset).totalSupply() -
            convertToAssets(totalSupply);
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
    function maxMint(address) external view returns (uint256) {
        return
            convertToShares(IERC20Upgradeable(asset).totalSupply()) -
            totalSupply;
    }

    /// @notice Total number of underlying assets that can be
    /// withdrawn from the Vault by `owner`, where `owner`
    /// corresponds to the input parameter of a `withdraw` call.
    function maxWithdraw(address owner)
        external
        view
        returns (uint256 maxAssets)
    {
        maxAssets = convertToAssets(balanceOf[owner]).min(_getCash());
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
        maxShares = balanceOf[owner].min(convertToShares(_getCash()));
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
                address(this),
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
                address(this),
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
        uint256 supply = _totalSupply();
        iTokenBalance = balanceOf[account];

        (
            uint256 newTotalBorrows,
            uint256 newTotalReserves,
            uint256 newBorrowIndex
        ) = _accrueView();

        borrowBalance = _calculateBorrowBalanceOf(
            _loanTermsOf[account],
            newBorrowIndex
        );

        rate = _calculateExchangeRate(
            _getCash(),
            newTotalBorrows,
            newTotalReserves,
            supply
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
        (, , uint256 newBorrowIndex) = _accrueView();

        return _calculateBorrowBalanceOf(_loanTermsOf[account], newBorrowIndex);
    }

    /**
     * @notice It returns the current exchange rate
     */
    function exchangeRate() public view returns (uint256) {
        (uint256 newTotalBorrows, uint256 newTotalReserves, ) = _accrueView();

        return
            _calculateExchangeRate(
                _getCash(),
                newTotalBorrows,
                newTotalReserves,
                _totalSupply()
            );
    }

    /**
     *@notice Updates the loan data of this market.
     */
    function accrueMarket() external {
        _accrue();
    }

    /**
     * @notice Returns how many {asset} can be borrowed
     */
    function getCash() external view returns (uint256) {
        return _getCash();
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
            (shares = assets.wadDiv(_currentExchangeRate()))
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
            (assets = shares.wadMul(_currentExchangeRate())),
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
            (shares = assets.wadDiv(_currentExchangeRate()))
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
            (assets = shares.wadMul(_currentExchangeRate())),
            shares
        );
    }

    function borrow(uint256 assets, address receiver)
        external
        accrue
        nonReentrant
    {
        if (0 == assets) revert ITokenMarket__ZeroAmountNotAllowed();

        if (assets > _getCash()) revert ITokenMarket__NotEnoughCash();

        address sender = _msgSender();

        if (!manager.borrowAllowed(address(this), sender, receiver, assets))
            revert ITokenMarket__BorrowNotAllowed();

        LoanTerms memory terms = _loanTermsOf[sender];

        uint256 newAccountBorrow = _calculateBorrowBalanceOf(
            terms,
            _borrowIndex
        ) + assets;

        // Update in memory
        terms.principal = newAccountBorrow;
        terms.index = _borrowIndex;

        // Update storage
        _loanTermsOf[sender] = terms;
        _totalBorrows += assets;

        IERC20Upgradeable(asset).safeTransfer(receiver, assets);

        emit Borrow(sender, receiver, assets);
    }

    function repay(address borrower, uint256 assets)
        external
        accrue
        nonReentrant
    {
        _repay(_msgSender(), borrower, assets);
    }

    function liquidate(
        address borrower,
        uint256 assets,
        ITokenMarketInterface collateralMarket
    ) external accrue nonReentrant {
        address liquidator = _msgSender();

        if (liquidator == borrower) revert ITokenMarket__InvalidLiquidator();

        if (
            !manager.liquidateAllowed(
                address(collateralMarket),
                address(this),
                liquidator,
                borrower,
                assets
            )
        ) revert ITokenMarket__LiquidateNotAllowed();

        bool sameMarket = collateralMarket == this;

        // If it this market, we already accrued on the modifier
        if (!sameMarket) collateralMarket.accrueMarket();

        // Liquidator repays the loan
        uint256 repayAmount = _repay(liquidator, borrower, assets);

        uint256 seizeAmount = manager.liquidateCalculateSeizeTokens(
            address(collateralMarket),
            address(this),
            repayAmount
        );

        if (sameMarket) {
            _seize(
                address(collateralMarket),
                liquidator,
                borrower,
                seizeAmount
            );
        } else {
            collateralMarket.seize(liquidator, borrower, seizeAmount);
        }

        emit Liquidate(
            liquidator,
            borrower,
            repayAmount,
            seizeAmount,
            address(collateralMarket),
            address(this)
        );
    }

    function seize(
        address liquidator,
        address borrower,
        uint256 assets
    ) external nonReentrant {
        _seize(_msgSender(), liquidator, borrower, assets);
    }

    /**
     * @notice It allows anyone to donate reserves to the protocol.
     */
    function addReserves(uint256 amount) external accrue {
        if (amount == 0) revert ITokenMarket__ZeroAmountNotAllowed();

        address sender = _msgSender();

        IERC20Upgradeable(asset).safeTransferFrom(
            sender,
            address(this),
            amount
        );

        _totalReserves += amount;

        emit AddReserves(sender, amount, _totalReserves);
    }

    /*///////////////////////////////////////////////////////////////
                              Internal
    //////////////////////////////////////////////////////////////*/

    function _calculateBorrowBalanceOf(
        LoanTerms memory terms,
        uint256 borrowIndex
    ) internal pure returns (uint256) {
        return
            terms.principal == 0
                ? 0
                : (terms.principal * borrowIndex) / terms.index;
    }

    function _calculateExchangeRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 supply
    ) internal view returns (uint256) {
        return
            supply == 0
                ? _initialExchangeRateMantissa
                : (cash + borrows - reserves).wadMul(supply);
    }

    function _totalSupply() internal view returns (uint256) {
        unchecked {
            return totalSupply - _totalReservesShares;
        }
    }

    function _getCash() internal view returns (uint256) {
        return IERC20Upgradeable(asset).balanceOf(address(this));
    }

    function _safeBorrowRatePerBlock() internal view returns (uint256 rate) {
        if ((rate = borrowRatePerBlock()) >= BORROW_RATE_MAX_MANTISSA)
            revert ITokenMarket__InvalidBorrowRate();
    }

    function _currentExchangeRate() internal view returns (uint256) {
        return
            _calculateExchangeRate(
                _getCash(),
                _totalBorrows,
                _totalReserves,
                _totalSupply()
            );
    }

    function _deposit(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal {
        if (0 == shares || 0 == assets)
            revert ITokenMarket__ZeroAmountNotAllowed();

        address sender = _msgSender();

        // Make sure minting is allowed
        if (!manager.depositAllowed(address(this), sender, receiver, assets))
            revert ITokenMarket__DepositNotAllowed();

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
        if (0 != assets || 0 != shares)
            revert ITokenMarket__ZeroAmountNotAllowed();

        if (!manager.withdrawAllowed(address(this), owner, receiver, assets))
            revert ITokenMarket__WithdrawNotAllowed();

        if (assets > _getCash()) revert ITokenMarket__NotEnoughCash();

        address sender = _msgSender();

        if (sender != owner) {
            _spendAllowance(owner, sender, shares);
        }

        _burn(owner, shares);

        IERC20Upgradeable(asset).safeTransfer(receiver, assets);

        emit Withdraw(sender, receiver, assets, shares);
    }

    function _repay(
        address sender,
        address borrower,
        uint256 assets
    ) internal returns (uint256 safeRepayAmount) {
        if (0 == assets) revert ITokenMarket__ZeroAmountNotAllowed();

        if (!manager.repayAllowed(address(this), sender, borrower, assets))
            revert ITokenMarket__RepayNotAllowed();

        LoanTerms memory terms = _loanTermsOf[borrower];

        uint256 accountBorrow = _calculateBorrowBalanceOf(terms, _borrowIndex);

        safeRepayAmount = assets > accountBorrow ? accountBorrow : assets;

        // Want to get the tokens before updating the state
        IERC20Upgradeable(asset).safeTransferFrom(
            sender,
            address(this),
            assets
        );

        // Update memory
        terms.principal = accountBorrow - safeRepayAmount;
        terms.index = _borrowIndex;

        // Update storage
        _loanTermsOf[borrower] = terms;
        _totalBorrows -= safeRepayAmount;

        emit Repay(sender, borrower, safeRepayAmount);
    }

    function _seize(
        address borrowMarket,
        address liquidator,
        address borrower,
        uint256 assets
    ) internal {
        if (
            !manager.seizeAllowed(
                address(this),
                borrowMarket,
                liquidator,
                borrower,
                assets
            )
        ) revert ITokenMarket__SeizeNotAllowed();

        uint256 protocolAmount = assets.wadMul(PROTOCOL_SEIZE_SHARE_MANTISSA);
        uint256 liquidatorAmount = assets - protocolAmount;

        uint256 reserves = _totalReserves;

        // Only function {liquidate} can call this function and accrued has been called already.
        uint256 rate = _calculateExchangeRate(
            _getCash(),
            _totalBorrows,
            reserves,
            _totalSupply()
        );

        _totalReserves = reserves + protocolAmount;
        _totalReservesShares += protocolAmount.wadDiv(rate);

        // Seize tokens from `borrower`
        _burn(borrower, assets);
        // Reward the liquidator
        _mint(liquidator, liquidatorAmount);
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
        (uint256 prevTotalborrow, uint256 prevBorrowIndex) = (
            _totalBorrows,
            _borrowIndex
        );

        uint256 interest = blocksDelta.uncheckedMul(_safeBorrowRatePerBlock());

        uint256 interestAccumulated = interest.wadMul(prevTotalborrow);

        return (
            interestAccumulated + prevTotalborrow,
            interestAccumulated.wadMul(reserveFactorMantissa) + _totalReserves,
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

    /*///////////////////////////////////////////////////////////////
                             OWNER ONLY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice It updates the manager of this contract.
     */
    function updateManager(ManagerInterface _manager)
        external
        accrue
        onlyOwner
    {
        if (address(_manager) == address(0))
            revert ITokenMarket__ZeroAddressNotAllowed();

        emit NewManager(address(manager), address(_manager));
        manager = _manager;
    }

    /**
     *@notice It updates the % of the borrow rate that is kept by the protocol.
     */
    function updateReserveFactor(uint256 factor) external accrue onlyOwner {
        if (factor >= RESERVE_FACTOR_MAX_MANTISSA)
            revert ITokenMarket__ReserveFactorOutOfBounds();

        emit NewReserveFactor(reserveFactorMantissa, factor);

        reserveFactorMantissa = factor;
    }

    /**
     *@notice It allows the {owner} to remove reserves from the protocol.
     */
    function removeReserves(uint256 amount) external accrue onlyOwner {
        if (amount == 0) revert ITokenMarket__ZeroAmountNotAllowed();

        if (amount > _getCash()) revert ITokenMarket__NotEnoughCash();

        uint256 reserves = _totalReserves;

        if (amount > reserves) revert ITokenMarket__NotEnoughReserves();

        reserves -= amount;

        _totalReserves = reserves;

        address sender = _msgSender();

        IERC20Upgradeable(asset).safeTransfer(sender, amount);

        emit AddReserves(sender, amount, reserves);
    }
}
