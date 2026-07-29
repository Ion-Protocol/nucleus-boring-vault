// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { stdJson as StdJson } from "@forge-std/StdJson.sol";

interface IAuthority {

    function setAuthority(address newAuthority) external;
    function transferOwnership(address newOwner) external;
    function owner() external view returns (address);

}

library ConfigReader {

    using StdJson for string;

    struct Config {
        string nameEntropy;
        address protocolAdmin;
        address base;
        uint8 boringVaultAndBaseDecimals;
        address boringVault;
        address payoutAddress;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint32 minimumUpdateDelayInSeconds;
        uint16 managementFee;
        uint16 performanceFee;
        string boringVaultName;
        string boringVaultSymbol;
        address beforeTransferHookAddress;
        address balancerVault;
        uint32 peerEid;
        bool setupLZConfigs;
        address[] requiredDvns;
        address[] optionalDvns;
        uint64 dvnBlockConfirmationsRequired;
        uint8 optionalDvnThreshold;
        address accountant;
        address opMessenger;
        uint64 maxGasForPeer;
        uint64 minGasForPeer;
        address lzEndpoint;
        address mailbox;
        uint32 peerDomainId;
        address manager;
        address teller;
        string tellerContractName;
        address strategist;
        address exchangeRateBot;
        address rolesAuthority;
        uint256 maxTimeFromLastUpdate;
        // Per-asset fees are stored as parallel arrays rather than a struct array, because Solidity
        // 0.8.21 does not support copying a memory dynamic array of structs into storage (which
        // happens when `Config memory` is assigned to `Config storage` in deployAll). Indices line
        // up: withdrawAssets[i] pairs with withdrawAssetFlatFees[i] and withdrawAssetPercentFees[i].
        // The author of the config json must be sure these arrays are the same length
        address[] withdrawAssets;
        uint256[] withdrawAssetFlatFees;
        uint256[] withdrawAssetPercentFees;
        address[] depositAssets;
        uint256[] depositAssetFlatFees;
        uint256[] depositAssetPercentFees;
        address[] rateProviders;
        address[] priceFeeds;
        bool distributorCodeDepositorDeploy;
        bool distributorCodeDepositorIsNativeDepositSupported;
        address distributorCodeDepositor;
        address nativeWrapper;
        address uniswapV3NonFungiblePositionManager;
        uint256 distributorCodeDepositorSupplyCap;
        address registry;
        string policyID;
        string withdrawQueueName;
        string withdrawQueueSymbol;
        address withdrawQueueFeeRecipient;
        uint256 withdrawQueueMinimumOrderSize;
        address withdrawQueue;
        address withdrawQueueProcessorAddress;
        address freezeListBeforeTransferHook;
        address genericDecoderAndSanitizer;
        bool equivalentExchangeUManagerDeploy;
        address equivalentExchangeUManager;
        // Optional accounting basket for the EquivalentExchangeUManager, stored as parallel arrays for the
        // same reason as the fee arrays above (0.8.21 cannot copy a memory struct array into storage during
        // the `mainConfig = config` assignment in deployAll). Indices line up: basketTokens[i] is priced by
        // basketOracles[i] (the zero address marks a 1:1 token) whose getRate() output carries
        // basketRateDecimals[i] decimals. All three arrays must be the same length.
        address[] equivalentExchangeUManagerBasketTokens;
        address[] equivalentExchangeUManagerBasketOracles;
        uint256[] equivalentExchangeUManagerBasketRateDecimals;
    }

    function toConfig(string memory _config, string memory _chainConfig) internal view returns (Config memory config) {
        // Reading the 'nameEntropy`
        config.nameEntropy = _config.readString(".nameEntropy");

        // Reading the 'protocolAdmin'
        config.protocolAdmin = _config.readAddress(".protocolAdmin");
        config.base = _config.readAddress(".base");
        config.boringVaultAndBaseDecimals = uint8(_config.readUint(".boringVaultAndBaseDecimals"));

        // Reading from the 'accountant' section
        config.accountant = _config.readAddress(".accountant.address");
        config.payoutAddress = _config.readAddress(".accountant.payoutAddress");
        config.allowedExchangeRateChangeUpper = uint16(_config.readUint(".accountant.allowedExchangeRateChangeUpper"));
        config.allowedExchangeRateChangeLower = uint16(_config.readUint(".accountant.allowedExchangeRateChangeLower"));
        config.minimumUpdateDelayInSeconds = uint32(_config.readUint(".accountant.minimumUpdateDelayInSeconds"));
        config.managementFee = uint16(_config.readUint(".accountant.managementFee"));
        config.performanceFee = uint16(_config.readUint(".accountant.performanceFee"));

        // Reading from the 'boringVault' section
        config.boringVault = _config.readAddress(".boringVault.address");
        config.boringVaultName = _config.readString(".boringVault.boringVaultName");
        config.boringVaultSymbol = _config.readString(".boringVault.boringVaultSymbol");
        config.beforeTransferHookAddress = _config.readAddress(".boringVault.beforeTransferHookAddress");

        // Reading from the 'manager' section
        config.manager = _config.readAddress(".manager.address");

        // Reading from the 'teller' section
        config.teller = _config.readAddress(".teller.address");
        config.maxGasForPeer = uint64(_config.readUint(".teller.maxGasForPeer"));
        config.minGasForPeer = uint64(_config.readUint(".teller.minGasForPeer"));
        config.tellerContractName = _config.readString(".teller.tellerContractName");
        config.withdrawAssets = _config.readAddressArray(".teller.withdrawAssets");
        config.withdrawAssetFlatFees =
            _config.readUintArrayOr(".teller.withdrawAssetFlatFees", new uint256[](config.withdrawAssets.length));
        config.withdrawAssetPercentFees =
            _config.readUintArrayOr(".teller.withdrawAssetPercentFees", new uint256[](config.withdrawAssets.length));
        require(
            config.withdrawAssets.length == config.withdrawAssetFlatFees.length
                && config.withdrawAssets.length == config.withdrawAssetPercentFees.length,
            "ConfigReader: withdrawAssets fee arrays length mismatch"
        );

        config.depositAssets = _config.readAddressArray(".teller.depositAssets");
        config.depositAssetFlatFees =
            _config.readUintArrayOr(".teller.depositAssetFlatFees", new uint256[](config.depositAssets.length));
        config.depositAssetPercentFees =
            _config.readUintArrayOr(".teller.depositAssetPercentFees", new uint256[](config.depositAssets.length));
        require(
            config.depositAssets.length == config.depositAssetFlatFees.length
                && config.depositAssets.length == config.depositAssetPercentFees.length,
            "ConfigReader: depositAssets fee arrays length mismatch"
        );

        // layerzero
        if (compareStrings(config.tellerContractName, "MultiChainLayerZeroTellerWithMultiAssetSupport")) {
            config.lzEndpoint = _chainConfig.readAddress(".lzEndpoint");

            config.peerEid = uint32(_config.readUint(".teller.peerEid"));
            config.setupLZConfigs = _config.readBool(".teller.setupLZConfigs");
            config.requiredDvns = _config.readAddressArray(".teller.dvnIfNoDefault.required");
            config.optionalDvns = _config.readAddressArray(".teller.dvnIfNoDefault.optional");
            config.dvnBlockConfirmationsRequired =
                uint64(_config.readUint(".teller.dvnIfNoDefault.blockConfirmationsRequiredIfNoDefault"));
            config.optionalDvnThreshold = uint8(_config.readUint(".teller.dvnIfNoDefault.optionalThreshold"));
        } else if (compareStrings(config.tellerContractName, "MultiChainHyperlaneTellerWithMultiAssetSupport")) {
            config.mailbox = _chainConfig.readAddress(".mailbox");
            config.peerDomainId = uint32(_config.readUint(".teller.peerDomainId"));
        }

        // Reading from the 'rolesAuthority' section
        config.rolesAuthority = _config.readAddress(".rolesAuthority.address");
        config.strategist = _config.readAddress(".rolesAuthority.strategist");
        config.exchangeRateBot = _config.readAddress(".rolesAuthority.exchangeRateBot");

        // Reading from the 'distributorCodeDepositor' section
        config.distributorCodeDepositorDeploy = _config.readBool(".distributorCodeDepositor.deploy");
        config.distributorCodeDepositorIsNativeDepositSupported =
            _config.readBool(".distributorCodeDepositor.nativeSupported");
        config.distributorCodeDepositorSupplyCap = _config.readUint(".distributorCodeDepositor.supplyCap");
        config.registry = _config.readAddress(".distributorCodeDepositor.registry");
        config.policyID = _config.readString(".distributorCodeDepositor.policyID");

        // Reading from the 'withdrawQueue' section
        config.withdrawQueueName = _config.readString(".withdrawQueue.name");
        config.withdrawQueueSymbol = _config.readString(".withdrawQueue.symbol");
        config.withdrawQueueFeeRecipient = _config.readAddress(".withdrawQueue.feeRecipient");
        config.withdrawQueueMinimumOrderSize = uint256(_config.readUint(".withdrawQueue.minimumOrderSize"));
        config.withdrawQueueProcessorAddress = _config.readAddress(".withdrawQueue.processorAddress");

        // Reading from the 'freezeListBeforeTransferHook' section
        config.freezeListBeforeTransferHook = _config.readAddress(".freezeListBeforeTransferHook.address");

        // Reading from the optional 'equivalentExchangeUManager' section. Defaults to not deploying so
        // existing configs that omit the key are unaffected.
        config.equivalentExchangeUManagerDeploy = _config.readBoolOr(".equivalentExchangeUManager.deploy", false);
        // Optional basket, keyed by parallel arrays. All default to empty, so a deploy-only UManager (no
        // basket wired at deploy time) needs no basket keys at all.
        config.equivalentExchangeUManagerBasketTokens =
            _config.readAddressArrayOr(".equivalentExchangeUManager.basketTokens", new address[](0));
        config.equivalentExchangeUManagerBasketOracles =
            _config.readAddressArrayOr(".equivalentExchangeUManager.basketOracles", new address[](0));
        config.equivalentExchangeUManagerBasketRateDecimals =
            _config.readUintArrayOr(".equivalentExchangeUManager.basketRateDecimals", new uint256[](0));
        require(
            config.equivalentExchangeUManagerBasketTokens.length
                    == config.equivalentExchangeUManagerBasketOracles.length
                && config.equivalentExchangeUManagerBasketTokens.length
                    == config.equivalentExchangeUManagerBasketRateDecimals.length,
            "ConfigReader: equivalentExchangeUManager basket arrays length mismatch"
        );

        // Reading from the 'chainConfig' section
        config.balancerVault = _chainConfig.readAddress(".balancerVault");
        config.nativeWrapper = _chainConfig.readAddress(".nativeWrapper");
        // Optional: only required by chains that deploy a Uniswap-V3-aware decoder/sanitizer.
        config.uniswapV3NonFungiblePositionManager =
            _chainConfig.readAddressOr(".uniswapV3NonFungiblePositionManager", address(0));

        return config;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

}
