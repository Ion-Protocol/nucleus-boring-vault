// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

abstract contract SpectraDecoderAndSanitizer {

    // @desc deposit base asset in Spectra PT without minShares specified
    // @tag ptReceiver:address:address of the ptReceiver
    // @tag ytReceiver:address:address of the ytReceiver
    function deposit(
        uint256,
        address ptReceiver,
        address ytReceiver
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(ptReceiver, ytReceiver);
    }

    // @desc deposit base asset in Spectra PT with minShares specified
    // @tag ptReceiver:address:address of the ptReceiver
    // @tag ytReceiver:address:address of the ytReceiver
    function deposit(
        uint256,
        address ptReceiver,
        address ytReceiver,
        uint256
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(ptReceiver, ytReceiver);
    }

    // @desc deposit IBT in Spectra PT without minShares specified
    // @tag ptReceiver:address:address of the ptReceiver
    // @tag ytReceiver:address:address of the ytReceiver
    function depositIBT(
        uint256,
        address ptReceiver,
        address ytReceiver
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(ptReceiver, ytReceiver);
    }

    // @desc deposit IBT in Spectra PT with minShares specified
    // @tag ptReceiver:address:address of the ptReceiver
    // @tag ytReceiver:address:address of the ytReceiver
    function depositIBT(
        uint256,
        address ptReceiver,
        address ytReceiver,
        uint256
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(ptReceiver, ytReceiver);
    }

    // @desc redeem some PT AND YT for IBT tokens on Spectra
    // @tag receiver:address:receiver of the IBT tokens
    // @tag owner:address:shares are burned from the owner address
    function redeem(
        uint256,
        address receiver,
        address owner
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(receiver, owner);
    }

    // @desc redeem some PT AND YT for IBT tokens on Spectra with min assets specified
    // @tag receiver:address:receiver of the IBT tokens
    // @tag owner:address:shares are burned from the owner address
    function redeem(
        uint256,
        address receiver,
        address owner,
        uint256
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(receiver, owner);
    }

    // @desc redeem some PT AND YT for IBT tokens on Spectra without minIbts specified
    // @tag receiver:address:receiver of the IBT tokens
    // @tag owner:address:shares are burned from the owner address
    function redeemForIBT(uint256, address receiver, address owner)
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(receiver, owner);
    }

    // @desc redeem some PT AND YT for IBT tokens on Spectra with minIbts specified
    // @tag receiver:address:receiver of the IBT tokens
    // @tag owner:address:shares are burned from the owner address
    function redeemForIBT(
        uint256,
        address receiver,
        address owner,
        uint256
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(receiver, owner);
    }

    // @desc withdraw assets from Spectra PT without maxShares specified
    // @tag receiver:address:receiver of the assets
    // @tag owner:address:shares are burned from the owner address
    function withdraw(
        uint256,
        address receiver,
        address owner
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(receiver, owner);
    }

    // @desc withdraw assets from Spectra PT with maxShares specified
    // @tag receiver:address:receiver of the assets
    // @tag owner:address:shares are burned from the owner address
    function withdraw(
        uint256,
        address receiver,
        address owner,
        uint256
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(receiver, owner);
    }

    // @desc withdraw IBT tokens from Spectra PT without maxShares specified
    // @tag receiver:address:receiver of the IBT tokens
    // @tag owner:address:shares are burned from the owner address
    function withdrawIBT(uint256, address receiver, address owner) external pure returns (bytes memory addressesFound) {
        return abi.encodePacked(receiver, owner);
    }

    // @desc withdraw IBT tokens from Spectra PT with maxShares specified
    // @tag receiver:address:receiver of the IBT tokens
    // @tag owner:address:shares are burned from the owner address
    function withdrawIBT(
        uint256,
        address receiver,
        address owner,
        uint256
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        return abi.encodePacked(receiver, owner);
    }

    // @desc claim yield from Spectra PT
    // @tag _receiver:address:receiver of the yield assets
    function claimYield(address _receiver, uint256) external pure returns (bytes memory addressesFound) {
        return abi.encodePacked(_receiver);
    }

    // @desc claim yield in IBT from Spectra PT
    // @tag _receiver:address:receiver of the yield IBT tokens
    function claimYieldInIBT(address _receiver, uint256) external pure returns (bytes memory addressesFound) {
        return abi.encodePacked(_receiver);
    }

}
