// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BoringVault} from "./../../../src/base/BoringVault.sol";
import {BaseScript} from "./../../Base.s.sol";
import {stdJson as StdJson} from "@forge-std/StdJson.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MainnetAddresses} from "../../../test/resources/MainnetAddresses.sol";

import {ManagerWithMerkleVerification} from "../../../src/base/Roles/ManagerWithMerkleVerification.sol";
import {AccountantWithRateProviders} from "../../../src/base/Roles/AccountantWithRateProviders.sol";
import {CrossChainLayerZeroTellerWithMultiAssetSupport} from "../../../src/base/Roles/CrossChain/CrossChainLayerZeroTellerWithMultiAssetSupport.sol";
import {TellerWithMultiAssetSupport} from "../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import {IonPoolDecoderAndSanitizer} from "../../../src/base/DecodersAndSanitizers/IonPoolDecoderAndSanitizer.sol";
import {EthPerWstEthRateProvider} from "../../../src/oracles/EthPerWstEthRateProvider.sol";

import {ETH_PER_STETH_CHAINLINK, WSTETH_ADDRESS} from "@ion-protocol/Constants.sol";
import {IRateProvider} from "../../../src/interfaces/IRateProvider.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

abstract contract DeployCrossChainBase is BaseScript, MainnetAddresses {
    using StdJson for string;

    string path = "./deployment-config/01_DeployIonBoringVault.json";
    string config = vm.readFile(path);

    bytes32 boringVaultSalt = config.readBytes32(".boringVaultSalt");
    string boringVaultName = config.readString(".boringVaultName");
    string boringVaultSymbol = config.readString(".boringVaultSymbol");

    // CHANGE this
    uint8 public constant STRATEGIST_ROLE = 1;
    uint8 public constant MANAGER_ROLE = 2;
    uint8 public constant TELLER_ROLE = 3;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 4;

    function fullDeployForChain(string memory rpc, address lzEndpoint) internal broadcast returns(CrossChainLayerZeroTellerWithMultiAssetSupport teller){
        vm.rpcUrl(rpc);


        // 01
        require(boringVaultSalt != bytes32(0));
        require(keccak256(bytes(boringVaultName)) != keccak256(bytes("")));
        require(keccak256(bytes(boringVaultSymbol)) != keccak256(bytes("")));

        bytes memory creationCode = type(BoringVault).creationCode;

        BoringVault boringVault;
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

        require(boringVault.owner() == broadcaster, "owner should be the deployer");
        require(address(boringVault.hook()) == address(0), "before transfer hook should be zero");


        // 02
        path = "./deployment-config/02_DeployIonBoringVault.json";
        config = vm.readFile(path);
        bytes32 managerSalt = config.readBytes32(".managerSalt");

        require(managerSalt != bytes32(0), "manager salt must not be zero");
        require(address(boringVault) != address(0), "boring vault address must not be zero");

        require(address(boringVault).code.length != 0, "boring vault must have code");
        require(address(BALANCER_VAULT).code.length != 0, "balancer vault must have code");

        creationCode = type(ManagerWithMerkleVerification).creationCode;

        ManagerWithMerkleVerification manager;
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

        require(manager.isPaused() == false, "the manager must not be paused");
        require(address(manager.vault()) == address(boringVault), "the manager vault must be the boring vault");
        require(address(manager.balancerVault()) == BALANCER_VAULT, "the manager balancer vault must be the balancer vault");


        // 03
        path = "./deployment-config/03_DeployAccountantWithRateProviders.json";
        config = vm.readFile(path);

        bytes32 accountantSalt = config.readBytes32(".accountantSalt");
        address payoutAddress = config.readAddress(".payoutAddress");
        address base = config.readAddress(".base");
        uint16 allowedExchangeRateChangeUpper = uint16(config.readUint(".allowedExchangeRateChangeUpper"));
        uint16 allowedExchangeRateChangeLower = uint16(config.readUint(".allowedExchangeRateChangeLower"));
        uint32 minimumUpdateDelayInSeconds = uint32(config.readUint(".minimumUpdateDelayInSeconds"));
        uint16 managementFee = uint16(config.readUint(".managementFee"));

        uint256 startingExchangeRate = 10 ** ERC20(base).decimals();

        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(base.code.length != 0, "base must have code");

        require(accountantSalt != bytes32(0), "accountant salt must not be zero");
        require(address(boringVault) != address(0), "boring vault address must not be zero");
        require(payoutAddress != address(0), "payout address must not be zero");
        require(base != address(0), "base address must not be zero");

        require(allowedExchangeRateChangeUpper > 1e4, "allowedExchangeRateChangeUpper");
        require(allowedExchangeRateChangeUpper <= 1.0003e4, "allowedExchangeRateChangeUpper upper bound");

        require(allowedExchangeRateChangeLower < 1e4, "allowedExchangeRateChangeLower");
        require(allowedExchangeRateChangeLower >= 0.9997e4, "allowedExchangeRateChangeLower lower bound");

        require(minimumUpdateDelayInSeconds >= 3600, "minimumUpdateDelayInSeconds");

        require(managementFee < 1e4, "managementFee");

        require(startingExchangeRate == 1e18, "starting exchange rate must be 1e18");

        AccountantWithRateProviders accountant;

        creationCode = type(AccountantWithRateProviders).creationCode;

        accountant = AccountantWithRateProviders(
            CREATEX.deployCreate3(
                accountantSalt,
                abi.encodePacked(
                    creationCode,
                    abi.encode(
                        broadcaster,
                        boringVault,
                        payoutAddress,
                        startingExchangeRate,
                        base,
                        allowedExchangeRateChangeUpper,
                        allowedExchangeRateChangeLower,
                        minimumUpdateDelayInSeconds,
                        managementFee
                    )
                )
            )
        );

        (
            address _payoutAddress,
            uint128 _feesOwedInBase,
            uint128 _totalSharesLastUpdate,
            uint96 _exchangeRate,
            uint16 _allowedExchangeRateChangeUpper,
            uint16 _allowedExchangeRateChangeLower,
            uint64 _lastUpdateTimestamp,
            bool _isPaused,
            uint32 _minimumUpdateDelayInSeconds,
            uint16 _managementFee
        ) = accountant.accountantState();

        require(_payoutAddress == payoutAddress, "payout address");
        require(_feesOwedInBase == 0, "fees owed in base");
        require(_totalSharesLastUpdate == 0, "total shares last update");
        require(_exchangeRate == startingExchangeRate, "exchange rate");
        require(_allowedExchangeRateChangeUpper == allowedExchangeRateChangeUpper, "allowed exchange rate change upper");
        require(_allowedExchangeRateChangeLower == allowedExchangeRateChangeLower, "allowed exchange rate change lower");
        require(_lastUpdateTimestamp == uint64(block.timestamp), "last update timestamp");
        require(_isPaused == false, "is paused");
        require(_minimumUpdateDelayInSeconds == minimumUpdateDelayInSeconds, "minimum update delay in seconds");
        require(_managementFee == managementFee, "management fee");

        require(address(accountant.vault()) == address(boringVault), "vault");
        require(address(accountant.base()) == base, "base");
        require(accountant.decimals() == ERC20(base).decimals(), "decimals");


        // 04
        path = "./deployment-config/04_DeployTellerWithMultiAssetSupport.json";
        config = vm.readFile(path);

        bytes32 tellerSalt = config.readBytes32(".tellerSalt");

        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(address(accountant).code.length != 0, "accountant must have code");
        
        require(tellerSalt != bytes32(0), "tellerSalt");
        require(address(boringVault) != address(0), "boringVault");
        require(address(accountant) != address(0), "accountant");

        creationCode = type(CrossChainLayerZeroTellerWithMultiAssetSupport).creationCode;

        // address _owner, address _vault, address _accountant, address _weth, address _endpoint
        teller = CrossChainLayerZeroTellerWithMultiAssetSupport(
            CREATEX.deployCreate3(
                tellerSalt,
                abi.encodePacked(creationCode, abi.encode(broadcaster, boringVault, accountant, address(WETH), lzEndpoint))
            )
        );

        require(teller.shareLockPeriod() == 0, "share lock period must be zero");
        require(teller.isPaused() == false, "the teller must not be paused");
        require(
            AccountantWithRateProviders(teller.accountant()).vault() == teller.vault(),
            "the accountant vault must be the teller vault"
        );


        // 05
        path = "./deployment-config/05_DeployRolesAuthority.json";
        config = vm.readFile(path);

        bytes32 rolesAuthoritySalt = config.readBytes32(".rolesAuthoritySalt");

        address strategist = config.readAddress(".strategist");
        address exchangeRateBot = config.readAddress(".exchangeRateBot");

        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(address(manager).code.length != 0, "manager must have code");
        require(address(teller).code.length != 0, "teller must have code");
        require(address(accountant).code.length != 0, "accountant must have code");
        
        require(address(boringVault) != address(0), "boringVault");
        require(address(manager) != address(0), "manager");
        require(address(teller) != address(0), "teller");
        require(address(accountant) != address(0), "accountant");
        require(strategist != address(0), "strategist");
        
        RolesAuthority rolesAuthority;
        creationCode = type(RolesAuthority).creationCode;

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

        // --- Assign roles to users ---

        rolesAuthority.setUserRole(strategist, STRATEGIST_ROLE, true);

        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);

        rolesAuthority.setUserRole(address(teller), TELLER_ROLE, true);

        rolesAuthority.setUserRole(exchangeRateBot, UPDATE_EXCHANGE_RATE_ROLE, true);

        require(rolesAuthority.doesUserHaveRole(strategist, STRATEGIST_ROLE), "strategist should have STRATEGIST_ROLE");
        require(rolesAuthority.doesUserHaveRole(address(manager), MANAGER_ROLE), "manager should have MANAGER_ROLE");
        require(rolesAuthority.doesUserHaveRole(address(teller), TELLER_ROLE), "teller should have TELLER_ROLE");
        require(rolesAuthority.doesUserHaveRole(exchangeRateBot, UPDATE_EXCHANGE_RATE_ROLE), "exchangeRateBot should have UPDATE_EXCHANGE_RATE_ROLE");
        
        require(rolesAuthority.canCall(strategist, address(manager), ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector), "strategist should be able to call manageVaultWithMerkleVerification");
        require(rolesAuthority.canCall(address(manager), address(boringVault), bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)")))), "manager should be able to call boringVault.manage");
        require(rolesAuthority.canCall(address(manager), address(boringVault), bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])")))), "manager should be able to call boringVault.manage");
        require(rolesAuthority.canCall(address(teller), address(boringVault), BoringVault.enter.selector), "teller should be able to call boringVault.enter");
        require(rolesAuthority.canCall(address(teller), address(boringVault), BoringVault.exit.selector), "teller should be able to call boringVault.exit");
        require(rolesAuthority.canCall(exchangeRateBot, address(accountant), AccountantWithRateProviders.updateExchangeRate.selector), "exchangeRateBot should be able to call accountant.updateExchangeRate");

        require(rolesAuthority.canCall(address(1), address(teller), TellerWithMultiAssetSupport.deposit.selector), "anyone should be able to call teller.deposit");


        // 06
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


        // 07
        path = "./deployment-config/07_DeployDecoderAndSanitizer.json";
        config = vm.readFile(path);

        bytes32 decoderSalt = config.readBytes32(".decoderSalt");    
        require(address(boringVault).code.length != 0, "boringVault must have code");
        require(decoderSalt != bytes32(0), "decoder salt must not be zero");
        require(address(boringVault) != address(0), "boring vault must be set");

        creationCode = type(IonPoolDecoderAndSanitizer).creationCode;

        IonPoolDecoderAndSanitizer decoder;
        decoder = IonPoolDecoderAndSanitizer(
            CREATEX.deployCreate3(decoderSalt, abi.encodePacked(creationCode, abi.encode(boringVault)))
        );


        // 08
        path = "./deployment-config/08_DeployRateProviders.json";
        config = vm.readFile(path);

        uint256 maxTimeFromLastUpdate = config.readUint(".maxTimeFromLastUpdate");
        IRateProvider rateProvider = new EthPerWstEthRateProvider{salt: ZERO_SALT}(
            address(ETH_PER_STETH_CHAINLINK), address(WSTETH_ADDRESS), maxTimeFromLastUpdate
        );
    }
}
