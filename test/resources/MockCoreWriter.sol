// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// TODO:due to this being a mock, we can't simulate how the REAL core writer will act.
// So to properly test, a testnet run through of the tests should be done to assert that the controller
// never custodies funds.
contract MockCoreWriter {

    event RawAction(address indexed user, bytes data);
    event MockCoreWriter__LimitOrder(
        uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 encodedTif, uint128 cloid
    );
    event MockCoreWriter__VaultTransfer(address vault, bool isDeposit, uint64 usd);
    event MockCoreWriter__TokenDelegate(address validator, uint64 _wei, bool isUndelegate);
    event MockCoreWriter__StakingDeposit(uint64 _wei);
    event MockCoreWriter__StakingWithdraw(uint64 _wei);
    event MockCoreWriter__SpotSend(address destination, uint64 token, uint64 _wei);
    event MockCoreWriter__UsdClassTransfer(uint64 ntl, bool toPerp);
    event MockCoreWriter__FinalizeEvmContract(
        uint64 token, uint8 encodedFinalizeEvmContractVariant, uint64 createNonce
    );
    event MockCoreWriter__AddApiWallet(address apiWalletAddress, string apiWalletName);

    function sendRawAction(bytes calldata data) external {
        // Spends ~20k gas
        for (uint256 i = 0; i < 400; i++) { }
        emit RawAction(msg.sender, data);
        _handleRawAction(data);
    }

    function _handleRawAction(bytes calldata data) internal {
        require(data[0] == 0x01, "only encoding type 1 supported");
        bytes1 actionID = data[3];

        if (actionID == 0x01) {
            // Limit Order
            (uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 encodedTif, uint128 cloid) =
                abi.decode(data[4:], (uint32, bool, uint64, uint64, bool, uint8, uint128));
            emit MockCoreWriter__LimitOrder(asset, isBuy, limitPx, sz, reduceOnly, encodedTif, cloid);
        } else if (actionID == 0x02) {
            // Vault Transfer
            (address vault, bool isDeposit, uint64 usd) = abi.decode(data[4:], (address, bool, uint64));
            emit MockCoreWriter__VaultTransfer(vault, isDeposit, usd);
        } else if (actionID == 0x03) {
            // Token delegate
            (address validator, uint64 _wei, bool isUndelegate) = abi.decode(data[4:], (address, uint64, bool));
            emit MockCoreWriter__TokenDelegate(validator, _wei, isUndelegate);
        } else if (actionID == 0x04) {
            // Staking deposit
            uint64 _wei = abi.decode(data[4:], (uint64));
            emit MockCoreWriter__StakingDeposit(_wei);
        } else if (actionID == 0x05) {
            // Staking withdraw
            uint64 _wei = abi.decode(data[4:], (uint64));
            emit MockCoreWriter__StakingWithdraw(_wei);
        } else if (actionID == 0x06) {
            // Spot Send
            (address destination, uint64 token, uint64 _wei) = abi.decode(data[4:], (address, uint64, uint64));
            emit MockCoreWriter__SpotSend(destination, token, _wei);
        } else if (actionID == 0x07) {
            // USD Class Transfer
            (uint64 ntl, bool toPerp) = abi.decode(data[4:], (uint64, bool));
            emit MockCoreWriter__UsdClassTransfer(ntl, toPerp);
        } else if (actionID == 0x08) {
            // Finalize EVM Contract
            (uint64 token, uint8 encodedFinalizeEvmContractVariant, uint64 createNonce) =
                abi.decode(data[4:], (uint64, uint8, uint64));
            emit MockCoreWriter__FinalizeEvmContract(token, encodedFinalizeEvmContractVariant, createNonce);
        } else if (actionID == 0x09) {
            // Add API Wallet
            (address apiWalletAddress, string memory apiWalletName) = abi.decode(data[4:], (address, string));
            emit MockCoreWriter__AddApiWallet(apiWalletAddress, apiWalletName);
        }
    }

}
