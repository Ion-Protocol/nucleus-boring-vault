// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { WETH } from "@solmate/tokens/WETH.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { BeforeTransferHook } from "src/interfaces/BeforeTransferHook.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { AuthOwnable2Step } from "src/helper/AuthOwnable2Step.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";

/**
 * @title TellerWithMultiAssetSupport
 * @custom:security-contact security@molecularlabs.io
 */
contract TellerWithMultiAssetSupport is AuthOwnable2Step, BeforeTransferHook, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for WETH;

    // ========================================= CONSTANTS =========================================

    /**
     * @notice The maximum possible share lock period.
     */
    uint256 internal constant MAX_SHARE_LOCK_PERIOD = 3 days;

    // ========================================= STATE =========================================

    /**
     * @notice Mapping withdrawERC20s to an isSupported bool.
     */
    mapping(ERC20 => bool) public isWithdrawSupported;

    /**
     * @notice The deposit nonce used to map to a deposit hash.
     */
    uint96 public depositNonce = 1;

    /**
     * @notice After deposits, shares are locked to the msg.sender's address
     *         for `shareLockPeriod`.
     * @dev During this time all transfers from msg.sender will revert, and
     *      deposits are refundable.
     */
    uint64 public shareLockPeriod;

    /**
     * @notice Used to pause calls to `deposit` and `depositWithPermit`.
     */
    bool public isPaused;

    /**
     * @notice The supply cap for the vault.
     * @dev Defaults to no cap
     */
    uint256 public supplyCap = type(uint256).max;

    /**
     * @notice The max time from last update on the Accountant before deposit or withdraw reverts.
     * @dev Defaults to no cap
     */
    uint64 public maxTimeFromLastUpdate = type(uint64).max;

    /**
     * @notice rate limit period, applies to all assets and defaults to 1 day
     */
    uint32 public rateLimitPeriod = 1 days;

    /**
     * @notice contains necessary values for a rate limit. The last time it was updated, the rate limit for this asset
     * and the deposits counted since last update
     */
    struct LimitData {
        uint32 lastTimestamp;
        uint112 rateLimit;
        uint112 currentDepositCount;
        uint128 depositCap;
        uint128 totalDepositCount;
    }

    /**
     * @notice Maps asset addresses to the LimitData struct for rate limits and deposit caps
     */
    mapping(address => LimitData) public limitByAsset;

    /**
     * @dev Maps deposit nonce to keccak256(address receiver, address depositAsset, uint256 depositAmount, uint256
     * shareAmount, uint256 timestamp, uint256 shareLockPeriod).
     */
    mapping(uint256 => bytes32) public publicDepositHistory;

    /**
     * @notice Maps user address to the time their shares will be unlocked.
     */
    mapping(address => uint256) public shareUnlockTime;

    //============================== ERRORS ===============================

    error TellerWithMultiAssetSupport__ShareLockPeriodTooLong();
    error TellerWithMultiAssetSupport__SharesAreLocked();
    error TellerWithMultiAssetSupport__SharesAreUnLocked();
    error TellerWithMultiAssetSupport__BadDepositHash();
    error TellerWithMultiAssetSupport__AssetDepositNotSupported();
    error TellerWithMultiAssetSupport__AssetWithdrawNotSupported();
    error TellerWithMultiAssetSupport__ZeroAssets();
    error TellerWithMultiAssetSupport__MinimumMintNotMet();
    error TellerWithMultiAssetSupport__MinimumAssetsNotMet();
    error TellerWithMultiAssetSupport__PermitFailedAndAllowanceTooLow();
    error TellerWithMultiAssetSupport__ZeroShares();
    error TellerWithMultiAssetSupport__Paused();
    error TellerWithMultiAssetSupport__InvalidInput();
    error TellerWithMultiAssetSupport__RateLimit();
    error TellerWithMultiAssetSupport__DepositCapReached();
    error TellerWithMultiAssetSupport__SupplyCapReached();
    error TellerWithMultiAssetSupport__AccountantPaused();
    error TellerWithMultiAssetSupport__MaxTimeFromLastUpdateExceeded();

    //============================== EVENTS ===============================

    event Paused();
    event Unpaused();
    event AssetConfigured(address indexed asset, uint112 newRateLimit, uint256 newSupplyCap, bool isWithdrawSupported);
    event Deposit(
        uint256 indexed nonce,
        address indexed receiver,
        address indexed depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        uint256 shareLockPeriodAtTimeOfDeposit
    );
    event BulkDeposit(address indexed asset, uint256 depositAmount);
    event BulkWithdraw(address indexed asset, uint256 shareAmount);
    event DepositRefunded(uint256 indexed nonce, bytes32 depositHash, address indexed user);

    //============================== IMMUTABLES ===============================

    /**
     * @notice The BoringVault this contract is working with.
     */
    BoringVault public immutable vault;

    /**
     * @notice The AccountantWithRateProviders this contract is working with.
     */
    AccountantWithRateProviders public immutable accountant;

    /**
     * @notice One share of the BoringVault.
     */
    uint256 internal immutable ONE_SHARE;

    constructor(address _owner, address _vault, address _accountant) AuthOwnable2Step(_owner, Authority(address(0))) {
        vault = BoringVault(payable(_vault));
        ONE_SHARE = 10 ** vault.decimals();
        accountant = AccountantWithRateProviders(_accountant);
    }

    // ========================================= ADMIN FUNCTIONS =========================================

    /**
     * @notice Sets the supply cap for the vault.
     * @dev Callable by MULTISIG_ROLE.
     */
    function setSupplyCap(uint256 _supplyCap) external requiresAuth {
        supplyCap = _supplyCap;
    }

    /**
     * @notice Sets the max time from last update.
     * @dev Callable by MULTISIG_ROLE.
     */
    function setMaxTimeFromLastUpdate(uint64 _maxTimeFromLastUpdate) external requiresAuth {
        maxTimeFromLastUpdate = _maxTimeFromLastUpdate;
    }

    /**
     * @notice Pause this contract, which prevents future calls to `deposit` and `depositWithPermit`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function pause() external requiresAuth {
        isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpause this contract, which allows future calls to `deposit` and `depositWithPermit`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function unpause() external requiresAuth {
        isPaused = false;
        emit Unpaused();
    }

    /**
     * @notice Sets the rate limit period.
     * @dev Callable by OWNER_ROLE.
     */
    function setRateLimitPeriod(uint32 _rateLimitPeriod) external requiresAuth {
        rateLimitPeriod = _rateLimitPeriod;
    }

    /**
     * @notice Adds assets to the teller.
     * @dev Callable by OWNER_ROLE.
     */
    function addAssets(ERC20[] calldata assets) external requiresAuth {
        uint256 length = assets.length;
        for (uint256 i; i < length; ++i) {
            ERC20 asset = assets[i];
            // ensure 0 addresses and values are not passed in
            if (address(asset) == address(0)) {
                revert TellerWithMultiAssetSupport__InvalidInput();
            }
            LimitData storage limitData = limitByAsset[address(asset)];
            limitData.lastTimestamp = uint32(block.timestamp);
            limitData.rateLimit = type(uint112).max;
            limitData.depositCap = type(uint128).max;
            isWithdrawSupported[asset] = true;
            emit AssetConfigured(address(asset), type(uint112).max, type(uint128).max, true);
        }
    }

    /**
     * @notice Configures assets deposit caps (0 if not supported) and withdrawable status
     * @dev All arrays must be the same length
     */
    function configureAssets(
        ERC20[] calldata assets,
        uint112[] calldata rateLimits,
        uint128[] calldata depositCaps,
        bool[] calldata withdrawStatusByAssets
    )
        external
        requiresAuth
    {
        uint256 length = assets.length;
        if (length != withdrawStatusByAssets.length || length != rateLimits.length || length != depositCaps.length) {
            revert TellerWithMultiAssetSupport__InvalidInput();
        }

        for (uint256 i; i < length; ++i) {
            ERC20 asset = assets[i];
            // ensure 0 addresses and values are not passed in
            if (address(asset) == address(0)) {
                revert TellerWithMultiAssetSupport__InvalidInput();
            }
            LimitData storage limitData = limitByAsset[address(asset)];

            limitData.lastTimestamp = uint32(block.timestamp);
            limitData.rateLimit = rateLimits[i];
            limitData.depositCap = depositCaps[i];

            isWithdrawSupported[asset] = withdrawStatusByAssets[i];
            emit AssetConfigured(address(asset), rateLimits[i], depositCaps[i], withdrawStatusByAssets[i]);
        }
    }

    /**
     * @notice Sets the share lock period.
     * @dev This not only locks shares to the user address, but also serves as the pending deposit period, where
     * deposits can be reverted.
     * @dev If a new shorter share lock period is set, users with pending share locks could make a new deposit to
     * receive 1 wei shares,
     *      and have their shares unlock sooner than their original deposit allows. This state would allow for the user
     * deposit to be refunded,
     *      but only if they have not transferred their shares out of there wallet. This is an accepted limitation, and
     * should be known when decreasing
     *      the share lock period.
     * @dev Callable by OWNER_ROLE.
     */
    function setShareLockPeriod(uint64 _shareLockPeriod) external requiresAuth {
        if (_shareLockPeriod > MAX_SHARE_LOCK_PERIOD) revert TellerWithMultiAssetSupport__ShareLockPeriodTooLong();
        shareLockPeriod = _shareLockPeriod;
    }

    // ========================================= BeforeTransferHook FUNCTIONS =========================================

    /**
     * @notice Implement beforeTransfer hook to check if shares are locked.
     */
    function beforeTransfer(address from) public view {
        if (shareUnlockTime[from] > block.timestamp) revert TellerWithMultiAssetSupport__SharesAreLocked();
    }

    // ========================================= REVERT DEPOSIT FUNCTIONS =========================================

    /**
     * @notice Allows DEPOSIT_REFUNDER_ROLE to revert a pending deposit.
     * @dev Once a deposit share lock period has passed, it can no longer be reverted.
     * @dev It is possible the admin does not setup the BoringVault to call the transfer hook,
     *      but this contract can still be saving share lock state. In the event this happens
     *      deposits are still refundable if the user has not transferred their shares.
     *      But there is no guarantee that the user has not transferred their shares.
     * @dev Callable by STRATEGIST_MULTISIG_ROLE.
     */
    function refundDeposit(
        uint256 nonce,
        address receiver,
        address depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        uint256 shareLockUpPeriodAtTimeOfDeposit
    )
        external
        requiresAuth
    {
        if ((block.timestamp - depositTimestamp) > shareLockUpPeriodAtTimeOfDeposit) {
            // Shares are already unlocked, so we can not revert deposit.
            revert TellerWithMultiAssetSupport__SharesAreUnLocked();
        }
        bytes32 depositHash = keccak256(
            abi.encode(
                receiver, depositAsset, depositAmount, shareAmount, depositTimestamp, shareLockUpPeriodAtTimeOfDeposit
            )
        );
        if (publicDepositHistory[nonce] != depositHash) revert TellerWithMultiAssetSupport__BadDepositHash();

        // Delete hash to prevent refund gas.
        delete publicDepositHistory[nonce];

        // Burn shares and refund assets to receiver.
        vault.exit(receiver, ERC20(depositAsset), depositAmount, receiver, shareAmount);

        emit DepositRefunded(nonce, depositHash, receiver);
    }

    // ========================================= USER FUNCTIONS =========================================

    /**
     * @notice Allows users to deposit into the BoringVault, if this contract is not paused.
     * @dev Publicly callable.
     */
    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to
    )
        external
        nonReentrant
        requiresAuth
        returns (uint256 shares)
    {
        if (isPaused) revert TellerWithMultiAssetSupport__Paused();

        shares = _erc20Deposit(depositAsset, depositAmount, minimumMint, to);

        _afterPublicDeposit(to, depositAsset, depositAmount, shares, shareLockPeriod);
    }

    /**
     * @notice Allows users to deposit into BoringVault using permit.
     * @dev Publicly callable.
     */
    function depositWithPermit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        uint256 deadline,
        address to,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        nonReentrant
        requiresAuth
        returns (uint256 shares)
    {
        if (isPaused) revert TellerWithMultiAssetSupport__Paused();

        // solhint-disable-next-line no-empty-blocks
        try depositAsset.permit(msg.sender, address(vault), depositAmount, deadline, v, r, s) { }
        catch {
            if (depositAsset.allowance(msg.sender, address(vault)) < depositAmount) {
                revert TellerWithMultiAssetSupport__PermitFailedAndAllowanceTooLow();
            }
        }
        shares = _erc20Deposit(depositAsset, depositAmount, minimumMint, to);

        _afterPublicDeposit(to, depositAsset, depositAmount, shares, shareLockPeriod);
    }

    /**
     * @notice Allows off ramp role to withdraw from this contract.
     * @dev Callable by SOLVER_ROLE.
     */
    function bulkWithdraw(
        ERC20 withdrawAsset,
        uint256 shareAmount,
        uint256 minimumAssets,
        address to
    )
        external
        requiresAuth
        returns (uint256 assetsOut)
    {
        if (accountant.isPaused()) revert TellerWithMultiAssetSupport__AccountantPaused();
        if (block.timestamp - accountant.getLastUpdateTimestamp() > maxTimeFromLastUpdate) {
            revert TellerWithMultiAssetSupport__MaxTimeFromLastUpdateExceeded();
        }
        if (!isWithdrawSupported[withdrawAsset]) revert TellerWithMultiAssetSupport__AssetWithdrawNotSupported();

        if (shareAmount == 0) revert TellerWithMultiAssetSupport__ZeroShares();

        assetsOut = accountant.getAssetsOutForShares(withdrawAsset, shareAmount);

        if (assetsOut < minimumAssets) revert TellerWithMultiAssetSupport__MinimumAssetsNotMet();
        vault.exit(to, withdrawAsset, assetsOut, msg.sender, shareAmount);
        emit BulkWithdraw(address(withdrawAsset), shareAmount);
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================

    /**
     * @notice Implements a common ERC20 deposit into BoringVault.
     */
    function _erc20Deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to
    )
        internal
        returns (uint256 shares)
    {
        if (accountant.isPaused()) revert TellerWithMultiAssetSupport__AccountantPaused();
        if (block.timestamp - accountant.getLastUpdateTimestamp() > maxTimeFromLastUpdate) {
            revert TellerWithMultiAssetSupport__MaxTimeFromLastUpdateExceeded();
        }
        if (limitByAsset[address(depositAsset)].rateLimit == 0) {
            revert TellerWithMultiAssetSupport__AssetDepositNotSupported();
        }
        _checkRateLimit(address(depositAsset), depositAmount);
        limitByAsset[address(depositAsset)].totalDepositCount += uint128(depositAmount);
        if (limitByAsset[address(depositAsset)].depositCap < limitByAsset[address(depositAsset)].totalDepositCount) {
            revert TellerWithMultiAssetSupport__DepositCapReached();
        }

        if (depositAmount == 0) revert TellerWithMultiAssetSupport__ZeroAssets();

        shares = accountant.getSharesForDepositAmount(depositAsset, depositAmount);

        if (shares < minimumMint) revert TellerWithMultiAssetSupport__MinimumMintNotMet();

        if (shares + vault.totalSupply() > supplyCap) revert TellerWithMultiAssetSupport__SupplyCapReached();
        vault.enter(msg.sender, depositAsset, depositAmount, to, shares);
    }

    /**
     * @notice Handle share lock logic, and event.
     */
    function _afterPublicDeposit(
        address user,
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 shares,
        uint256 currentShareLockPeriod
    )
        internal
    {
        shareUnlockTime[user] = block.timestamp + currentShareLockPeriod;

        uint256 nonce = depositNonce;
        publicDepositHistory[nonce] =
            keccak256(abi.encode(user, depositAsset, depositAmount, shares, block.timestamp, currentShareLockPeriod));
        depositNonce++;
        emit Deposit(nonce, user, address(depositAsset), depositAmount, shares, block.timestamp, currentShareLockPeriod);
    }

    function _checkRateLimit(address asset, uint256 attemptedDeposit) internal {
        LimitData memory limitData = limitByAsset[asset];
        LimitData storage storageLimitData = limitByAsset[asset];

        if (limitData.lastTimestamp + rateLimitPeriod < block.timestamp) {
            storageLimitData.currentDepositCount = 0;
            storageLimitData.lastTimestamp = uint32(block.timestamp);
        }

        storageLimitData.currentDepositCount += uint112(attemptedDeposit);
        if (storageLimitData.currentDepositCount > limitData.rateLimit) {
            revert TellerWithMultiAssetSupport__RateLimit();
        }
    }
}
