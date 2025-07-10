// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { HLPAccount } from "src/whlp-automation/HLPAccount.sol";
import { ICreateX } from "lib/createx/src/ICreateX.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { console } from "@forge-std/Test.sol";

contract HLPController is Auth {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private accountsSet;
    ICreateX public constant CREATEX = ICreateX(0x1077f8ea07EA34D9F23BC39256BF234665FB391f);

    address public immutable coreWriter;
    bytes32 public currentSalt;

    event HLPController__NewAccount(HLPAccount indexed account);

    error HLPAccount__AccountNotInSet(HLPAccount account);

    constructor(address _boringVault, address _coreWriter) Auth(_boringVault, Authority(address(0))) {
        coreWriter = _coreWriter;
        currentSalt = abi.decode(abi.encodePacked(address(this), bytes1(0x00), bytes11(0)), (bytes32));
    }

    modifier requireAccountInSet(HLPAccount account) {
        if (containsAccount(address(account))) {
            _;
        } else {
            revert HLPAccount__AccountNotInSet(account);
        }
    }

    /**
     * @dev deploy a number of new accounts
     */
    function deployAccounts(uint256 number) external requiresAuth {
        for (uint256 i; i < number; ++i) {
            _deployAccount();
        }
    }

    /**
     * @dev this should be called after the account has already received funds in spot
     * NOTE if toPerp fails here, deposit may still succeed and vis versa
     */
    function deposit(HLPAccount account, uint64 amount) external requiresAuth requireAccountInSet(account) {
        account.toPerp(amount);
        account.depositHLP(amount);
    }

    /**
     * @dev withdraws and converts the perp funds to spot
     */
    function withdraw(HLPAccount account, uint64 amount) external requiresAuth requireAccountInSet(account) {
        account.withdrawHLP(amount);
        account.toSpot(amount);
    }

    /**
     * @dev function to do a USD Class Transfer, to/from perp
     */
    function USDClassTransfer(
        HLPAccount account,
        uint64 amount,
        bool toPerp
    )
        external
        requiresAuth
        requireAccountInSet(account)
    {
        if (toPerp) {
            account.toPerp(amount);
        } else {
            account.toSpot(amount);
        }
    }

    /**
     * @dev function to deposit or withdraw from HLP
     */
    function transferHLP(
        HLPAccount account,
        uint64 amount,
        bool isDeposit
    )
        external
        requiresAuth
        requireAccountInSet(account)
    {
        if (isDeposit) {
            account.depositHLP(amount);
        } else {
            account.withdrawHLP(amount);
        }
    }

    /**
     * @dev sends the owner (vault) the specified funds
     */
    function sendToVault(HLPAccount account, uint64 amount) external requiresAuth requireAccountInSet(account) {
        account.withdrawSpot(amount);
    }

    /**
     * @dev getter for length of account set
     */
    function getAccountsCount() external view returns (uint256) {
        return accountsSet.length();
    }

    /**
     * @dev getter for account
     */
    function getAccountAt(uint256 index) external view returns (address) {
        return accountsSet.at(index);
    }

    /**
     * @dev getter for if an account exists in set
     */
    function containsAccount(address account) public view returns (bool) {
        return accountsSet.contains(account);
    }

    /**
     * @dev helper function to deploy a vault using CREATEX
     */
    function _deployAccount() internal {
        bytes memory creationCode =
            abi.encodePacked(type(HLPAccount).creationCode, abi.encode(address(this), owner, coreWriter));
        address account = CREATEX.deployCreate3(currentSalt, creationCode);
        currentSalt = bytes32(uint256(currentSalt) + 1);

        accountsSet.add(account);
        emit HLPController__NewAccount(HLPAccount(account));
    }
}
