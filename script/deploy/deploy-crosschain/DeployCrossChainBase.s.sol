// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BoringVault} from "./../../../src/base/BoringVault.sol";
import {BaseScript} from "./../../Base.s.sol";
import {stdJson as StdJson} from "@forge-std/StdJson.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MainnetAddresses} from "../../../test/resources/MainnetAddresses.sol";

import {ManagerWithMerkleVerification} from "../../../src/base/Roles/ManagerWithMerkleVerification.sol";
import {AccountantWithRateProviders} from "../../../src/base/Roles/AccountantWithRateProviders.sol";

import {MultiChainLayerZeroTellerWithMultiAssetSupport} from "../../../src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";
import {CrossChainOPTellerWithMultiAssetSupport} from "../../../src/base/Roles/CrossChain/CrossChainOPTellerWithMultiAssetSupport.sol";

import {TellerWithMultiAssetSupport} from "../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import {IonPoolDecoderAndSanitizer} from "../../../src/base/DecodersAndSanitizers/IonPoolDecoderAndSanitizer.sol";
import {EthPerWstEthRateProvider} from "../../../src/oracles/EthPerWstEthRateProvider.sol";

import {ETH_PER_STETH_CHAINLINK, WSTETH_ADDRESS} from "@ion-protocol/Constants.sol";
import {IRateProvider} from "../../../src/interfaces/IRateProvider.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

import {CrossChainTellerBase} from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";


struct AccountantConfig{
        bytes32 accountantSalt;
        address payoutAddress;
        address base;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint32 minimumUpdateDelayInSeconds;
        uint16 managementFee;

        uint256 startingExchangeRate;
}

struct AccountantReturn{
        address _payoutAddress;
        uint128 _feesOwedInBase;
        uint128 _totalSharesLastUpdate;
        uint96 _exchangeRate;
        uint16 _allowedExchangeRateChangeUpper;
        uint16 _allowedExchangeRateChangeLower;
        uint64 _lastUpdateTimestamp;
        bool _isPaused;
        uint32 _minimumUpdateDelayInSeconds;
        uint16 _managementFee;
}

