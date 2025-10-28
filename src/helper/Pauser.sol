// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Pauser is Ownable {

    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Keep an enumerable set of all the vault symbol's hashes
    EnumerableSet.Bytes32Set symbolHashes;

    // Keep an enumerable set of all the addresses associated with each symbol
    mapping(bytes32 => EnumerableSet.AddressSet) symbolHashesToOwnedContracts;

    // Mapping of approved pause addresses
    mapping(address => bool) public isApprovedPauser;

    // Cap to symbols to prevent excessive gas, default to 50 but allow owner to update it
    uint256 public symbolCap = 50;

    event Pauser__FailedPause(address toPause, bytes response);
    event Pauser__AddedContract(address added);
    event Pauser__RemovedContract(address removed);
    event Pauser__FailedPauseEmptyCode(address toPause);
    event Pauser__EmptySymbol(string symbol);

    error Pauser__ContractNotPausableByThis(address x);
    error Pauser__ArrayLengthMismatch();
    error Pauser__Unauthorized();
    error Pauser__InvalidSymbolCap();
    error Pauser__SymbolCapReached();

    constructor(address owner, address[] memory defaultPausers) Ownable(owner) {
        isApprovedPauser[owner] = true;
        uint256 l = defaultPausers.length;
        for (uint256 i; i < l; ++i) {
            isApprovedPauser[defaultPausers[i]] = true;
        }
    }

    // Auth functions
    function addApprovedPausers(address[] calldata newPausers) external onlyOwner {
        for (uint256 i; i < newPausers.length; ++i) {
            isApprovedPauser[newPausers[i]] = true;
        }
    }

    function removeApprovedPausers(address[] calldata pausersToRemove) external onlyOwner {
        for (uint256 i; i < pausersToRemove.length; ++i) {
            isApprovedPauser[pausersToRemove[i]] = false;
        }
    }

    modifier onlyApprovedPauser() {
        if (!isApprovedPauser[msg.sender]) {
            revert Pauser__Unauthorized();
        }
        _;
    }

    // View functions
    function length(string calldata symbol) public view returns (uint256) {
        return symbolHashesToOwnedContracts[keccak256(bytes(symbol))].length();
    }

    function length() public view returns (uint256 l) {
        uint256 symbolLength = symbolHashes.length();

        for (uint256 i; i < symbolLength; ++i) {
            l += symbolHashesToOwnedContracts[symbolHashes.at(i)].length();
        }
    }

    function getAddresses(string calldata symbol) public view returns (address[] memory) {
        return symbolHashesToOwnedContracts[keccak256(bytes(symbol))].values();
    }

    function getAddresses() public view returns (address[][] memory) {
        uint256 symbolLength = symbolHashes.length();
        address[][] memory addresses = new address[][](symbolLength);

        for (uint256 i; i < symbolLength; ++i) {
            addresses[i] = symbolHashesToOwnedContracts[symbolHashes.at(i)].values();
        }

        return addresses;
    }

    // Owner management functions
    function addContract(address newContract, string memory symbol) public onlyOwner {
        if (symbolHashes.length() == symbolCap) {
            revert Pauser__SymbolCapReached();
        }

        bytes32 symbolHash = keccak256(bytes(symbol));

        // adding an existing hash is fine, as the library will do nothing if it exists
        symbolHashes.add(symbolHash);
        symbolHashesToOwnedContracts[symbolHash].add(newContract);

        emit Pauser__AddedContract(newContract);
    }

    function addContracts(string calldata symbol, address[] calldata newContracts) public onlyOwner {
        uint256 l = newContracts.length;

        for (uint256 i; i < l; ++i) {
            addContract(newContracts[i], symbol);
        }
    }

    function removeContract(string calldata symbol, address contractToRemove) public onlyOwner {
        symbolHashesToOwnedContracts[keccak256(bytes(symbol))].remove(contractToRemove);

        emit Pauser__RemovedContract(contractToRemove);
    }

    function removeContracts(string calldata symbol, address[] calldata tokenAddresses) external onlyOwner {
        uint256 l = tokenAddresses.length;

        for (uint256 i; i < l; ++i) {
            removeContract(symbol, tokenAddresses[i]);
        }
    }

    function updateSymbolCap(uint256 newCap) external onlyOwner {
        if (newCap < symbolHashes.length()) {
            revert Pauser__InvalidSymbolCap();
        }

        symbolCap = newCap;
    }

    // Pause functions
    /// @dev pause all contracts
    function pauseAll() external returns (uint256 failingCount) {
        uint256 symbolHashesLength = symbolHashes.length();

        for (uint256 i; i < symbolHashesLength; ++i) {
            bytes32 symbolHash = symbolHashes.at(i);
            uint256 l = symbolHashesToOwnedContracts[symbolHash].length();

            for (uint256 j; j < l; ++j) {
                bool success = pauseSingle(symbolHashesToOwnedContracts[symbolHash].at(j));
                if (!success) {
                    unchecked {
                        ++failingCount;
                    }
                }
            }
        }
    }

    /// @dev pause all contracts for a single symbol
    function pauseSymbol(string calldata symbol) external returns (uint256 failingCount) {
        uint256 l = symbolHashesToOwnedContracts[keccak256(bytes(symbol))].length();
        if (l == 0) {
            emit Pauser__EmptySymbol(symbol);
            return 0;
        }

        for (uint256 i; i < l; ++i) {
            address addr = pauseSingle(symbol, i);
            if (addr != address(0)) {
                unchecked {
                    ++failingCount;
                }
            }
        }
    }

    /// @dev pause for a single contract on a single chain by index
    function pauseSingle(string calldata symbol, uint256 index) public returns (address failingAddressIfFailed) {
        address contractAddress = symbolHashesToOwnedContracts[keccak256(bytes(symbol))].at(index);
        // if success return 0, if not return the contract address
        return pauseSingle(contractAddress) ? address(0) : contractAddress;
    }

    /// @dev pause for a single contract on a single chain by address
    /// NOTE This does not require the address is in the data structure as it's being passed in directly
    function pauseSingle(address contractAddress) public onlyApprovedPauser returns (bool success) {
        if (contractAddress.code.length == 0) {
            emit Pauser__FailedPauseEmptyCode(contractAddress);
            return false;
        }

        bytes memory err;
        (success, err) = contractAddress.call(abi.encodeWithSignature("pause()"));
        if (!success) {
            emit Pauser__FailedPause(contractAddress, err);
        }
    }

}
