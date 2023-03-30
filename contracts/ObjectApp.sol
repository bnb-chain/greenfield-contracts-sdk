// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol";
import "./interface/IObjectHub.sol";

abstract contract ObjectApp is BaseApp {
    /*----------------- constants -----------------*/
    uint8 public constant OBJECT_CHANNEL_ID = 0x05;

    /*----------------- storage -----------------*/
    // system contract
    address public objectHub;

    event DeleteObjectSuccess(uint256 indexed tokenId);
    event DeleteObjectFailed(uint32 status, uint256 indexed tokenId);

    // need initialize

    function greenfieldCall(
        uint32 status,
        uint8 channelId,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override virtual {
        require(msg.sender == crossChain, "ObjectApp: caller is not the crossChain contract");
        require(channelId == OBJECT_CHANNEL_ID, "ObjectApp: channelId is not supported");

        if (operationType == TYPE_DELETE) {
            _deleteObjectCallback(status, resourceId, callbackData);
        } else {
            revert("ObjectApp: operationType is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function retryPackage() external override virtual onlyOperator {
        IObjectHub(objectHub).retryPackage();
    }

    function skipPackage() external override virtual onlyOperator {
        IObjectHub(objectHub).skipPackage();
    }

    /*----------------- internal functions -----------------*/
    function _deleteObject(uint256 _tokenId) internal {
        uint256 totalFee = _getTotalFee();
        IObjectHub(objectHub).deleteObject{value: totalFee}(_tokenId);
    }

    function _deleteObject(uint256 _tokenId, bytes memory _callbackData) internal {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        IObjectHub(objectHub).deleteObject{value: totalFee}(_tokenId, callbackGasLimit, _extraData);
    }

    function _deleteObjectCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
