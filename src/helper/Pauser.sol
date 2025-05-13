// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { console } from "@forge-std/Test.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Pauser {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Keep an enumerable set of all the vault symbols
    EnumerableSet.Bytes32Set symbolHashes;

    // Keep an enumerable set of all the addresses associated with each symbol
    mapping(bytes32 => EnumerableSet.AddressSet) symbolHashesToOwnedContracts;

    address public constant DELETED = address(0xdead);

    event Pauser__FailedPause(address toPause, bytes response);
    event Pauser__AddedContract(address added);
    event Pauser__RemovedContract(address removed);

    error Pauser__ContractNotPausableByThis(address x);
    error Pauser__ArrayLengthMismatch();

    function length(string calldata symbol) public view returns (uint256) {
        return symbolHashesToOwnedContracts[keccak256(bytes(symbol))].length();
    }

    function length() public view returns (uint256 l) {
        uint256 symbolLength = symbolHashes.length();

        for (uint256 i; i < symbolLength; ++i) {
            l += symbolHashesToOwnedContracts[symbolHashes.at(i)].length();
        }
    }

    function addContract(address newContract, string memory symbol) public {
        address pausableContract = newContract;

        // (bool success, bytes memory response) =
        // address(pausableContract).staticcall(abi.encodeWithSignature("pause()"));

        // if(!success){
        //     console.logBytes(response);
        //     revert Pauser__ContractNotPausableByThis(pausableContract);
        // }

        bytes32 symbolHash = keccak256(bytes(symbol));
        symbolHashes.add(symbolHash);
        symbolHashesToOwnedContracts[symbolHash].add(address(pausableContract));

        emit Pauser__AddedContract(pausableContract);
    }

    function addContracts(address[] calldata newContracts, string[] calldata associatedVaultSymbols) public {
        uint256 l = newContracts.length;
        if (l != associatedVaultSymbols.length) {
            revert Pauser__ArrayLengthMismatch();
        }

        for (uint256 i; i < l; ++i) {
            addContract(newContracts[i], associatedVaultSymbols[i]);
        }
    }

    function removeContract(string calldata symbol, address contractToRemove) public {
        symbolHashesToOwnedContracts[keccak256(bytes(symbol))].remove(contractToRemove);

        emit Pauser__RemovedContract(contractToRemove);
    }

    function removeContracts(string[] calldata symbols, address[] calldata tokenAddresses) external {
        for (uint256 i; i < symbols.length; ++i) {
            for (uint256 j; j < tokenAddresses.length; ++j) {
                symbolHashesToOwnedContracts[keccak256(bytes(symbols[i]))].remove(tokenAddresses[j]);
                emit Pauser__RemovedContract(tokenAddresses[j]);
            }
        }
    }

    /// @dev pause all contracts
    function pauseAll() external returns (bool success) {
        success = true;
        uint256 symbolHashesLength = symbolHashes.length();

        for (uint256 i; i < symbolHashesLength; ++i) {
            bytes32 symbolHash = symbolHashes.at(i);
            uint256 l = symbolHashesToOwnedContracts[symbolHash].length();

            for (uint256 j; j < l; ++j) {
                success = pauseSingle(symbolHashesToOwnedContracts[symbolHash].at(j)) ? success : false;
            }
        }
    }

    /// @dev pause all contracts for a single symbol
    function pauseAll(string calldata symbol) external returns (bool success) {
        return pauseRange(symbol, 0, length(symbol));
    }

    /// @dev pause a range of contracts for a single symbol
    function pauseRange(string calldata symbol, uint256 start, uint256 end) public returns (bool success) {
        // If range is 0-0 like when we pauseAll("NONEXISTENT_SYMBOL") this returns true...
        // But it IS true. We paused nothing for a symbol where we have nothing to pause.
        // Curious opinions here for erroring? Maybe a unique error?
        success = true;
        for (uint256 i = start; i < end; ++i) {
            // if pausing fails, success is false, otherwise it remains the same
            success = pauseSingle(symbol, i) ? success : false;
        }
    }

    /// @dev pause for a single contract on a single chain by index
    function pauseSingle(string calldata symbol, uint256 index) public returns (bool success) {
        return pauseSingle(symbolHashesToOwnedContracts[keccak256(bytes(symbol))].at(index));
    }

    /// @dev pause for a single contract on a single chain by address
    /// NOTE This does not require the address is in the data structure as it's being passed in directly
    function pauseSingle(address contractAddress) public returns (bool success) {
        bytes memory err;
        (success, err) = contractAddress.call(abi.encodeWithSignature("pause()"));
        if (!success) {
            emit Pauser__FailedPause(contractAddress, err);
        }
    }
}
