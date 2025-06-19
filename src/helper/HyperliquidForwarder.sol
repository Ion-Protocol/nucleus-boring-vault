pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

/**
 * @title Hyperliquid Forwarder
 * @custom:security-contact security@molecularlabs.io
 */
contract HyperliquidForwarder is Auth {
    using SafeTransferLib for ERC20;

    address public constant WHYPE = 0x5555555555555555555555555555555555555555;
    address private constant WHYPE_BRIDGE = 0x2222222222222222222222222222222222222222;

    error HyperliquidForwarder__BridgeNotSet(address token);
    error HyperliquidForwarder__BridgeAddressDoesNotMatchTokenID();
    error HyperliquidForwarder__EOANotAllowed(address eoa);

    event HyperliquidForwarder__EOAAllowStatusUpdated(address eoa, bool allowed);
    event HyperliquidForwarder__ForwardComplete(ERC20 token, uint256 amount, address eoa);
    event HyperliquidForwarder__TokenAddressUpdated(address tokenAddress, address bridgeAddress, uint16 tokenId);

    mapping(address => bool) public eoaAllowlist;
    mapping(address => address) internal tokenAddressToBridge;

    constructor() Auth(msg.sender, Authority(address(0))) {
        // By default add WHYPE exception
        addTokenIDToBridgeMapping(WHYPE, address(0), 0);
    }

    /**
     * @dev require EOA is in the eoaAllowlist
     */
    modifier requireAllowedEOA(address eoa) {
        if (eoaAllowlist[eoa]) {
            _;
        } else {
            revert HyperliquidForwarder__EOANotAllowed(eoa);
        }
    }

    /**
     * @dev To prevent mistakes we only allow approved EOA addresses for forwarding
     * owner may set these addresses
     */
    function setEOAAllowStatus(address eoa, bool allowed) external requiresAuth {
        eoaAllowlist[eoa] = allowed;
        HyperliquidForwarder__EOAAllowStatusUpdated(eoa, allowed);
    }

    /**
     * @dev We require owner adds a new token using the token ID rather than the bridge address itself
     *     in order to require the owner has researched the tokenID rather than copying & pasting addresses,
     *     which could lead to inaccuracies.
     * @dev From Hyperliquid Docs:
     *   tokenBridge is different for each token and there is no onchain programmatic way to determine them:
     *   Every token has a system address on the Core, which is the address with first byte 0x20 and the
     *   remaining bytes all zeros, except for the token index encoded in big-endian format.
     *   For example, for token index 200, the system address would be 0x20000000000000000000000000000000000000c8
     *   Exceptions are:
     *       WHYPE: 0x2222222222222222222222222222222222222222
     */
    function addTokenIDToBridgeMapping(
        address tokenAddress,
        address bridgeAddress,
        uint16 tokenID
    )
        public
        requiresAuth
    {
        // HYPE/WHYPE is an exception and is handled separately, do not allow owner to incorrectly set it
        if (tokenAddress == WHYPE) {
            tokenAddressToBridge[WHYPE] = WHYPE_BRIDGE;
            return;
        }

        // Move the token ID 12 bytes to the left so as to prevent truncating on cast to bytes20
        bytes20 formattedTokenID = bytes20(bytes32(uint256(tokenID)) << 8 * 12);

        // Add the 2 prefix for all bridges and convert bytes20 to address
        address computedBridgeAddress = address(formattedTokenID | hex"2000000000000000000000000000000000000000");

        if (computedBridgeAddress != bridgeAddress) {
            revert HyperliquidForwarder__BridgeAddressDoesNotMatchTokenID();
        }

        // Store the mapping of token address to bridge based off what's created from the ID
        tokenAddressToBridge[tokenAddress] = bridgeAddress;
        HyperliquidForwarder__TokenAddressUpdated(tokenAddress, bridgeAddress, tokenID);
    }

    /**
     * @notice function to forward tokens to the Hyperliquid L1, ensuring they arrive on the desired address (as it
     * matches msg.sender on L1)
     */
    function forward(
        ERC20 token,
        uint256 amount,
        address evmEOAToSendToAndForwardToL1
    )
        external
        requireAllowedEOA(evmEOAToSendToAndForwardToL1)
    {
        address bridge = tokenAddressToBridge[address(token)];
        if (bridge == address(0)) {
            revert HyperliquidForwarder__BridgeNotSet(address(token));
        }

        token.safeTransferFrom(msg.sender, evmEOAToSendToAndForwardToL1, amount);
        token.safeTransferFrom(evmEOAToSendToAndForwardToL1, bridge, amount);
        HyperliquidForwarder__ForwardComplete(token, amount, evmEOAToSendToAndForwardToL1);
    }
}
