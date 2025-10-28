// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { QueueDeprecateableRolesAuthority } from "src/helper/one-to-one-queue/QueueDeprecateableRolesAuthority.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { OneToOneQueueTestBase, tERC20 } from "../OneToOneQueueTestBase.t.sol";

contract OneToOneQueueTest is OneToOneQueueTestBase {

    function test_SetFeeModule() external {
        address oldFeeModule = queue.feeModule();
        assertEq(oldFeeModule, address(feeModule));

        SimpleFeeModule newFeeModule = new SimpleFeeModule(TEST_OFFER_FEE_PERCENTAGE);
        vm.expectRevert("UNAUTHORIZED");
        queue.setFeeModule(address(newFeeModule));

        vm.startPrank(owner);
        vm.expectRevert(OneToOneQueue.ZeroAddress.selector);
        queue.setFeeModule(address(0));

        vm.expectEmit();
        emit OneToOneQueue.FeeModuleUpdated(oldFeeModule, address(newFeeModule));
        queue.setFeeModule(address(newFeeModule));
        assertEq(queue.feeModule(), address(newFeeModule));
        vm.stopPrank();
    }

    function test_SetFeeRecipient() external {
        address oldFeeRecipient = queue.feeRecipient();
        address newFeeRecipient = makeAddr("new fee recipient");
        assertEq(oldFeeRecipient, feeRecipient);

        vm.expectRevert("UNAUTHORIZED");
        queue.setFeeRecipient(address(newFeeRecipient));

        vm.startPrank(owner);
        vm.expectRevert(OneToOneQueue.ZeroAddress.selector);
        queue.setFeeRecipient(address(0));

        vm.expectEmit(true, true, true, true);
        emit OneToOneQueue.FeeRecipientUpdated(oldFeeRecipient, address(newFeeRecipient));
        queue.setFeeRecipient(address(newFeeRecipient));
        assertEq(queue.feeRecipient(), address(newFeeRecipient));
        vm.stopPrank();
    }

    function test_AddOfferAsset() external {
        address oldOfferAsset = address(USDC);
        address newOfferAsset = address(new tERC20(6));
        assertEq(queue.supportedOfferAssets(address(USDC)), true);

        vm.expectRevert("UNAUTHORIZED");
        queue.addOfferAsset(newOfferAsset, 12);

        vm.startPrank(owner);
        vm.expectRevert(OneToOneQueue.ZeroAddress.selector);
        queue.addOfferAsset(address(0), 0);

        vm.expectEmit(true, true, true, true);
        emit OneToOneQueue.OfferAssetAdded(newOfferAsset, 12);
        queue.addOfferAsset(newOfferAsset, 12);
        assertEq(queue.supportedOfferAssets(newOfferAsset), true);
        assertEq(queue.minimumOrderSizePerAsset(newOfferAsset), 12);

        vm.expectRevert(abi.encodeWithSelector(OneToOneQueue.AssetAlreadySupported.selector, newOfferAsset));
        queue.addOfferAsset(newOfferAsset, 12);
        vm.stopPrank();
    }

    function test_UpdateAssetMinimumOrderSize() external {
        uint256 oldMinimum = queue.minimumOrderSizePerAsset(address(USDC));
        uint256 newMinimum = 12;

        vm.expectRevert("UNAUTHORIZED");
        queue.updateAssetMinimumOrderSize(address(USDC), newMinimum);

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(OneToOneQueue.AssetNotSupported.selector, address(0)));
        queue.updateAssetMinimumOrderSize(address(0), 12);

        vm.expectEmit(true, true, true, true);
        emit OneToOneQueue.MinimumOrderSizeUpdated(address(USDC), 0, 12);
        queue.updateAssetMinimumOrderSize(address(USDC), newMinimum);
        assertEq(queue.minimumOrderSizePerAsset(address(USDC)), newMinimum);
        vm.stopPrank();
    }

    function test_RemoveOfferAsset() external {
        address oldOfferAsset = address(USDC);
        assertEq(queue.supportedOfferAssets(address(USDC)), true);

        vm.expectRevert("UNAUTHORIZED");
        queue.removeOfferAsset(address(USDC));

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit OneToOneQueue.OfferAssetRemoved(address(USDC));
        queue.removeOfferAsset(address(USDC));
        assertFalse(queue.supportedOfferAssets(address(USDC)));
        vm.stopPrank();
    }

    function test_AddWantAsset() external {
        address oldWantAsset = address(USDG0);
        address newWantAsset = address(new tERC20(6));
        assertEq(queue.supportedWantAssets(address(USDG0)), true);

        vm.expectRevert("UNAUTHORIZED");
        queue.addWantAsset(newWantAsset);

        vm.startPrank(owner);
        vm.expectRevert(OneToOneQueue.ZeroAddress.selector);
        queue.addWantAsset(address(0));

        vm.expectEmit(true, true, true, true);
        emit OneToOneQueue.WantAssetAdded(newWantAsset);
        queue.addWantAsset(newWantAsset);
        assertEq(queue.supportedWantAssets(newWantAsset), true);

        vm.expectRevert(abi.encodeWithSelector(OneToOneQueue.AssetAlreadySupported.selector, newWantAsset));
        queue.addWantAsset(newWantAsset);
        vm.stopPrank();
    }

    function test_RemoveWantAsset() external {
        address oldWantAsset = address(USDG0);
        assertEq(queue.supportedWantAssets(address(USDG0)), true);

        vm.expectRevert("UNAUTHORIZED");
        queue.removeWantAsset(address(USDG0));

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit OneToOneQueue.WantAssetRemoved(address(USDG0));
        queue.removeWantAsset(address(USDG0));
        assertFalse(queue.supportedWantAssets(address(USDG0)));
        vm.stopPrank();
    }

    function test_UpdateOfferAssetRecipient() external {
        address oldOfferAssetRecipient = queue.offerAssetRecipient();
        address newOfferAssetRecipient = makeAddr("new offer asset recipient");
        assertEq(oldOfferAssetRecipient, mockBoringVaultAddress);

        vm.expectRevert("UNAUTHORIZED");
        queue.updateOfferAssetRecipient(address(newOfferAssetRecipient));

        vm.startPrank(owner);
        vm.expectRevert(OneToOneQueue.ZeroAddress.selector);
        queue.updateOfferAssetRecipient(address(0));

        vm.expectEmit(true, true, true, true);
        emit OneToOneQueue.OfferAssetRecipientUpdated(oldOfferAssetRecipient, address(newOfferAssetRecipient));
        queue.updateOfferAssetRecipient(address(newOfferAssetRecipient));
        assertEq(queue.offerAssetRecipient(), address(newOfferAssetRecipient));
        vm.stopPrank();
    }

}
