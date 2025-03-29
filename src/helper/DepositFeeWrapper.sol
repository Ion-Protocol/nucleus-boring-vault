// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @custom:security-contact security@molecularlabs.io
 */
contract DepositFeeWrapper is Ownable2Step {
    using SafeTransferLib for ERC20;

    uint256 public feePercentage;
    address public feeReceiver;

    error DepositFeeWrapper__InvalidFeePercentage();
    error DepositFeeWrapper__ZeroAddress();

    event FeesCollected(address indexed asset, uint256 fee, address receiver);
    event NewFeePercentage(uint256 feePercentage);
    event NewFeeReceiver(address feeReceiver);

    constructor(address _owner) Ownable(_owner) { }

    /**
     * @notice deposit with frontend fee set by owner, NOTE minShares is inclusive of fees
     */
    function deposit(
        TellerWithMultiAssetSupport teller,
        ERC20 asset,
        uint256 amount,
        uint256 minShares,
        address receiver
    )
        external
    {
        uint256 fee = amount * feePercentage / 1e4;
        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.safeTransfer(feeReceiver, fee);

        emit FeesCollected(address(asset), fee, feeReceiver);

        asset.safeApprove(address(teller.vault()), amount - fee);
        teller.deposit(asset, amount - fee, minShares, receiver);
    }

    /**
     * @notice set fee percentage in basis points
     * @dev callable by OWNER
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        if (_feePercentage > 1e4) revert DepositFeeWrapper__InvalidFeePercentage();
        feePercentage = _feePercentage;
        emit NewFeePercentage(_feePercentage);
    }

    /**
     * @notice set fee receiver
     * @dev callable by OWNER
     */
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        if (_feeReceiver == address(0)) revert DepositFeeWrapper__ZeroAddress();
        feeReceiver = _feeReceiver;
        emit NewFeeReceiver(_feeReceiver);
    }
}
