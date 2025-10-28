// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "../BaseDecoderAndSanitizer.sol";

abstract contract OPStandardL2BridgeDecoderAndSanitizer is BaseDecoderAndSanitizer {

    /**
     * @dev use bridgeTo instead of bridge despite us usually wanting to bridge to the same address
     * because OP requires EOAs to call the regular bridge functions.
     * Also instead of reverting on _to != boring vault, we instead encode the value here on the off chance
     * a boring vault does not match addresses on destination chain.
     * Also do not encode the _extraData as it is not used by anything except emits
     */
    // @desc bridge ERC20 OP standard L2 bridge
    // @tag localToken:address:local token
    // @tag remoteToken:address:remote token
    // @tag to:address:receiver of the bridged tokens
    // @tag extraData:bytes:extra data, depending on the message, can get from a test tx
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(_localToken, _remoteToken, _to, _extraData);
    }

    /**
     * @dev use bridgeTo instead of bridge despite us usually wanting to bridge to the same address
     * because OP requires EOAs to call the regular bridge functions.
     * Also instead of reverting on _to != boring vault, we instead encode the value here on the off chance
     * a boring vault does not match addresses on destination chain.
     * Also do not encode the _extraData as it is not used by anything except emits
     */
    // @desc bridge native token using OP standard L2 bridge
    // @tag to:address:receiver of the bridged tokens
    // @tag extraData:bytes:extra data, depending on the message, can get from a test tx
    function bridgeETHTo(
        address _to,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(_to, _extraData);
    }

}
