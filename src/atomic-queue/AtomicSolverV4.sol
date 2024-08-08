// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AtomicQueueV2 } from "./AtomicQueueV2.sol";
import { IAtomicSolver } from "./IAtomicSolver.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ERC4626 } from "@solmate/tokens/ERC4626.sol";
import { IWEETH } from "src/interfaces/IStaking.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

/**
 * @title AtomicSolverV4
 * @author jpick713
 */
contract AtomicSolverV4 is IAtomicSolver, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    // ========================================= CONSTANTS =========================================

    ERC20 internal constant eETH = ERC20(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
    ERC20 internal constant weETH = ERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    // ========================================= ENUMS =========================================

    /**
     * @notice The Solve Type, used in `finishSolve` to determine the logic used.
     * @notice P2P Solver wants to swap share.asset() for user(s) shares
     * @notice REDEEM Solver needs to redeem shares, then can cover user(s) required assets.
     */
    enum SolveType {
        P2P,
        REDEEM
    }

    //============================== ERRORS ===============================

    error AtomicSolverV4___WrongInitiator();
    error AtomicSolverV4___AlreadyInSolveContext();
    error AtomicSolverV4___FailedToSolve();
    error AtomicSolverV4___SolveMaxAssetsExceeded(uint256 actualAssets, uint256 maxAssets);
    error AtomicSolverV4___P2PSolveMinSharesNotMet(uint256 actualShares, uint256 minShares);
    error AtomicSolverV4___BoringVaultTellerMismatch(address vault, address teller);

    //============================== IMMUTABLES ===============================

    constructor(address _owner) Auth(_owner, Authority(address(0))) { }

    //============================== SOLVE FUNCTIONS ===============================
    /**
     * @notice Solver wants to exchange p2p share.asset() for withdraw queue shares.
     * @dev Solver should approve this contract to spend share.asset().
     */
    function p2pSolve(
        AtomicQueueV2 queue,
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        uint256 minOfferReceived,
        uint256 maxAssets
    )
        external
        requiresAuth
    {
        bytes memory runData = abi.encode(SolveType.P2P, msg.sender, minOfferReceived, maxAssets, type(uint256).max);

        // Solve for `users`.
        queue.solve(offer, want, users, runData, address(this));
    }

    /**
     * @notice Solver wants to redeem withdraw offer shares, to help cover withdraw.
     * @dev `offer` MUST be an ERC4626 vault.
     */
    function redeemSolve(
        AtomicQueueV2 queue,
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        uint256 minimumAssetsOut,
        uint256 maxAssets,
        TellerWithMultiAssetSupport teller
    )
        external
        requiresAuth
    {
        AccountantWithRateProviders accountant = teller.accountant();
        uint256 priceToCheckAtomicPrice = accountant.getRateInQuoteSafe(want);
        if (priceToCheckAtomicPrice == 0) {
            revert AtomicSolverV4___FailedToSolve();
        }

        bytes memory runData =
            abi.encode(SolveType.REDEEM, msg.sender, minimumAssetsOut, maxAssets, teller, priceToCheckAtomicPrice);

        // Solve for `users`.
        queue.solve(offer, want, users, runData, address(this));
    }

    //============================== ISOLVER FUNCTIONS ===============================

    /**
     * @notice Implement the finishSolve function WithdrawQueue expects to call.
     * @dev nonReentrant is not needed on this function because it is impossible to reenter,
     *      because the above solve functions have the nonReentrant modifier.
     *      The only way to have the first 2 checks pass is if the msg.sender is the queue,
     *      and this contract is msg.sender of `Queue.solve()`, which is only called in the above
     *      functions.
     */
    function finishSolve(
        bytes calldata runData,
        address initiator,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    )
        external
        requiresAuth
    {
        if (initiator != address(this)) revert AtomicSolverV4___WrongInitiator();

        address queue = msg.sender;

        SolveType _type = abi.decode(runData, (SolveType));

        if (_type == SolveType.P2P) {
            _p2pSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        } else if (_type == SolveType.REDEEM) {
            _redeemSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        }
    }

    //============================== HELPER FUNCTIONS ===============================

    /**
     * @notice Helper function containing the logic to handle p2p solves.
     */
    function _p2pSolve(
        address queue,
        bytes memory runData,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    )
        internal
    {
        (, address solver, uint256 minOfferReceived, uint256 maxAssets) =
            abi.decode(runData, (SolveType, address, uint256, uint256));

        // Make sure solver is receiving the minimum amount of offer.
        if (offerReceived < minOfferReceived) {
            revert AtomicSolverV4___P2PSolveMinSharesNotMet(offerReceived, minOfferReceived);
        }

        // Make sure solvers `maxAssets` was not exceeded.
        if (wantApprovalAmount > maxAssets) {
            revert AtomicSolverV4___SolveMaxAssetsExceeded(wantApprovalAmount, maxAssets);
        }

        // Transfer required want from solver.
        want.safeTransferFrom(solver, address(this), wantApprovalAmount);

        // Transfer offer to solver.
        offer.safeTransfer(solver, offerReceived);

        // Approve queue to spend wantApprovalAmount.
        want.safeApprove(queue, wantApprovalAmount);
    }

    /**
     * @notice Helper function containing the logic to handle redeem solves.
     */
    function _redeemSolve(
        address queue,
        bytes memory runData,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    )
        internal
    {
        (, address solver, uint256 minimumAssetsOut, uint256 maxAssets, TellerWithMultiAssetSupport teller) =
            abi.decode(runData, (SolveType, address, uint256, uint256, TellerWithMultiAssetSupport));

        if (address(offer) != address(teller.vault())) {
            revert AtomicSolverV4___BoringVaultTellerMismatch(address(offer), address(teller));
        }
        // Make sure solvers `maxAssets` was not exceeded.
        if (wantApprovalAmount > maxAssets) {
            revert AtomicSolverV4___SolveMaxAssetsExceeded(wantApprovalAmount, maxAssets);
        }

        // Redeem the shares, sending assets to solver.
        teller.bulkWithdraw(want, offerReceived, minimumAssetsOut, solver);

        // Transfer required assets from solver.
        want.safeTransferFrom(solver, address(this), wantApprovalAmount);

        // Approve queue to spend wantApprovalAmount.
        want.safeApprove(queue, wantApprovalAmount);
    }
}
