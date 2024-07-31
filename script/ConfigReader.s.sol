// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { stdJson as StdJson } from "@forge-std/StdJson.sol";

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
        address decoder;
        address rateProvider;
        bytes32 rateProviderSalt;
        uint256 maxTimeFromLastUpdate;
        address[] assets;
        address[] rateProviders;
        address[] priceFeeds;
        address base;
    }

    function toConfig(string memory _config, string memory _chainConfig) internal pure returns (Config memory config) {
        // Reading the 'protocolAdmin'
        config.protocolAdmin = _config.readAddress(".protocolAdmin");

        // Reading from the 'accountant' section
        config.accountant = _config.readAddress(".accountant.address");
        config.accountantSalt = _config.readBytes32(".accountant.accountantSalt");
        config.payoutAddress = _config.readAddress(".accountant.payoutAddress");
        config.allowedExchangeRateChangeUpper = uint16(_config.readUint(".accountant.allowedExchangeRateChangeUpper"));
        config.allowedExchangeRateChangeLower = uint16(_config.readUint(".accountant.allowedExchangeRateChangeLower"));
        config.minimumUpdateDelayInSeconds = uint32(_config.readUint(".accountant.minimumUpdateDelayInSeconds"));
        config.managementFee = uint16(_config.readUint(".accountant.managementFee"));

        // Reading from the 'boringVault' section
        config.boringVault = _config.readAddress(".boringVault.address");
        config.boringVaultSalt = _config.readBytes32(".boringVault.boringVaultSalt");
        config.boringVaultName = _config.readString(".boringVault.boringVaultName");
        config.boringVaultSymbol = _config.readString(".boringVault.boringVaultSymbol");

        // Reading from the 'manager' section
        config.manager = _config.readAddress(".manager.address");
        config.managerSalt = _config.readBytes32(".manager.managerSalt");

        // Reading from the 'teller' section
        config.teller = _config.readAddress(".teller.address");
        config.tellerSalt = _config.readBytes32(".teller.tellerSalt");
        config.maxGasForPeer = _config.readUint(".teller.maxGasForPeer");
        config.minGasForPeer = _config.readUint(".teller.minGasForPeer");
        config.tellerContractName = _config.readString(".teller.tellerContractName");
        config.assets = _config.readAddressArray(".teller.assets");

        // Reading from the 'rolesAuthority' section
        config.rolesAuthority = _config.readAddress(".rolesAuthority.address");
        config.rolesAuthoritySalt = _config.readBytes32(".rolesAuthority.rolesAuthoritySalt");
        config.strategist = _config.readAddress(".rolesAuthority.strategist");
        config.exchangeRateBot = _config.readAddress(".rolesAuthority.exchangeRateBot");

        // Reading from the 'decoder' section
        config.decoderSalt = _config.readBytes32(".decoder.decoderSalt");
        config.decoder = _config.readAddress(".decoder.address");

        // Reading from the 'rateProvider' section
        config.rateProvider = _config.readAddress(".rateProvider.address");
        config.rateProviderSalt = _config.readBytes32(".rateProvider.rateProviderSalt");
        config.maxTimeFromLastUpdate = uint32(_config.readUint(".rateProvider.maxTimeFromLastUpdate"));

        // Reading from the 'chainConfig' section
        config.base = _chainConfig.readAddress(".base");
        config.balancerVault = _chainConfig.readAddress(".balancerVault");
        config.opMessenger = _chainConfig.readAddress(".opMessenger");
        config.lzEndpoint = _chainConfig.readAddress(".lzEndpoint");

        return config;
    }
}
