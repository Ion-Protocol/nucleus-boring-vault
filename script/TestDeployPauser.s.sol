// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pauser } from "src/helper/Pauser.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BalancerVault } from "src/interfaces/BalancerVault.sol";
import { EtherFiLiquidDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/EtherFiLiquidDecoderAndSanitizer.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

import "@forge-std/Script.sol";
import "@forge-std/StdJson.sol";

contract TestDeployPauser is Script {
    uint8 internal constant PAUSER_ROLE = 5;
    // State variables for deployed contracts
    Pauser internal pauser;

    BoringVault internal b1;
    AccountantWithRateProviders internal a1;
    ManagerWithMerkleVerification internal m1;
    RolesAuthority internal r1;
    TellerWithMultiAssetSupport internal t1;

    BoringVault internal b2;
    AccountantWithRateProviders internal a2;
    ManagerWithMerkleVerification internal m2;
    RolesAuthority internal r2;
    TellerWithMultiAssetSupport internal t2;

    BoringVault internal b3;
    AccountantWithRateProviders internal a3;
    ManagerWithMerkleVerification internal m3;
    RolesAuthority internal r3;
    TellerWithMultiAssetSupport internal t3;

    uint256 public privateKey;

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() external {
        vm.startBroadcast();
        console.log(msg.sender);

        pauser = new Pauser();
        console.log("PAUSER: ", address(pauser));

        // Deploy 1 "vault" with symbol BV1
        r1 = new RolesAuthority(msg.sender, Authority(address(0))); // Specific authority for vault 1
        console.log("BV1 RolesAuthority: ", address(r1));

        b1 = new BoringVault(msg.sender, "Boring Vault 1", "BV1", 18);
        console.log("BV1 BoringVault: ", address(b1));
        b1.setAuthority(r1);

        a1 = new AccountantWithRateProviders(
            msg.sender, address(b1), msg.sender, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );
        console.log("BV1 Accountant: ", address(a1));
        a1.setAuthority(r1);

        m1 = new ManagerWithMerkleVerification(msg.sender, address(b1), vault);
        console.log("BV1 Manager: ", address(m1));
        m1.setAuthority(r1);

        t1 = new TellerWithMultiAssetSupport(msg.sender, address(b1), address(a1));
        console.log("BV1 Teller: ", address(t1));
        t1.setAuthority(r1);

        r1.setUserRole(address(pauser), PAUSER_ROLE, true);
        r1.setRoleCapability(PAUSER_ROLE, address(a1), AccountantWithRateProviders.pause.selector, true);
        r1.setRoleCapability(PAUSER_ROLE, address(m1), ManagerWithMerkleVerification.pause.selector, true);
        r1.setRoleCapability(PAUSER_ROLE, address(t1), TellerWithMultiAssetSupport.pause.selector, true);

        pauser.addContract(address(a1), "BV1");
        pauser.addContract(address(m1), "BV1");
        pauser.addContract(address(t1), "BV1");

        // Deploy 2 "vault" with symbol BV2
        r2 = new RolesAuthority(msg.sender, Authority(address(0))); // Specific authority for vault 2
        console.log("BV2 RolesAuthority: ", address(r2));

        b2 = new BoringVault(msg.sender, "Boring Vault 2", "BV2", 18);
        console.log("BV2 BoringVault: ", address(b2));
        b2.setAuthority(r2);

        a2 = new AccountantWithRateProviders(
            msg.sender, address(b2), msg.sender, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );
        console.log("BV2 Accountant: ", address(a2));
        a2.setAuthority(r2);

        m2 = new ManagerWithMerkleVerification(msg.sender, address(b2), vault);
        console.log("BV2 Manager: ", address(m2));
        m2.setAuthority(r2);

        t2 = new TellerWithMultiAssetSupport(msg.sender, address(b2), address(a2));
        console.log("BV2 Teller: ", address(t2));
        t2.setAuthority(r2);

        r2.setUserRole(address(pauser), PAUSER_ROLE, true);
        r2.setRoleCapability(PAUSER_ROLE, address(a2), AccountantWithRateProviders.pause.selector, true);
        r2.setRoleCapability(PAUSER_ROLE, address(m2), ManagerWithMerkleVerification.pause.selector, true);
        r2.setRoleCapability(PAUSER_ROLE, address(t2), TellerWithMultiAssetSupport.pause.selector, true);

        pauser.addContract(address(a2), "BV2");
        pauser.addContract(address(m2), "BV2");
        pauser.addContract(address(t2), "BV2");

        // Deploy 3 "vault" with symbol BV3
        r3 = new RolesAuthority(msg.sender, Authority(address(0))); // Specific authority for vault 3
        console.log("BV3 RolesAuthority: ", address(r3));

        b3 = new BoringVault(msg.sender, "Boring Vault 3", "BV3", 18);
        console.log("BV3 BoringVault: ", address(b3));
        b3.setAuthority(r3);

        a3 = new AccountantWithRateProviders(
            msg.sender, address(b3), msg.sender, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );
        console.log("BV3 Accountant: ", address(a3));
        a3.setAuthority(r3);

        m3 = new ManagerWithMerkleVerification(msg.sender, address(b3), vault);
        console.log("BV3 Manager: ", address(m3));
        m3.setAuthority(r3);

        t3 = new TellerWithMultiAssetSupport(msg.sender, address(b3), address(a3));
        console.log("BV3 Teller: ", address(t3));
        t3.setAuthority(r3);

        r3.setUserRole(address(pauser), PAUSER_ROLE, true);
        r3.setRoleCapability(PAUSER_ROLE, address(a3), AccountantWithRateProviders.pause.selector, true);
        r3.setRoleCapability(PAUSER_ROLE, address(m3), ManagerWithMerkleVerification.pause.selector, true);
        r3.setRoleCapability(PAUSER_ROLE, address(t3), TellerWithMultiAssetSupport.pause.selector, true);

        pauser.addContract(address(a3), "BV3");
        pauser.addContract(address(m3), "BV3");
        pauser.addContract(address(t3), "BV3");

        vm.stopBroadcast();
    }
}
