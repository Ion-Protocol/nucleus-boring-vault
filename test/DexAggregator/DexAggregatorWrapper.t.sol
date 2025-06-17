// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, console } from "@forge-std/Test.sol";
import { DexAggregatorWrapper } from "src/helper/DexAggregatorWrapper.sol";
import { AggregationRouterV6 } from "src/interfaces/AggregationRouterV6.sol";
import { IOKXRouter } from "src/interfaces/IOKXRouter.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RateProviderConfig } from "src/base/Roles/RateProviderConfig.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { IAuthority } from "../../../script/ConfigReader.s.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

string constant DEFAULT_RPC_URL = "L1_RPC_URL";
uint256 constant DEFAULT_BLOCK_NUMBER = 21_949_667;

contract DexAggregatorWrapperTest is Test {
    uint8 public constant ADMIN_ROLE = 2;
    uint8 public constant TELLER_ROLE = 3;
    DexAggregatorWrapper wrapper;
    uint256 constant depositAm = 100_000_000;
    address constant srcToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address constant dstToken = 0x15700B564Ca08D9439C58cA5053166E8317aa138;
    address constant oneInchAgg = 0x111111125421cA6dc452d289314280a0f8842A65;
    address constant executor = 0x5141B82f5fFDa4c6fE1E372978F1C5427640a190;

    // OKX specific addresses
    address constant okxRouter = 0x7D0CcAa3Fac1e5A943c5168b6CEd828691b46B36;
    address constant okxApprover = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;
    address constant okxSrcToken = 0x8236a87084f8B84306f72007F36F2618A5634494; // LBTC
    address constant okxDstToken = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
    uint256 constant okxDepositAm = 500_000_000; // 5 LBTC

    // Mainnet addresses
    address constant MAINNET_MULTISIG = 0x0000000000417626Ef34D62C4DC189b021603f2F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // USD teller related addresses
    address constant USD_VAULT = 0x9fbC367B9Bb966a2A537989817A088AFCaFFDC4c;
    address constant USD_AUTHORITY = 0x1320b933bFcaEBf5C84A47a46d491d612653D807;

    // BTC teller related addresses
    address constant BTC_VAULT = 0x66E47E6957B85Cf62564610B76dD206BB04d831a;
    address constant BTC_AUTHORITY = 0x05FAE28773ab9dAfD5C8997AcEe5099fa0D1f219;

    // function selector needed for public capability on teller
    bytes4 depositSelector = TellerWithMultiAssetSupport.deposit.selector;

    // Custom recipient address
    address recipient;

    // Salt for deterministic deployment - constant for the primary wrapper for API calls
    bytes32 public constant PRIMARY_WRAPPER_SALT = keccak256("OKX_DEX_WRAPPER_V1");

    // Variable salt for test-specific deployments
    bytes32 public testWrapperSalt;

    // Teller contracts
    TellerWithMultiAssetSupport usdTeller;
    TellerWithMultiAssetSupport btcTeller;

    // Accountant contracts
    AccountantWithRateProviders usdAccountant;
    AccountantWithRateProviders btcAccountant;

    RateProviderConfig rateProviderContract;

    // Additional wrappers for test-specific deployments
    DexAggregatorWrapper testWrapper;

    // Flag to track if the primary wrapper has been deployed
    bool isPrimaryWrapperDeployed;

    // Store deployed wrapper addresses
    address payable public primaryWrapperAddress;

    // Store current fork ID
    uint256 public forkId;
    bool public isSetupComplete;

    // Use this function to initialize the test with a specific block number
    function _initializeTest(uint256 blockNumber, bool usePrimaryWrapper) internal {
        if (isSetupComplete) {
            return; // Skip if already initialized
        }

        // Generate a test-specific salt based on the block number to avoid Create2 collisions
        if (!usePrimaryWrapper) {
            testWrapperSalt = keccak256(abi.encodePacked("TEST_WRAPPER", blockNumber));
        }

        forkId = _startFork(DEFAULT_RPC_URL, blockNumber);

        // Create a recipient address
        recipient = makeAddr("recipient");

        // ========== Deploy Accountants ==========
        rateProviderContract = new RateProviderConfig(MAINNET_MULTISIG);

        // Deploy USD accountant
        usdAccountant = new AccountantWithRateProviders(
            MAINNET_MULTISIG, // owner
            USD_VAULT, // boringVault
            MAINNET_MULTISIG, // payout_address
            1e6, // baseRate (1.0)
            srcToken, // USDC
            1.001e4, // conversionBpsUp
            0.999e4, // conversionBpsDown
            1, // priceDecimals
            0, // bpsDecimals
            0, // baseRateDecimals
            rateProviderContract
        );
        console.log("USD Accountant deployed at:", address(usdAccountant));

        // Deploy BTC accountant
        btcAccountant = new AccountantWithRateProviders(
            MAINNET_MULTISIG, // owner
            BTC_VAULT, // boringVault
            MAINNET_MULTISIG, // payout_address
            1e8, // baseRate (1.0)
            okxDstToken, // WBTC
            1.001e4, // conversionBpsUp
            0.999e4, // conversionBpsDown
            1, // priceDecimals
            0, // bpsDecimals
            0, // baseRateDecimals
            rateProviderContract
        );
        console.log("BTC Accountant deployed at:", address(btcAccountant));

        // ========== Deploy New Tellers ==========
        // Deploy USD teller
        usdTeller = new TellerWithMultiAssetSupport(MAINNET_MULTISIG, USD_VAULT, address(usdAccountant));
        console.log("USD Teller deployed at:", address(usdTeller));

        // Deploy BTC teller
        btcTeller = new TellerWithMultiAssetSupport(MAINNET_MULTISIG, BTC_VAULT, address(btcAccountant));
        console.log("BTC Teller deployed at:", address(btcTeller));

        // ========== Set Authorities ==========
        // Impersonate multisig to set authorities
        vm.startPrank(MAINNET_MULTISIG);

        // Set USD teller authority
        IAuthority(address(usdTeller)).setAuthority(USD_AUTHORITY);
        console.log("Set USD teller authority to:", USD_AUTHORITY);

        // Set BTC teller authority
        IAuthority(address(btcTeller)).setAuthority(BTC_AUTHORITY);
        console.log("Set BTC teller authority to:", BTC_AUTHORITY);

        // Set USD Accountant authority
        IAuthority(address(usdAccountant)).setAuthority(USD_AUTHORITY);
        console.log("Set USD accountant authority to:", USD_AUTHORITY);

        // Set BTC Accountant authority
        IAuthority(address(btcAccountant)).setAuthority(BTC_AUTHORITY);
        console.log("Set BTC accountant authority to:", BTC_AUTHORITY);

        vm.stopPrank();

        // ========== Set Roles ==========
        // Set teller role in USD authority
        vm.startPrank(MAINNET_MULTISIG);
        RolesAuthority(USD_AUTHORITY).setUserRole(address(usdTeller), TELLER_ROLE, true);
        console.log("Set USD teller role 3 to true in USD authority");
        RolesAuthority(USD_AUTHORITY).setUserRole(MAINNET_MULTISIG, ADMIN_ROLE, true);
        console.log("Set owner role 2 to true in USD authority");
        RolesAuthority(USD_AUTHORITY).setPublicCapability(address(usdTeller), depositSelector, true);
        console.log("Set USD teller deposit capability to public");
        vm.stopPrank();

        // Set teller role in BTC authority
        vm.startPrank(MAINNET_MULTISIG);
        RolesAuthority(BTC_AUTHORITY).setUserRole(address(btcTeller), TELLER_ROLE, true);
        console.log("Set BTC teller role 3 to true in BTC authority");
        RolesAuthority(BTC_AUTHORITY).setUserRole(MAINNET_MULTISIG, ADMIN_ROLE, true);
        console.log("Set owner role 2 to true in BTC authority");
        RolesAuthority(BTC_AUTHORITY).setPublicCapability(address(btcTeller), depositSelector, true);
        console.log("Set BTC teller deposit capability to public");
        vm.stopPrank();

        // ========== Add Supported Assets ==========
        // Configure USDC as supported asset in USD teller
        vm.startPrank(MAINNET_MULTISIG);
        ERC20[] memory usdAssets = new ERC20[](2);
        usdAssets[0] = ERC20(srcToken);
        usdAssets[1] = ERC20(dstToken);
        uint112[] memory usdRateLimits = new uint112[](2);
        usdRateLimits[0] = type(uint112).max;
        usdRateLimits[1] = type(uint112).max;
        uint128[] memory usdDepositCaps = new uint128[](2);
        usdDepositCaps[0] = type(uint128).max;
        usdDepositCaps[1] = type(uint128).max;
        bool[] memory usdWithdrawStatus = new bool[](2);
        usdWithdrawStatus[0] = true;
        usdWithdrawStatus[1] = true;
        usdTeller.configureAssets(usdAssets, usdRateLimits, usdDepositCaps, usdWithdrawStatus);
        console.log("Added USDC as supported asset in USD teller");
        vm.stopPrank();

        // Configure WBTC as supported asset in BTC teller
        vm.startPrank(MAINNET_MULTISIG);
        ERC20[] memory btcAssets = new ERC20[](1);
        btcAssets[0] = ERC20(okxDstToken);
        uint112[] memory btcRateLimits = new uint112[](1);
        btcRateLimits[0] = type(uint112).max;
        uint128[] memory btcDepositCaps = new uint128[](1);
        btcDepositCaps[0] = type(uint128).max;
        bool[] memory btcWithdrawStatus = new bool[](1);
        btcWithdrawStatus[0] = true;
        btcTeller.configureAssets(btcAssets, btcRateLimits, btcDepositCaps, btcWithdrawStatus);
        console.log("Added WBTC as supported asset in BTC teller");
        vm.stopPrank();

        vm.startPrank(MAINNET_MULTISIG);
        RateProviderConfig.RateProviderData[] memory usdRateProviderData = new RateProviderConfig.RateProviderData[](1);
        usdRateProviderData[0] = RateProviderConfig.RateProviderData(true, address(0), "", 0, type(uint256).max);
        rateProviderContract.setRateProviderData(ERC20(usdAssets[0]), ERC20(dstToken), usdRateProviderData);
        RateProviderConfig.RateProviderData[] memory btcRateProviderData = new RateProviderConfig.RateProviderData[](1);
        btcRateProviderData[0] = RateProviderConfig.RateProviderData(true, address(0), "", 0, type(uint256).max);
        rateProviderContract.setRateProviderData(ERC20(btcAssets[0]), ERC20(okxDstToken), btcRateProviderData);
        vm.stopPrank();

        // ========== Deploy Wrapper ==========
        if (usePrimaryWrapper) {
            // Primary wrapper deployment with constant salt - only do this once per test run
            if (!isPrimaryWrapperDeployed) {
                // Predict the wrapper address before deployment
                primaryWrapperAddress = payable(computeWrapperAddress(PRIMARY_WRAPPER_SALT));
                console.log("Predicted primary wrapper address:", primaryWrapperAddress);

                // Deploy the wrapper using Create2 for deterministic address
                bytes memory bytecode = abi.encodePacked(
                    type(DexAggregatorWrapper).creationCode, abi.encode(oneInchAgg, okxRouter, okxApprover, WETH)
                );

                address payable deployedAddress = payable(Create2.deploy(0, PRIMARY_WRAPPER_SALT, bytecode));
                wrapper = DexAggregatorWrapper(deployedAddress);

                // Verify the addresses match
                assertEq(deployedAddress, primaryWrapperAddress, "Deployed address should match predicted address");
                console.log("Primary wrapper deployed at:", address(wrapper));

                isPrimaryWrapperDeployed = true;
            } else {
                // If already deployed, just use the existing address
                wrapper = DexAggregatorWrapper(payable(primaryWrapperAddress));
                console.log("Using already deployed primary wrapper at:", primaryWrapperAddress);
            }
        } else {
            // Test-specific wrapper with unique salt
            address predictedTestWrapperAddress = computeWrapperAddress(testWrapperSalt);
            console.log("Predicted test wrapper address:", predictedTestWrapperAddress);

            // Deploy a test-specific wrapper
            bytes memory bytecode = abi.encodePacked(
                type(DexAggregatorWrapper).creationCode, abi.encode(oneInchAgg, okxRouter, okxApprover, WETH)
            );

            address payable deployedAddress = payable(Create2.deploy(0, testWrapperSalt, bytecode));
            testWrapper = DexAggregatorWrapper(deployedAddress);

            // Use this wrapper for the test
            wrapper = testWrapper;

            // Verify the addresses match
            assertEq(
                deployedAddress, predictedTestWrapperAddress, "Deployed test wrapper address should match predicted"
            );
            console.log("Test-specific wrapper deployed at:", address(wrapper));
        }

        isSetupComplete = true;
    }

    // Standard setUp with default block number uses primary wrapper
    function setUp() external {
        _initializeTest(DEFAULT_BLOCK_NUMBER, true);
    }

    // Helper method to start a fork with custom block number
    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 newForkId) {
        if (block.chainid == 31_337) {
            newForkId = vm.createFork(vm.envString(rpcKey), blockNumber);
            vm.selectFork(newForkId);
        }
        return newForkId;
    }

    // Helper to switch to a specific block number (creates a new fork)
    function _switchToBlockNumber(uint256 blockNumber) internal returns (uint256 newForkId) {
        newForkId = _startFork(DEFAULT_RPC_URL, blockNumber);
        return newForkId;
    }

    // Function to compute the deterministic address of the wrapper
    function computeWrapperAddress(bytes32 salt) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(DexAggregatorWrapper).creationCode, abi.encode(oneInchAgg, okxRouter, okxApprover, WETH)
        );

        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    // Helper for backward compatibility - uses primary salt
    function computeWrapperAddress() public view returns (address) {
        return computeWrapperAddress(PRIMARY_WRAPPER_SALT);
    }

    function testPredictAddress() external {
        address predictedAddress = computeWrapperAddress();
        console.log("Predicted primary wrapper address:", predictedAddress);
    }

    // Test with specified block number using test-specific wrapper
    function testOneInchWrapperCustomBlock() external {
        // Specific block number for this test
        uint256 customBlockNumber = 21_939_585; // Example block number

        // Reset the fork to the custom block number
        uint256 newForkId = _switchToBlockNumber(customBlockNumber);

        // Re-initialize the test with the new block number and a test-specific wrapper
        isSetupComplete = false; // Force re-initialization
        _initializeTest(customBlockNumber, false); // false = use test-specific wrapper

        AggregationRouterV6.SwapDescription memory desc = AggregationRouterV6.SwapDescription({
            srcToken: ERC20(srcToken),
            dstToken: ERC20(dstToken),
            srcReceiver: payable(executor),
            dstReceiver: payable(address(wrapper)),
            amount: depositAm,
            minReturnAmount: 99_927_739_338_702_407_010,
            flags: 0
        });

        bytes memory data =
            hex"00000000000000000000000000000000000000000000000000007d00001a0020d6bdbf78a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4802a00000000000000000000000000000000000000000000000000000000000000001ee63c1e580e780df05ed3d1d29b35edaf9c8f3131e9f4c799ea0b86991c6218b36c1d19d4a2e9eb0ce3606eb48111111125421ca6dc452d289314280a0f8842a65";

        // Deal tokens to custom recipient
        deal(srcToken, recipient, depositAm);

        uint256 startShareBal = usdTeller.vault().balanceOf(recipient);
        uint256 startVaultDstBal = ERC20(dstToken).balanceOf(address(usdTeller.vault()));
        console.log("startShareBal", startShareBal);
        console.log("startVaultDstBal", startVaultDstBal);

        // Impersonate the recipient to approve tokens
        vm.startPrank(recipient);
        ERC20(srcToken).approve(address(wrapper), depositAm);

        uint256 minimumMint = 99_970_000; // 0.9997 USDC at accountant 1:1 rate

        // Call the wrapper contract from the recipient
        wrapper.depositOneInch(ERC20(dstToken), recipient, usdTeller, minimumMint, executor, desc, data, 0);

        // Check the share balance of the recipient
        uint256 endShareBal = usdTeller.vault().balanceOf(recipient);
        console.log("endShareBal", endShareBal);
        assertGe(endShareBal, minimumMint, "should have greater than or equal to minimum mint vault shares");
        assertGt(
            ERC20(dstToken).balanceOf(address(usdTeller.vault())),
            startVaultDstBal + 99_927_739_338_702_407_010,
            "should have deposited tokens greater than minReturnAmount"
        );
        assertEq(ERC20(srcToken).balanceOf(recipient), 0, "should have no source tokens left");
        vm.stopPrank();
    }

    function testOkxWrapperWithRealDataCustomBlock() external {
        uint256 newForkId = _switchToBlockNumber(DEFAULT_BLOCK_NUMBER);

        // Re-initialize the test with the new block number and a test-specific wrapper
        isSetupComplete = false; // Force re-initialization
        _initializeTest(DEFAULT_BLOCK_NUMBER, false); // false = use test-specific wrapper

        // This would be the transaction data from the OKX API
        bytes memory realOkxTxData =
            hex"b80c2f09000000000000000000000000000000000000000000000000000000000001ad0a0000000000000000000000008236a87084f8b84306f72007f36f2618a56344940000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000000000000000000000000000000000001dcd6500000000000000000000000000000000000000000000000000000000001d83cad70000000000000000000000000000000000000000000000000000000067c29c9f000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000165a0bc00000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000000017d78400000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000005a00000000000000000000000000000000000000000000000000000000000000ae00000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000002200000000000000000000000008236a87084f8b84306f72007f36f2618a56344940000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ecd7eef15713997528896cb5db7ec316db4c2101000000000000000000000000ecd7eef15713997528896cb5db7ec316db4c21010000000000000000000000004347b972898b2fd780adbdaa29b4a5160a9f4fe50000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ecd7eef15713997528896cb5db7ec316db4c2101000000000000000000000000ecd7eef15713997528896cb5db7ec316db4c21010000000000000000000000004347b972898b2fd780adbdaa29b4a5160a9f4fe50000000000000000000000000000000000000000000000000000000000000003000000000000000000001388abaf76590478f2fe0b396996f55f0b61101e9502000000000000000000000a282f3bc4c27a4437aeca13de0e37cdf1028f3706f08000000000000000000009600b599ebf4e05af48b56d38e2dde520570c36646000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000008236a87084f8b84306f72007f36f2618a56344940000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000008236a87084f8b84306f72007f36f2618a56344940000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000600000000000000000000000008236a87084f8b84306f72007f36f2618a56344940000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001600000000000000000000000008236a87084f8b84306f72007f36f2618a563449400000000000000000000000000000000000000000000000000000000000000010000000000000000000000004347b972898b2fd780adbdaa29b4a5160a9f4fe500000000000000000000000000000000000000000000000000000000000000010000000000000000000000004347b972898b2fd780adbdaa29b4a5160a9f4fe50000000000000000000000000000000000000000000000000000000000000001800000000000000000002710f93bd55717b426a69badeb6458a07739c1d7a85f0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000600000000000000000000000008236a87084f8b84306f72007f36f2618a5634494000000000000000000000000657e8c867d8b37dcc18fa4caead9c45eb088c64200000000000000000000000000000000000000000000000000000000000001f400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000160000000000000000000000000657e8c867d8b37dcc18fa4caead9c45eb088c6420000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ecd7eef15713997528896cb5db7ec316db4c21010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ecd7eef15713997528896cb5db7ec316db4c210100000000000000000000000000000000000000000000000000000000000000010000000000000000000027107704d01908afd31bf647d969c295bb45230cd2d60000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000657e8c867d8b37dcc18fa4caead9c45eb088c6420000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000024000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001600000000000000000000000008236a87084f8b84306f72007f36f2618a5634494000000000000000000000000000000000000000000000000000000000000000100000000000000000000000097a7f8be1364759266cc5a619772458cc126b612000000000000000000000000000000000000000000000000000000000000000100000000000000000000000097a7f8be1364759266cc5a619772458cc126b6120000000000000000000000000000000000000000000000000000000000000001000000000000000000002710c8f989e9b7ece1b4d092ae4db7faf1294146bda40000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000400000000000000000000000008236a87084f8b84306f72007f36f2618a5634494000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000160000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf000000000000000000000000000000000000000000000000000000000000000100000000000000000000000097a7f8be1364759266cc5a619772458cc126b612000000000000000000000000000000000000000000000000000000000000000100000000000000000000000097a7f8be1364759266cc5a619772458cc126b61200000000000000000000000000000000000000000000000000000000000000018000000000000000000027103c0441b42195f4ad6aa9a0978e06096ea616cda7000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000040000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf0000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000000000000000000000000000000000000000000000";

        // Deal tokens to custom recipient
        deal(okxSrcToken, recipient, okxDepositAm);

        uint256 startShareBal = btcTeller.vault().balanceOf(recipient);
        uint256 startVaultDstBal = ERC20(okxDstToken).balanceOf(address(btcTeller.vault()));
        console.log("startShareBal", startShareBal);
        console.log("startVaultDstBal", startVaultDstBal);

        // Impersonate the recipient to approve tokens
        vm.startPrank(recipient);
        ERC20(okxSrcToken).approve(address(wrapper), okxDepositAm);

        uint256 minimumMint = 500_178_000; // 5.00178 WBTC at accountant 1:1 rate

        // Execute the swap with real transaction data
        wrapper.depositOkxUniversal(
            ERC20(okxDstToken),
            recipient, // Use custom recipient
            btcTeller,
            minimumMint,
            okxSrcToken,
            okxDepositAm,
            realOkxTxData,
            0
        );

        // Check the share balance of the recipient
        uint256 endShareBal = btcTeller.vault().balanceOf(recipient);
        console.log("endShareBal", endShareBal);
        assertGe(endShareBal, minimumMint, "should have greater than or equal to minimum mint vault shares");
        assertGt(
            ERC20(okxDstToken).balanceOf(address(btcTeller.vault())),
            startVaultDstBal + 500_000_000,
            "should have deposited tokens greater than expected wbtc return"
        );
        assertEq(ERC20(okxSrcToken).balanceOf(recipient), 0, "should have no source tokens left");
        vm.stopPrank();
    }
}
