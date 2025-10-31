// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "../BaseDecoderAndSanitizer.sol";
import { DecoderCustomTypes } from "src/interfaces/DecoderCustomTypes.sol";

interface IPositionManager {

    function ownerOf(address position) external view returns (address);

}

abstract contract SentimentDecoderAndSanitizer is BaseDecoderAndSanitizer {

    IPositionManager internal immutable positionManager;

    error SentimentDecoderAndSanitizer__PositionNotOwned();

    constructor(address _positionManager) {
        positionManager = IPositionManager(_positionManager);
    }

    // @desc Function dispatcher for all Sentiment protocol actions on the PositionManager contract.
    // @tag packedArgs:bytes:packed args are conditional based on the operation types including NewPosition, Deposit,
    // Borrow, Repay, Transfer, AddToken, or RemoveToken.
    function process(
        address position,
        DecoderCustomTypes.Action calldata action
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        bytes calldata data = action.data;

        // We skip the `positionManager.ownerOf(position) != boringVault` check
        // if the operation is `NewPosition` because this check cannot pass
        // without calling the NewPosition operation first.
        if (action.op == DecoderCustomTypes.Operation.NewPosition) {
            address owner = address(bytes20(data[0:20]));
            addressesFound = abi.encodePacked(owner);
        } else if (positionManager.ownerOf(position) != boringVault) {
            revert SentimentDecoderAndSanitizer__PositionNotOwned();
        } else if (
            action.op == DecoderCustomTypes.Operation.Deposit || action.op == DecoderCustomTypes.Operation.AddToken
                || action.op == DecoderCustomTypes.Operation.RemoveToken
        ) {
            address asset = address(bytes20(data[0:20]));
            addressesFound = abi.encodePacked(asset);
        } else if (action.op == DecoderCustomTypes.Operation.Borrow || action.op == DecoderCustomTypes.Operation.Repay)
        {
            uint256 poolId = uint256(bytes32(data[0:32]));
            addressesFound = abi.encodePacked(poolId);
        } else if (action.op == DecoderCustomTypes.Operation.Transfer) {
            address recipient = address(bytes20(data[0:20]));
            address asset = address(bytes20(data[20:40]));
            uint256 amt = uint256(bytes32(data[40:72]));
            addressesFound = abi.encodePacked(recipient, asset, amt);
        }
    }

}
