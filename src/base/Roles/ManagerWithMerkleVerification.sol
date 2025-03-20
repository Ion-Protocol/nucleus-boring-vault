// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BoringVault } from "src/base/BoringVault.sol";
import { MerkleProofLib } from "@solmate/utils/MerkleProofLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BalancerVault } from "src/interfaces/BalancerVault.sol";
import { ILendingPool } from "src/interfaces/ILendingPool.sol";
import { IMorphoBase } from "src/interfaces/IMorphoBase.sol";
import { IUniswapV3Pool } from "src/interfaces/IUniswapV3Pool.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { AuthOwnable2Step } from "src/helper/AuthOwnable2Step.sol";

/**
 * @title ManagerWithMerkleVerification
 * @custom:security-contact security@molecularlabs.io
 */
contract ManagerWithMerkleVerification is AuthOwnable2Step {
    using SafeTransferLib for ERC20;
    using Address for address;

    // ========================================= STATE =========================================

    /**
     * @notice A merkle tree root that restricts what data can be passed to the BoringVault.
     * @dev Maps a strategist address to their specific merkle root.
     * @dev Each leaf is composed of the keccak256 hash of abi.encodePacked {decodersAndSanitizer, target,
     * valueIsNonZero, selector, argumentAddress_0, ...., argumentAddress_N}
     *      Where:
     *             - decodersAndSanitizer is the address to call to extract packed address arguments from the calldata
     *             - target is the address to make the call to
     *             - valueIsNonZero is a bool indicating whether or not the value is non-zero
     *             - selector is the function selector on target
     *             - argumentAddress is each allowed address argument in that call
     */
    mapping(address => bytes32) public manageRoot;

    /**
     * @notice Bool indicating whether or not this contract is actively performing a flash loan.
     * @dev Used to block flash loans that are initiated outside a manage call.
     */
    bool internal performingFlashLoan;

    /**
     * @notice keccak256 hash of flash loan data.
     */
    bytes32 internal flashLoanIntentHash = bytes32(0);

    // Temporary storage for the flash loan pool address during a flash loan callback.
    address internal currentFlashLoanPool;
    // For Morpho flash loans (only one asset at a time) we also store the token.
    address internal currentMorphoToken;

    /**
     * @notice Used to pause calls to `manageVaultWithMerkleVerification`.
     */
    bool public isPaused;

    // =============================== ERRORS ===============================
    error ManagerWithMerkleVerification__InvalidManageProofLength();
    error ManagerWithMerkleVerification__InvalidTargetDataLength();
    error ManagerWithMerkleVerification__InvalidValuesLength();
    error ManagerWithMerkleVerification__InvalidDecodersAndSanitizersLength();
    error ManagerWithMerkleVerification__FlashLoanNotExecuted();
    error ManagerWithMerkleVerification__FlashLoanNotInProgress();
    error ManagerWithMerkleVerification__BadFlashLoanIntentHash();
    error ManagerWithMerkleVerification__FailedToVerifyManageProof(address target, bytes targetData, uint256 value);
    error ManagerWithMerkleVerification__Paused();
    error ManagerWithMerkleVerification__OnlyCallableByBoringVault();
    error ManagerWithMerkleVerification__OnlyCallableByFlashLoanPool();
    error ManagerWithMerkleVerification__TotalSupplyMustRemainConstantDuringManagement();
    error ManagerWithMerkleVerification__ZeroFlashLoanAmount();

    // =============================== EVENTS ===============================
    event ManageRootUpdated(address indexed strategist, bytes32 oldRoot, bytes32 newRoot);
    event BoringVaultManaged(uint256 callsMade);
    event Paused();
    event Unpaused();

    // =============================== IMMUTABLES =========================================

    /**
     * @notice The BoringVault this contract can manage.
     */
    BoringVault public immutable vault;

    constructor(address _owner, address _vault) AuthOwnable2Step(_owner, Authority(address(0))) {
        vault = BoringVault(payable(_vault));
    }

    // ========================================= ADMIN FUNCTIONS =========================================

    /**
     * @notice Sets the manageRoot.
     * @dev Callable by OWNER_ROLE.
     */
    function setManageRoot(address strategist, bytes32 _manageRoot) external requiresAuth {
        bytes32 oldRoot = manageRoot[strategist];
        manageRoot[strategist] = _manageRoot;
        emit ManageRootUpdated(strategist, oldRoot, _manageRoot);
    }

    /**
     * @notice Pause this contract, which prevents future calls to `manageVaultWithMerkleVerification`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function pause() external requiresAuth {
        isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpause this contract, which allows future calls to `manageVaultWithMerkleVerification`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function unpause() external requiresAuth {
        isPaused = false;
        emit Unpaused();
    }

    // ========================================= FLASH LOAN INITIALIZATION HELPER
    // =========================================

    /**
     * @notice Initializes flash loan state.
     * @dev Checks that the caller is the vault, then sets the current flash loan pool,
     *      computes and stores the flashLoanIntentHash, and sets the reentrancy flag.
     * @param poolAddress The pool address to be stored.
     * @param userData The encoded user data used for intent verification.
     */
    function _initFlashLoanState(address poolAddress, bytes calldata userData) internal {
        if (msg.sender != address(vault)) revert ManagerWithMerkleVerification__OnlyCallableByBoringVault();
        currentFlashLoanPool = poolAddress;
        flashLoanIntentHash = keccak256(userData);
        performingFlashLoan = true;
    }

    /**
     * @notice Finalizes flash loan state.
     * @dev Clears the performing flag and reverts if the flashLoanIntentHash is non-zero.
     */
    function _finalizeFlashLoanState() internal {
        performingFlashLoan = false;
        if (flashLoanIntentHash != bytes32(0)) {
            revert ManagerWithMerkleVerification__FlashLoanNotExecuted();
        }
    }

    // ========================================= STRATEGIST FUNCTIONS =========================================

    /**
     * @notice Allows strategist to manage the BoringVault.
     * @dev The strategist must provide a merkle proof for every call that verifiees they are allowed to make that call.
     * @dev Callable by MANAGER_INTERNAL_ROLE.
     * @dev Callable by STRATEGIST_ROLE.
     * @dev Callable by MICRO_MANAGER_ROLE.
     */
    function manageVaultWithMerkleVerification(
        bytes32[][] calldata manageProofs,
        address[] calldata decodersAndSanitizers,
        address[] calldata targets,
        bytes[] calldata targetData,
        uint256[] calldata values
    )
        external
        requiresAuth
    {
        if (isPaused) revert ManagerWithMerkleVerification__Paused();
        uint256 targetsLength = targets.length;
        if (targetsLength != manageProofs.length) revert ManagerWithMerkleVerification__InvalidManageProofLength();
        if (targetsLength != targetData.length) revert ManagerWithMerkleVerification__InvalidTargetDataLength();
        if (targetsLength != values.length) revert ManagerWithMerkleVerification__InvalidValuesLength();
        if (targetsLength != decodersAndSanitizers.length) {
            revert ManagerWithMerkleVerification__InvalidDecodersAndSanitizersLength();
        }

        bytes32 strategistManageRoot = manageRoot[msg.sender];
        uint256 totalSupply = vault.totalSupply();

        for (uint256 i; i < targetsLength; ++i) {
            _verifyCallData(
                strategistManageRoot, manageProofs[i], decodersAndSanitizers[i], targets[i], values[i], targetData[i]
            );
            vault.manage(targets[i], targetData[i], values[i]);
        }
        if (totalSupply != vault.totalSupply()) {
            revert ManagerWithMerkleVerification__TotalSupplyMustRemainConstantDuringManagement();
        }
        emit BoringVaultManaged(targetsLength);
    }

    // ========================================= FLASH LOAN FUNCTIONS =========================================

    // --- Balancer Flash Loan ---
    /**
     * @notice Initiates a Balancer flash loan.
     * @param poolAddress The Balancer (fork) pool address to use.
     * @param tokens The addresses of the tokens to be borrowed.
     * @param amounts The amounts for each token.
     * @param userData Encoded parameters for management and intent verification.
     */
    function flashLoanBalancer(
        address poolAddress,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    )
        external
    {
        _initFlashLoanState(poolAddress, userData);
        BalancerVault(poolAddress).flashLoan(address(this), tokens, amounts, userData);
        _finalizeFlashLoanState();
    }

    /**
     * @notice Balancer flash loan callback.
     * @dev userData can optionally have salt encoded at the end of it, in order to change the intentHash,
     *      if a flash loan is exact userData is being repeated, and their is fear of 3rd parties
     *      front-running the rebalance.
     * @param tokens The token addresses.
     * @param amounts The amounts borrowed.
     * @param feeAmounts (Balancer fees are assumed to be zero)
     * @param userData Encoded parameters used to derive the intent hash and management instructions.
     */
    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    )
        external
    {
        _verifyFlashLoan();
        uint256[] memory zeros = new uint256[](amounts.length);
        _processFlashLoanCallback(currentFlashLoanPool, tokens, amounts, zeros, userData, false, new uint256[](0));
    }

    // --- Aave Flash Loan ---
    /**
     * @notice Initiates an Aave flash loan.
     * @param poolAddress The Aave (fork) pool address to use.
     * @param tokens The addresses of the tokens to be borrowed.
     * @param amounts The amounts for each token.
     * @param modes Array of debt modes (use 0 for a flash loan).
     * @param userData Encoded parameters for management and intent verification.
     */
    function flashLoanAave(
        address poolAddress,
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata userData
    )
        external
    {
        _initFlashLoanState(poolAddress, userData);
        ILendingPool(poolAddress).flashLoan(address(this), tokens, amounts, modes, address(this), userData, 0);
        _finalizeFlashLoanState();
    }

    /**
     * @notice Aave flash loan callback.
     * @param assets The token addresses.
     * @param amounts The amounts borrowed.
     * @param premiums The premium fees to be repaid.
     * @param initiator The initiator of the flash loan.
     * @param params Encoded parameters used for intent verification and management calls.
     * @return True on successful execution.
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool)
    {
        _verifyFlashLoan();
        _processFlashLoanCallback(currentFlashLoanPool, assets, amounts, premiums, params, true, new uint256[](0));
        return true;
    }

    // --- Morpho Flash Loan ---
    /**
     * @notice Initiates a Morpho flash loan.
     * @param poolAddress The Morpho (fork) pool address to use.
     * @param token The address of the token to be borrowed (only one asset allowed).
     * @param assets The amount to borrow.
     * @param userData Encoded parameters for management and intent verification.
     */
    function flashLoanMorpho(address poolAddress, address token, uint256 assets, bytes calldata userData) external {
        if (assets == 0) revert ManagerWithMerkleVerification__ZeroFlashLoanAmount();
        _initFlashLoanState(poolAddress, userData);
        currentMorphoToken = token;
        IMorphoBase(poolAddress).flashLoan(token, assets, userData);
        _finalizeFlashLoanState();
    }

    /**
     * @notice Morpho flash loan callback.
     * @param assets The amount borrowed.
     * @param data Encoded parameters used for intent verification and management calls.
     */
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        _verifyFlashLoan();
        address[] memory tokens = new address[](1);
        tokens[0] = currentMorphoToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = assets;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;
        _processFlashLoanCallback(currentFlashLoanPool, tokens, amounts, fees, data, true, new uint256[](0));
    }

    // --- Uniswap V3 Swap ---
    /**
     * @notice Initiates a Uniswap V3 swap with callback.
     * @param poolAddress The Uniswap V3 pool address to use.
     * @param zeroForOne Direction of the swap (true for token0 to token1, false for token1 to token0).
     * @param amountSpecified The amount to swap (positive for exact input, negative for exact output).
     * @param userData Encoded management parameters.
     */
    function swapUniswapV3(
        address poolAddress,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata userData
    )
        external
    {
        _initFlashLoanState(poolAddress, userData);

        uint160 sqrtPriceLimitX96 = zeroForOne
            ? uint160(4_295_128_740) // Min price for token0/token1
            : uint160(1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341); // Max price

        // Use the provided price limit for a real swap
        IUniswapV3Pool(poolAddress).swap(address(this), zeroForOne, amountSpecified, sqrtPriceLimitX96, userData);

        _finalizeFlashLoanState();
    }

    /**
     * @notice Uniswap V3 swap callback.
     * @param amount0Delta The amount of token0 that needs to be sent to the pool.
     * @param amount1Delta The amount of token1 that needs to be sent to the pool.
     * @param data Encoded management parameters.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _verifyFlashLoan();

        // Build token array from pool's token0 and token1
        address[] memory tokens = new address[](2);
        tokens[0] = IUniswapV3Pool(currentFlashLoanPool).token0();
        tokens[1] = IUniswapV3Pool(currentFlashLoanPool).token1();

        // For Uniswap, we only have one token to repay and one to receive
        uint256[] memory amountsToPay = new uint256[](2);
        uint256[] memory amountsToReceive = new uint256[](2);

        // If amount0Delta is positive, we owe token0 to the pool
        // If amount1Delta is negative, we received token1 from the pool
        if (amount0Delta > 0) {
            amountsToPay[0] = uint256(amount0Delta);
            amountsToReceive[1] = amount1Delta < 0 ? uint256(-amount1Delta) : 0;
        } else {
            // Otherwise, we owe token1 and received token0
            amountsToPay[1] = uint256(amount1Delta);
            amountsToReceive[0] = amount0Delta < 0 ? uint256(-amount0Delta) : 0;
        }

        // No additional fees for swaps
        uint256[] memory fees = new uint256[](2);

        _processFlashLoanCallback(
            currentFlashLoanPool,
            tokens,
            amountsToPay, // Only contains the token we owe
            fees,
            data,
            false,
            amountsToReceive // Only contains the token we received
        );
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================

    /**
     * @notice Verifies that the flash loan callback is coming from the correct pool and that a flash loan is in
     * progress.
     */
    function _verifyFlashLoan() internal view {
        if (msg.sender != currentFlashLoanPool) revert ManagerWithMerkleVerification__OnlyCallableByFlashLoanPool();
        if (!performingFlashLoan) revert ManagerWithMerkleVerification__FlashLoanNotInProgress();
    }

    /**
     * @notice Verifies the flash loan intent hash against the provided parameters.
     * @param params The userData that was used to initiate the flash loan.
     * @return computedHash The computed keccak256 hash of the params.
     */
    function _verifyFlashLoanState(bytes calldata params) internal view returns (bytes32 computedHash) {
        computedHash = keccak256(params);
        if (computedHash != flashLoanIntentHash) revert ManagerWithMerkleVerification__BadFlashLoanIntentHash();
    }

    /**
     * @notice Resets the flash loan state to prevent reentrancy or replay.
     */
    function _resetFlashLoanState() internal {
        flashLoanIntentHash = bytes32(0);
        currentFlashLoanPool = address(0);
    }

    /**
     * @notice Internal helper to process common flash loan callback tasks (for multi-asset loans).
     * @param repayTo The address to which the repayment will be sent or approved.
     * @param tokens The token addresses.
     * @param amounts The amounts borrowed/to be repaid.
     * @param fees The fee amounts associated with the flash loan.
     * @param params The management parameters used for intent verification and management calls.
     * @param useApprove If true, the manager will perform direct approvals for repayment.
     * @param amountsToReceive Optional array of amounts received (used for Uniswap swaps), empty for regular flash
     * loans.
     */
    function _processFlashLoanCallback(
        address repayTo,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory fees,
        bytes calldata params,
        bool useApprove,
        uint256[] memory amountsToReceive
    )
        internal
    {
        _verifyFlashLoanState(params);
        _resetFlashLoanState();

        // For regular flash loans, transfer all borrowed tokens to the vault
        if (amountsToReceive.length == 0) {
            for (uint256 i = 0; i < amounts.length; ++i) {
                ERC20(tokens[i]).safeTransfer(address(vault), amounts[i]);
            }
        }
        // For Uniswap swaps, only transfer the received token(s) to the vault
        else {
            for (uint256 i = 0; i < amountsToReceive.length; ++i) {
                if (amountsToReceive[i] > 0) {
                    ERC20(tokens[i]).safeTransfer(address(vault), amountsToReceive[i]);
                }
            }
        }

        // Decode management parameters
        (
            bytes32[][] memory manageProofs,
            address[] memory decodersAndSanitizers,
            address[] memory targets,
            bytes[] memory data,
            uint256[] memory values
        ) = abi.decode(params, (bytes32[][], address[], address[], bytes[], uint256[]));

        ManagerWithMerkleVerification(address(this)).manageVaultWithMerkleVerification(
            manageProofs, decodersAndSanitizers, targets, data, values
        );

        // Call the second part of the function with the necessary parameters
        _processRepayment(repayTo, tokens, amounts, fees, useApprove);
    }

    // New helper function to handle repayment logic
    function _processRepayment(
        address repayTo,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory fees,
        bool useApprove
    )
        internal
    {
        bytes[] memory transferData = new bytes[](tokens.length);

        if (!useApprove) {
            // For protocols like Balancer and Uniswap V3 flash swaps, repay via vault.transfer
            for (uint256 i = 0; i < amounts.length; ++i) {
                if (amounts[i] > 0) {
                    transferData[i] = abi.encodeWithSelector(ERC20.transfer.selector, repayTo, (amounts[i] + fees[i]));
                } else {
                    // Empty transfer for tokens we don't need to pay back
                    transferData[i] = abi.encodeWithSelector(ERC20.transfer.selector, address(0), 0);
                }
            }
        } else {
            // For protocols like Aave and Morpho, approve the pool to pull funds
            for (uint256 i = 0; i < amounts.length; ++i) {
                if (amounts[i] > 0) {
                    ERC20(tokens[i]).safeApprove(repayTo, (amounts[i] + fees[i]));
                    transferData[i] =
                        abi.encodeWithSelector(ERC20.transfer.selector, address(this), (amounts[i] + fees[i]));
                } else {
                    // No need to approve for tokens we don't need to pay back
                    transferData[i] = abi.encodeWithSelector(ERC20.transfer.selector, address(0), 0);
                }
            }
        }

        vault.manage(tokens, transferData, new uint256[](tokens.length));
    }

    /**
     * @notice Helper function to decode, sanitize, and verify call data.
     */
    function _verifyCallData(
        bytes32 currentManageRoot,
        bytes32[] calldata manageProof,
        address decoderAndSanitizer,
        address target,
        uint256 value,
        bytes calldata targetData
    )
        internal
        view
    {
        // Use address decoder to get addresses in call data.
        bytes memory packedArgumentAddresses = abi.decode(decoderAndSanitizer.functionStaticCall(targetData), (bytes));
        if (
            !_verifyManageProof(
                currentManageRoot,
                manageProof,
                target,
                decoderAndSanitizer,
                value,
                bytes4(targetData),
                packedArgumentAddresses
            )
        ) {
            revert ManagerWithMerkleVerification__FailedToVerifyManageProof(target, targetData, value);
        }
    }

    /**
     * @notice Helper function to verify that a manage proof is valid.
     */
    function _verifyManageProof(
        bytes32 root,
        bytes32[] calldata proof,
        address target,
        address decoderAndSanitizer,
        uint256 value,
        bytes4 selector,
        bytes memory packedArgumentAddresses
    )
        internal
        pure
        returns (bool)
    {
        bool valueNonZero = value > 0;
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(
                    abi.encodePacked(decoderAndSanitizer, target, valueNonZero, selector, packedArgumentAddresses)
                )
            )
        );
        return MerkleProofLib.verify(proof, root, leaf);
    }
}
