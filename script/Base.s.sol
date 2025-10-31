// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19 <=0.9.0;

import { ICreateX } from "lib/createx/src/ICreateX.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { Script, stdJson } from "@forge-std/Script.sol";

import { ConfigReader, IAuthority } from "./ConfigReader.s.sol";

abstract contract BaseScript is Script {

    using stdJson for string;
    using Strings for uint256;

    string constant CONFIG_PATH_ROOT = "./deployment-config/";
    string constant CONFIG_CHAIN_ROOT = "./deployment-config/chains/";

    /// Custom base params
    ICreateX immutable CREATEX;

    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Needed for the deterministic deployments.
    bytes32 internal constant ZERO_SALT = bytes32(0);

    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;

    /// @dev Used to derive the broadcaster's address if $ETH_FROM is not defined.
    string internal mnemonic;

    bool internal deployCreate2;

    string path;

    /// @dev Initializes the transaction broadcaster like this:
    ///
    /// - If $ETH_FROM is defined, use it.
    /// - Otherwise, derive the broadcaster address from $MNEMONIC.
    /// - If $MNEMONIC is not defined, default to a test mnemonic.
    ///
    /// The use case for $ETH_FROM is to specify the broadcaster key and its address via the command line.
    constructor() {
        CREATEX = ICreateX(vm.envAddress("CREATEX"));
        deployCreate2 = vm.envOr({ name: "CREATE2", defaultValue: true });
        address from = vm.envOr({ name: "ETH_FROM", defaultValue: address(0) });
        if (from != address(0)) {
            broadcaster = from;
        } else {
            mnemonic = vm.envOr({ name: "MNEMONIC", defaultValue: TEST_MNEMONIC });
            (broadcaster,) = deriveRememberKey({ mnemonic: mnemonic, index: 0 });
        }

        // if this chain doesn't have a CREATEX deployment, deploy it ourselves
        if (address(CREATEX).code.length == 0) {
            revert("CREATEX Not Deployed on this chain. Use the DeployCustomCreatex script to deploy it");
        }
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastFrom(address from) {
        vm.startBroadcast(from);
        _;
        vm.stopBroadcast();
    }

    function deploy(ConfigReader.Config memory config) public virtual returns (address) {
        revert("deploy() Not Implemented");
    }

    function getConfig() public returns (ConfigReader.Config memory) {
        return ConfigReader.toConfig(requestConfigFileFromUser(), getChainConfigFile());
    }

    function getChainConfigFile() internal view returns (string memory) {
        return vm.readFile(string.concat(CONFIG_CHAIN_ROOT, Strings.toString(block.chainid), ".json"));
    }

    function requestConfigFileFromUser() internal returns (string memory) {
        path = string.concat(CONFIG_PATH_ROOT, vm.prompt("Please Enter The Deployments Configuration File Name: "));
        return vm.readFile(path);
    }

    function compareStrings(string memory a, string memory b) internal returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    function getMultisig() internal returns (address) {
        if (block.chainid == 1) {
            return 0x0000000000417626Ef34D62C4DC189b021603f2F;
        } else if (block.chainid == 1329) {
            return 0xF2dE1311C5b2C1BD94de996DA13F80010453e505;
        } else if (block.chainid == 42_161) {
            return 0x08f6f6dD5C9B33015124e1Ea4Ea1e0B11DB342FB;
        } else if (block.chainid == 1923) {
            return 0xc6cC90808A3434DF28028824Fd3cefcaE4A93A88;
        } else if (block.chainid == 98_866) {
            return 0x823873F5E05564a2F8374c56053ac65E3Add061b;
        } else if (block.chainid == 999) {
            return 0x413f2e80070a069eB1051772Fdc4f0af8e8303d7;
        } else if (block.chainid == 288) {
            return 0x0888c3D797E13892C5e67cD802F93Ffe55Ea2826;
        } else if (block.chainid == 1_380_012_617) {
            return 0x6d0C5a20ac08ED00256aD224F74Ca53afF3D011d;
        } else {
            revert("bad chain id");
        }
    }

}
