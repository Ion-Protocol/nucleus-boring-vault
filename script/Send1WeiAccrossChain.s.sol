// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

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
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { CrossChainTellerBase } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@forge-std/Script.sol";
import "@forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address, uint256) external;
}

/**
 *  source .env && forge script script/DeployTestBoringVault.s.sol:DeployTestBoringVaultScript --with-gas-price
 * 30000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify
 * @dev Optionally can change --with-gas-price to something more reasonable
 */
contract TestScript is Script {
    uint256 public privateKey;
    address broadcaster;

    CrossChainTellerBase teller;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        broadcaster = vm.addr(privateKey);
    }

    function run() external {
        vm.startBroadcast(privateKey);

        ERC20 NATIVE = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        ERC20 WETH = ERC20(0xFC00000000000000000000000000000000000006);
        // ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // ERC20 WETH = ERC20(0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000);
        address BORING_VAULT = 0x647Ea8b492832e9D99A06DE8cc9A05e58FcCdF02;
        address TELLER = 0xD9395622c8Ec792D1cb6F39B562095fDa240BA57;

        teller = CrossChainTellerBase(TELLER);

        require(teller.isSupported(WETH), "asset not supported");

        // WETH.approve(BORING_VAULT, 1 ether);
        // payable(address(WETH)).call{value: 1}("");
        // require(WETH.balanceOf(broadcaster) > 1, "No WETH");

        // teller.deposit(WETH, 1000000000, 1000000000);
        BridgeData memory data = BridgeData({
            chainSelector: 30_101,
            destinationChainReceiver: broadcaster,
            bridgeFeeToken: NATIVE,
            messageGas: 100_000,
            data: ""
        });

        uint256 fee = teller.previewFee(1, data);

        // teller.depositAndBridge{ value: fee }(WETH, 1, 1, data);
        teller.bridge{ value: fee }(1, data);
        // boring_vault = new BoringVault(owner, "Test Boring Vault", "BV", 18);

        // manager = new ManagerWithMerkleVerification(owner, address(boring_vault), balancerVault);
    }
}
