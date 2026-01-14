// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

/**
 * @title VerboseAuth
 * @notice A verbose version of the solmate Auth contract
 * @author Based on Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol)
 */
abstract contract VerboseAuth {

    address public owner;

    Authority public authority;

    event OwnershipTransferred(address indexed user, address indexed newOwner);

    event AuthorityUpdated(address indexed user, Authority indexed newAuthority);

    error Unauthorized(address caller, bytes data, string reasons);

    constructor(address _owner, Authority _authority) {
        owner = _owner;
        authority = _authority;

        emit OwnershipTransferred(msg.sender, _owner);
        emit AuthorityUpdated(msg.sender, _authority);
    }

    /// @notice similar to requiresAuth but with a more verbose custom error
    modifier requiresAuthVerbose() virtual {
        (bool canCall, string memory reasons) = isAuthorizedVerbose(msg.sender, msg.data);
        if (canCall) {
            _;
        } else {
            revert Unauthorized(msg.sender, msg.data, reasons);
        }
    }

    /// @notice set a new Authority for this contract
    function setAuthority(Authority newAuthority) public virtual {
        // We check if the caller is the owner first because we want to ensure they can
        // always swap out the authority even if it's reverting or using up a lot of gas.
        if (msg.sender != owner) {
            if (address(authority) == address(0)) {
                revert Unauthorized(msg.sender, msg.data, "- No Authority Set: Owner Only ");
            }
            (bool canCall,) = authority.canCallVerbose(msg.sender, address(this), msg.data);
            if (!canCall) {
                revert Unauthorized(msg.sender, msg.data, "- Not authorized");
            }
        }

        authority = newAuthority;

        emit AuthorityUpdated(msg.sender, newAuthority);
    }

    /// @notice identical to solmate Auth
    function transferOwnership(address newOwner) public virtual requiresAuthVerbose {
        owner = newOwner;

        emit OwnershipTransferred(msg.sender, newOwner);
    }

    /**
     * @notice follows same logic of solmate Auth but to return bool + reason string
     * @dev Owner is always authorized
     */
    function isAuthorizedVerbose(
        address user,
        bytes calldata data
    )
        public
        view
        virtual
        returns (bool canCall, string memory reasons)
    {
        if (user == owner) return (true, "");

        Authority auth = Authority(address(authority));

        if (address(auth) == address(0)) return (false, "- No Authority Set: Owner Only ");

        return auth.canCallVerbose(user, address(this), data);
    }

}

/**
 * @notice A generic interface for a contract which provides authorization data to an Auth instance with more verbosity
 * @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol)
 */
interface Authority {

    function canCallVerbose(
        address user,
        address target,
        bytes calldata data
    )
        external
        view
        returns (bool, string memory);

}

