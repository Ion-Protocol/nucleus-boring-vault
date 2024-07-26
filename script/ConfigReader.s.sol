// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {stdJson as StdJson} from "@forge-std/StdJson.sol";

interface IAuthority {
    function setAuthority(address newAuthority) external;
    function transferOwnership(address newOwner) external;
    function owner() external returns (address);
}

library ConfigReader {
    using StdJson for string;

    struct Config {
        address protocolAdmin;
        bytes32 accountantSalt;
        address boringVault;
        address payoutAddress;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint32 minimumUpdateDelayInSeconds;
        uint16 managementFee;
        bytes32 boringVaultSalt;
        string boringVaultName;
        string boringVaultSymbol;
        bytes32 managerSalt;
        address balancerVault;
        bytes32 tellerSalt;
        address accountant;
        address opMessenger;
        uint256 maxGasForPeer;
        uint256 minGasForPeer;
        address lzEndpoint;
        bytes32 rolesAuthoritySalt;
        address manager;
        address teller;
        string tellerContractName;
        address strategist;
        address exchangeRateBot;
        address rolesAuthority;
        bytes32 decoderSalt;
        uint256 maxTimeFromLastUpdate;

        address base;
    }

    function toConfig(string memory _config, string memory _chainConfig) internal returns(Config memory config){
        config.protocolAdmin = _config.readAddress(".protocolAdmin");
        config.accountantSalt = _config.readBytes32(".accountantSalt");
        config.boringVault = _config.readAddress(".boringVault");
        config.payoutAddress = _config.readAddress(".payoutAddress");
        config.allowedExchangeRateChangeUpper = uint16(_config.readUint(".allowedExchangeRateChangeUpper"));
        config.allowedExchangeRateChangeLower = uint16(_config.readUint(".allowedExchangeRateChangeLower"));
        config.minimumUpdateDelayInSeconds = uint32(_config.readUint(".minimumUpdateDelayInSeconds"));
        config.managementFee = uint16(_config.readUint(".managementFee"));
        config.boringVaultSalt = _config.readBytes32(".boringVaultSalt");
        config.boringVaultName = _config.readString(".boringVaultName");
        config.boringVaultSymbol = _config.readString(".boringVaultSymbol");
        config.managerSalt = _config.readBytes32(".managerSalt");
        config.tellerSalt = _config.readBytes32(".tellerSalt");
        config.accountant = _config.readAddress(".accountant");
        config.opMessenger = _config.readAddress(".opMessenger");
        config.maxGasForPeer = _config.readUint(".maxGasForPeer");
        config.minGasForPeer = _config.readUint(".minGasForPeer");
        config.lzEndpoint = _config.readAddress(".lzEndpoint");
        config.rolesAuthoritySalt = _config.readBytes32(".rolesAuthoritySalt");
        config.manager = _config.readAddress(".manager");
        config.teller = _config.readAddress(".teller");
        config.tellerContractName = _config.readString(".tellerContractName");
        config.strategist = _config.readAddress(".strategist");
        config.exchangeRateBot = _config.readAddress(".exchangeRateBot");
        config.rolesAuthority = _config.readAddress(".rolesAuthority");
        config.decoderSalt = _config.readBytes32(".decoderSalt");

        config.base = _chainConfig.readAddress(".base");
        config.balancerVault = _chainConfig.readAddress(".balancerVault");
    }
}