abstract contract DeployCrossChainBase is BaseScript, MainnetAddresses {
    using StdJson for string;

    uint8 public constant STRATEGIST_ROLE = 1;
    uint8 public constant MANAGER_ROLE = 2;
    uint8 public constant TELLER_ROLE = 3;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 4;

    mapping(string => mapping(string => address)) public addressesByRpc;

    modifier broadcastChain(string memory rpc) {
        vm.createSelectFork(vm.rpcUrl(rpc));
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    function fullDeployForChainOP(string memory rpc, address messenger) internal returns(CrossChainOPTellerWithMultiAssetSupport teller){
        // 01 ===========================================================================================================================================
        BoringVault boringVault = _deployBoringVault();

        // 02 ===========================================================================================================================================
        ManagerWithMerkleVerification manager = _deployManager(boringVault);

        // 03 ===========================================================================================================================================
        AccountantWithRateProviders accountant = _deployAccountant(boringVault, rpc);
        
        // 04 ===========================================================================================================================================
        teller = _deployTellerOP(boringVault, accountant, messenger, rpc);        

        // 05 ===========================================================================================================================================
        RolesAuthority rolesAuthority = _deployRolesAuthority(boringVault, manager, teller, accountant);

        // 06 ===========================================================================================================================================
        {        
            require(address(boringVault).code.length != 0, "boringVault must have code");
            require(address(manager).code.length != 0, "manager must have code");
            require(address(teller).code.length != 0, "teller must have code");
            require(address(accountant).code.length != 0, "accountant must have code");
            
            require(address(boringVault) != address(0), "boringVault");
            require(address(manager) != address(0), "manager");
            require(address(accountant) != address(0), "accountant");
            require(address(teller) != address(0), "teller");
            require(address(rolesAuthority) != address(0), "rolesAuthority");

            require(protocolAdmin != address(0), "protocolAdmin");

            boringVault.setAuthority(rolesAuthority);
            manager.setAuthority(rolesAuthority);
            accountant.setAuthority(rolesAuthority);
            teller.setAuthority(rolesAuthority);

            boringVault.transferOwnership(protocolAdmin);
            manager.transferOwnership(protocolAdmin);
            accountant.transferOwnership(protocolAdmin);
            teller.transferOwnership(protocolAdmin);

            rolesAuthority.transferOwnership(protocolAdmin);

            require(boringVault.owner() == protocolAdmin, "boringVault");
            require(manager.owner() == protocolAdmin, "manager");
            require(accountant.owner() == protocolAdmin, "accountant");
            require(teller.owner() == protocolAdmin, "teller");
        }

    }

    function fullDeployForChainLZ(string memory rpc, address lzEndpoint) internal returns(MultiChainLayerZeroTellerWithMultiAssetSupport teller){
        // 01 ===========================================================================================================================================
        BoringVault boringVault = _deployBoringVault();

        // 02 ===========================================================================================================================================
        ManagerWithMerkleVerification manager = _deployManager(boringVault);

        // 03 ===========================================================================================================================================
        AccountantWithRateProviders accountant = _deployAccountant(boringVault, rpc);
        
        // 04 ===========================================================================================================================================
        teller = _deployTellerLZ(boringVault, accountant, lzEndpoint, rpc);        

        // 05 ===========================================================================================================================================
        RolesAuthority rolesAuthority = _deployRolesAuthority(boringVault, manager, teller, accountant);

        // 06 ===========================================================================================================================================
        {        
            require(address(boringVault).code.length != 0, "boringVault must have code");
            require(address(manager).code.length != 0, "manager must have code");
            require(address(teller).code.length != 0, "teller must have code");
            require(address(accountant).code.length != 0, "accountant must have code");
            
            require(address(boringVault) != address(0), "boringVault");
            require(address(manager) != address(0), "manager");
            require(address(accountant) != address(0), "accountant");
            require(address(teller) != address(0), "teller");
            require(address(rolesAuthority) != address(0), "rolesAuthority");

            require(protocolAdmin != address(0), "protocolAdmin");

            boringVault.setAuthority(rolesAuthority);
            manager.setAuthority(rolesAuthority);
            accountant.setAuthority(rolesAuthority);
            teller.setAuthority(rolesAuthority);

            boringVault.transferOwnership(protocolAdmin);
            manager.transferOwnership(protocolAdmin);
            accountant.transferOwnership(protocolAdmin);
            teller.transferOwnership(protocolAdmin);

            rolesAuthority.transferOwnership(protocolAdmin);

            require(boringVault.owner() == protocolAdmin, "boringVault");
            require(manager.owner() == protocolAdmin, "manager");
            require(accountant.owner() == protocolAdmin, "accountant");
            require(teller.owner() == protocolAdmin, "teller");
        }

        // 07 ===========================================================================================================================================
        // IonPoolDecoderAndSanitizer decoder = _deployDecoder(boringVault);

        // 08 ===========================================================================================================================================
        // string memory path = "./deployment-config/08_DeployRateProviders.json";
        // string memory config = vm.readFile(path);

        // uint256 maxTimeFromLastUpdate = config.readUint(".maxTimeFromLastUpdate");
        // IRateProvider rateProvider = new EthPerWstEthRateProvider{salt: ZERO_SALT}(
        //     address(ETH_PER_STETH_CHAINLINK), address(WSTETH_ADDRESS), maxTimeFromLastUpdate
        // );
    }

    function _deployBoringVault() internal returns(BoringVault boringVault){
        string memory path = "./deployment-config/01_DeployIonBoringVault.json";
        string memory config = vm.readFile(path);
        {
            bytes32 boringVaultSalt = config.readBytes32(".boringVaultSalt");
            string memory boringVaultName = config.readString(".boringVaultName");
            string memory boringVaultSymbol = config.readString(".boringVaultSymbol");

            require(boringVaultSalt != bytes32(0));
            require(keccak256(bytes(boringVaultName)) != keccak256(bytes("")));
            require(keccak256(bytes(boringVaultSymbol)) != keccak256(bytes("")));

            bytes memory creationCode = type(BoringVault).creationCode;
            boringVault = BoringVault(
                payable(
                    CREATEX.deployCreate3(
                        boringVaultSalt,
                        abi.encodePacked(
                            creationCode,
                            abi.encode(
                                broadcaster,
                                boringVaultName,
                                boringVaultSymbol,
                                18 // decimals
                            )
                        )
                    )
                )
            );
        }
        require(boringVault.owner() == broadcaster, "owner should be the deployer");
        require(address(boringVault.hook()) == address(0), "before transfer hook should be zero");
    }

    function _deployManager(BoringVault boringVault) internal returns(ManagerWithMerkleVerification manager){
        {
            string memory path = "./deployment-config/02_DeployManagerWithMerkleVerification.json";
            string memory config = vm.readFile(path);
            bytes32 managerSalt = config.readBytes32(".managerSalt");

            require(managerSalt != bytes32(0), "manager salt must not be zero");
            require(address(boringVault) != address(0), "boring vault address must not be zero");

            require(address(boringVault).code.length != 0, "boring vault must have code");

            // On some chains like Optimism Sepolia, there isn't a BALANCER_VAULT
            // so this is commented out to test out functionality that could worth without engaging balancer
            // require(address(BALANCER_VAULT).code.length != 0, "balancer vault must have code");

            bytes memory creationCode = type(ManagerWithMerkleVerification).creationCode;

            manager = ManagerWithMerkleVerification(
                CREATEX.deployCreate3(
                    managerSalt,
                    abi.encodePacked(
                        creationCode,
                        abi.encode(
                            broadcaster,
                            boringVault,
                            BALANCER_VAULT,
                            18 // decimals
                        )
                    )
                )
            );

        }        
        require(manager.isPaused() == false, "the manager must not be paused");
        require(address(manager.vault()) == address(boringVault), "the manager vault must be the boring vault");
        require(address(manager.balancerVault()) == BALANCER_VAULT, "the manager balancer vault must be the balancer vault");

    }

    function _deployAccountant(BoringVault boringVault, string memory rpc) internal returns(AccountantWithRateProviders accountant){
        {
            string memory path = "./deployment-config/03_DeployAccountantWithRateProviders.json";
            string memory config = vm.readFile(path);

            AccountantConfig memory accConfig;
            // AccountantReturn memory returnData;

            accConfig.accountantSalt = config.readBytes32(".accountantSalt");
            accConfig.payoutAddress = config.readAddress(".payoutAddress");
            accConfig.base = addressesByRpc[rpc]["WETH"];
            accConfig.allowedExchangeRateChangeUpper = accConfig.allowedExchangeRateChangeUpper = uint16(config.readUint(".allowedExchangeRateChangeUpper"));
            accConfig.allowedExchangeRateChangeLower = uint16(config.readUint(".allowedExchangeRateChangeLower"));
            accConfig.minimumUpdateDelayInSeconds = uint32(config.readUint(".minimumUpdateDelayInSeconds"));
            accConfig.managementFee = uint16(config.readUint(".managementFee"));
            accConfig.startingExchangeRate = 10 ** ERC20(accConfig.base).decimals();

            require(address(boringVault).code.length != 0, "boringVault must have code");
            require(accConfig.base.code.length != 0, "base must have code");

            require(accConfig.accountantSalt != bytes32(0), "accountant salt must not be zero");
            require(address(boringVault) != address(0), "boring vault address must not be zero");
            require(accConfig.payoutAddress != address(0), "payout address must not be zero");
            require(accConfig.base != address(0), "base address must not be zero");

            require(accConfig.allowedExchangeRateChangeUpper > 1e4, "allowedExchangeRateChangeUpper");
            require(accConfig.allowedExchangeRateChangeUpper <= 1.0003e4, "allowedExchangeRateChangeUpper upper bound");

            require(accConfig.allowedExchangeRateChangeLower < 1e4, "allowedExchangeRateChangeLower");
            require(accConfig.allowedExchangeRateChangeLower >= 0.9997e4, "allowedExchangeRateChangeLower lower bound");

            require(accConfig.minimumUpdateDelayInSeconds >= 3600, "minimumUpdateDelayInSeconds");

            require(accConfig.managementFee < 1e4, "managementFee");

            require(accConfig.startingExchangeRate == 1e18, "starting exchange rate must be 1e18");

            bytes memory creationCode = type(AccountantWithRateProviders).creationCode;

            accountant = AccountantWithRateProviders(
                CREATEX.deployCreate3(
                    accConfig.accountantSalt,
                    abi.encodePacked(
                        creationCode,
                        abi.encode(
                            broadcaster,
                            boringVault,
                            accConfig.payoutAddress,
                            accConfig.startingExchangeRate,
                            accConfig.base,
                            accConfig.allowedExchangeRateChangeUpper,
                            accConfig.allowedExchangeRateChangeLower,
                            accConfig.minimumUpdateDelayInSeconds,
                            accConfig.managementFee
                        )
                    )
                )
            );

            // (
            //     returnData._payoutAddress,
            //     returnData._feesOwedInBase,
            //     returnData._totalSharesLastUpdate,
            //     returnData._exchangeRate,
            //     returnData._allowedExchangeRateChangeUpper,
            //     returnData._allowedExchangeRateChangeLower,
            //     returnData._lastUpdateTimestamp,
            //     returnData._isPaused,
            //     returnData._minimumUpdateDelayInSeconds,
            //     returnData._managementFee
            // ) = accountant.accountantState();

            // require(returnData._payoutAddress == accConfig.payoutAddress, "payout address");
            // require(returnData._feesOwedInBase == 0, "fees owed in base");
            // require(returnData._totalSharesLastUpdate == 0, "total shares last update");
            // require(returnData._exchangeRate == accConfig.startingExchangeRate, "exchange rate");
            // require(returnData._allowedExchangeRateChangeUpper == accConfig.allowedExchangeRateChangeUpper, "allowed exchange rate change upper");
            // require(returnData._allowedExchangeRateChangeLower == accConfig.allowedExchangeRateChangeLower, "allowed exchange rate change lower");
            // require(returnData._lastUpdateTimestamp == uint64(block.timestamp), "last update timestamp");
            // require(returnData._isPaused == false, "is paused");
            // require(returnData._minimumUpdateDelayInSeconds == accConfig.minimumUpdateDelayInSeconds, "minimum update delay in seconds");
            // require(returnData._managementFee == accConfig.managementFee, "management fee");

            require(address(accountant.vault()) == address(boringVault), "vault");
            require(address(accountant.base()) == accConfig.base, "base");
            require(accountant.decimals() == ERC20(accConfig.base).decimals(), "decimals");
        }
    }

    function _deployTellerOP(BoringVault boringVault, AccountantWithRateProviders accountant, address opMessenger, string memory rpc) internal returns(CrossChainOPTellerWithMultiAssetSupport teller) {
        string memory path = "./deployment-config/04_DeployTellerWithMultiAssetSupport.json";
        string memory config = vm.readFile(path);

        bytes32 tellerSalt = config.readBytes32(".tellerSalt");

        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(address(accountant).code.length != 0, "accountant must have code");
        
        require(tellerSalt != bytes32(0), "tellerSalt");
        require(address(boringVault) != address(0), "boringVault");
        require(address(accountant) != address(0), "accountant");

        bytes memory creationCode = type(CrossChainOPTellerWithMultiAssetSupport).creationCode;

        // address _owner, address _vault, address _accountant, address _weth, address _endpoint
        teller = CrossChainOPTellerWithMultiAssetSupport(
            CREATEX.deployCreate3(
                tellerSalt,
                abi.encodePacked(creationCode, abi.encode(broadcaster, boringVault, accountant, opMessenger))
            )
        );

        require(teller.shareLockPeriod() == 0, "share lock period must be zero");
        require(teller.isPaused() == false, "the teller must not be paused");
        require(
            AccountantWithRateProviders(teller.accountant()).vault() == teller.vault(),
            "the accountant vault must be the teller vault"
        );
    }

    function _deployTellerLZ(BoringVault boringVault, AccountantWithRateProviders accountant, address lzEndpoint, string memory rpc) internal returns(MultiChainLayerZeroTellerWithMultiAssetSupport teller) {
        string memory path = "./deployment-config/04_DeployTellerWithMultiAssetSupport.json";
        string memory config = vm.readFile(path);

        bytes32 tellerSalt = config.readBytes32(".tellerSalt");

        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(address(accountant).code.length != 0, "accountant must have code");
        
        require(tellerSalt != bytes32(0), "tellerSalt");
        require(address(boringVault) != address(0), "boringVault");
        require(address(accountant) != address(0), "accountant");

        bytes memory creationCode = type(MultiChainLayerZeroTellerWithMultiAssetSupport).creationCode;

        // address _owner, address _vault, address _accountant, address _endpoint
        teller = MultiChainLayerZeroTellerWithMultiAssetSupport(
            CREATEX.deployCreate3(
                tellerSalt,
                abi.encodePacked(creationCode, abi.encode(broadcaster, boringVault, accountant, lzEndpoint))
            )
        );

        require(teller.shareLockPeriod() == 0, "share lock period must be zero");
        require(teller.isPaused() == false, "the teller must not be paused");
        require(
            AccountantWithRateProviders(teller.accountant()).vault() == teller.vault(),
            "the accountant vault must be the teller vault"
        );
    }

    function _deployRolesAuthority(
        BoringVault boringVault, 
        ManagerWithMerkleVerification manager, 
        TellerWithMultiAssetSupport teller, 
        AccountantWithRateProviders accountant
        ) 
        internal 
    returns(RolesAuthority rolesAuthority){   

        string memory path = "./deployment-config/05_DeployRolesAuthority.json";
        string memory config = vm.readFile(path);

        bytes32 rolesAuthoritySalt = config.readBytes32(".rolesAuthoritySalt");

        address strategist = config.readAddress(".strategist");

        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(address(manager).code.length != 0, "manager must have code");
        require(address(teller).code.length != 0, "teller must have code");
        require(address(accountant).code.length != 0, "accountant must have code");
        
        require(address(boringVault) != address(0), "boringVault");
        require(address(manager) != address(0), "manager");
        require(address(teller) != address(0), "teller");
        require(address(accountant) != address(0), "accountant");
        require(strategist != address(0), "strategist");
        
        
        bytes memory creationCode = type(RolesAuthority).creationCode;

        rolesAuthority = RolesAuthority(
            CREATEX.deployCreate3(
                rolesAuthoritySalt,
                abi.encodePacked(
                    creationCode,
                    abi.encode(
                        broadcaster,
                        address(0) // `Authority`
                    )
                )
            )
        );

        // Setup initial roles configurations
        // --- Users ---
        // 1. VAULT_STRATEGIST (BOT EOA)
        // 2. MANAGER (CONTRACT)
        // 3. TELLER (CONTRACT)
        // --- Roles ---
        // 1. STRATEGIST_ROLE
        //     - manager.manageVaultWithMerkleVerification
        //     - assigned to VAULT_STRATEGIST
        // 2. MANAGER_ROLE
        //     - boringVault.manage()
        //     - assigned to MANAGER
        // 3. TELLER_ROLE
        //     - boringVault.enter()
        //     - boringVault.exit()
        //     - assigned to TELLER
        // --- Public ---
        // 1. teller.deposit

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(manager), ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector, true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(boringVault), bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))), true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(boringVault), bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))), true
        );

        rolesAuthority.setRoleCapability(TELLER_ROLE, address(boringVault), BoringVault.enter.selector, true);

        rolesAuthority.setRoleCapability(TELLER_ROLE, address(boringVault), BoringVault.exit.selector, true);

        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);

        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE, address(accountant), AccountantWithRateProviders.updateExchangeRate.selector, true
        );

        rolesAuthority.setPublicCapability(address(teller), CrossChainTellerBase.bridge.selector, true);
        rolesAuthority.setPublicCapability(address(teller), CrossChainTellerBase.depositAndBridge.selector, true);

        // --- Assign roles to users ---

        rolesAuthority.setUserRole(strategist, STRATEGIST_ROLE, true);

        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);

        rolesAuthority.setUserRole(address(teller), TELLER_ROLE, true);

        require(rolesAuthority.doesUserHaveRole(strategist, STRATEGIST_ROLE), "strategist should have STRATEGIST_ROLE");
        require(rolesAuthority.doesUserHaveRole(address(manager), MANAGER_ROLE), "manager should have MANAGER_ROLE");
        require(rolesAuthority.doesUserHaveRole(address(teller), TELLER_ROLE), "teller should have TELLER_ROLE");
        
        require(rolesAuthority.canCall(strategist, address(manager), ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector), "strategist should be able to call manageVaultWithMerkleVerification");
        require(rolesAuthority.canCall(address(manager), address(boringVault), bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)")))), "manager should be able to call boringVault.manage");
        require(rolesAuthority.canCall(address(manager), address(boringVault), bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])")))), "manager should be able to call boringVault.manage");
        require(rolesAuthority.canCall(address(teller), address(boringVault), BoringVault.enter.selector), "teller should be able to call boringVault.enter");
        require(rolesAuthority.canCall(address(teller), address(boringVault), BoringVault.exit.selector), "teller should be able to call boringVault.exit");

        require(rolesAuthority.canCall(address(1), address(teller), TellerWithMultiAssetSupport.deposit.selector), "anyone should be able to call teller.deposit");
    }

    function _deployDecoder(BoringVault boringVault) internal returns(IonPoolDecoderAndSanitizer decoder){
        string memory path = "./deployment-config/07_DeployDecoderAndSanitizer.json";
        string memory config = vm.readFile(path);

        bytes32 decoderSalt = config.readBytes32(".decoderSalt");    
        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(decoderSalt != bytes32(0), "decoder salt must not be zero");
        require(address(boringVault) != address(0), "boring vault must be set");

        bytes memory creationCode = type(IonPoolDecoderAndSanitizer).creationCode;

        decoder = IonPoolDecoderAndSanitizer(
            CREATEX.deployCreate3(decoderSalt, abi.encodePacked(creationCode, abi.encode(boringVault)))
        );
    }
}
