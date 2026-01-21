// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract MasterChefV3DecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc harvest rewards from staked LP positions
    // @tag to:address:receiver of the harvest tokens
    function harvest(uint256, address _to) external pure virtual returns (bytes memory addressesFound) {
        return abi.encodePacked(_to);
    }

    // @desc withdraw staked LP positions
    // @tag to:address:receiver of the withdrawn LP NFT
    function withdraw(uint256, address _to) external pure virtual returns (bytes memory addressesFound) {
        return abi.encodePacked(_to);
    }

}
