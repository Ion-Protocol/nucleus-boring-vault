// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CommunityCodeDepositorWithoutNative } from "src/helper/CommunityCodeDepositorWithoutNative.sol";
import { BaseScript } from "script/Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";

interface IOwner {
    function owner() external view returns (address);
}

contract DeployCommunityCodeDepositorWithoutNative is BaseScript {
    using StdJson for string;

    // NOTE MUST BE SET ON EACH DEPLOYMENT
    address constant TELLER = 0x8c3F1cbE2932FcA4403ec6Bbc65989a963ee4a3C; // whlp teller
    address constant OWNER = 0x413f2e80070a069eB1051772Fdc4f0af8e8303d7; // hyperliquid multisig
    bytes32 constant SALT = 0x1cf73ab0d8c6d2dcabf3f304c78f86d7f6cbce2a5427311ba31c5a731f985893;

    function run() public broadcast returns (address) {
        // Require config Values
        require(TELLER.code.length != 0, "teller must have code");
        require(OWNER.code.length != 0, "owner must have code");

        require(TELLER != address(0), "teller");
        require(OWNER != address(0), "protocolAdmin");

        require(SALT != bytes32(0), "tellerSalt");

        require(OWNER == IOwner(TELLER).owner(), "CommunityCodeDepositor owner must be the same as the teller owner");

        console.log("CREATEX", address(CREATEX));
        // Create Contract
        bytes memory creationCode = type(CommunityCodeDepositorWithoutNative).creationCode;
        CommunityCodeDepositorWithoutNative communityCodeDepositor = CommunityCodeDepositorWithoutNative(
            CREATEX.deployCreate3(SALT, abi.encodePacked(creationCode, abi.encode(TELLER, OWNER)))
        );

        // Post Deploy Checks
        require(communityCodeDepositor.owner() == OWNER, "owner must be set correctly");
        require(address(communityCodeDepositor.teller()) == TELLER, "teller must be set correctly");
        require(
            communityCodeDepositor.teller().owner() == OWNER,
            "teller owner must be the same as the CommunityCodeDepositor owner"
        );

        console.log("CommunityCodeDepositor deployed at:", address(communityCodeDepositor));
        console.log("Owner:", communityCodeDepositor.owner());
        console.log("Teller:", address(communityCodeDepositor.teller()));

        return address(communityCodeDepositor);
    }
}
