// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Auth, Authority } from "@solmate/auth/Auth.sol";

contract HLPAccount is Auth {
    address public constant HLP_VAULT = 0xdfc24b077bc1425AD1DEA75bCB6f8158E10Df303;
    uint64 public constant USDC_INDEX = 0;

    address public immutable coreWriter;
    address public immutable vault;

    constructor(address _owner, address _vault, address _coreWriter) Auth(_owner, Authority(address(0))) {
        coreWriter = _coreWriter;
        vault = _vault;
    }

    function toPerp(uint64 amount) external requiresAuth {
        bytes memory encodedAction = abi.encode(amount, true);
        _sendCoreWriterCall(encodedAction, 0x07);
    }

    function toSpot(uint64 amount) external requiresAuth {
        bytes memory encodedAction = abi.encode(amount, false);
        _sendCoreWriterCall(encodedAction, 0x07);
    }

    function depositHLP(uint64 amount) external requiresAuth {
        bytes memory encodedAction = abi.encode(HLP_VAULT, true, amount);
        _sendCoreWriterCall(encodedAction, 0x02);
    }

    function withdrawHLP(uint64 amount) external requiresAuth {
        bytes memory encodedAction = abi.encode(HLP_VAULT, false, amount);
        _sendCoreWriterCall(encodedAction, 0x02);
    }

    function withdrawSpot(uint64 amount) external requiresAuth {
        bytes memory encodedAction = abi.encode(vault, USDC_INDEX, amount);
        _sendCoreWriterCall(encodedAction, 0x06);
    }

    // Use a raw call with no error handling since core writer will not throw errors regardless
    function _sendCoreWriterCall(bytes memory encodedAction, bytes1 actionID) internal {
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = actionID;
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        coreWriter.call(abi.encodeWithSignature("sendRawAction(bytes)", data));
    }
}
