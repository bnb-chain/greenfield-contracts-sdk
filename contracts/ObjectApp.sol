// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol";
import "./interface/IObjectHub.sol";

abstract contract ObjectApp is BaseApp {
    /*----------------- constants -----------------*/
    uint8 public constant RESOURCE_OBJECT = 0x05;

    /*----------------- storage -----------------*/
    // system contract
    address public objectHub;

    event DeleteObjectSuccess(uint256 indexed tokenId);
    event DeleteObjectFailed(uint32 status, uint256 indexed tokenId);

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual override {
        require(msg.sender == crossChain, string.concat("ObjectApp: ", ERROR_INVALID_CALLER));
        require(resourceType == RESOURCE_OBJECT, string.concat("ObjectApp: ", ERROR_INVALID_RESOURCE));

        _objectGreenfieldCall(status, operationType, resourceId, callbackData);
    }

    /*----------------- internal functions -----------------*/
    function _objectGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal virtual {
        if (operationType == TYPE_DELETE) {
            _deleteObjectCallback(status, resourceId, callbackData);
        } else {
            revert(string.concat("ObjectApp: ", ERROR_INVALID_OPERATION));
        }
    }

    function _retryObjectPackage() internal virtual {
        IObjectHub(objectHub).retryPackage();
    }

    function _skipObjectPackage() internal virtual {
        IObjectHub(objectHub).skipPackage();
    }

    function _deleteObject(uint256 _tokenId) internal {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("ObjectApp: ", ERROR_INSUFFICIENT_VALUE));
        IObjectHub(objectHub).deleteObject{value: msg.value}(_tokenId);
    }

    function _deleteObject(uint256 _tokenId, bytes memory _callbackData) internal {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("ObjectApp: ", ERROR_INSUFFICIENT_VALUE));
        IObjectHub(objectHub).deleteObject{value: msg.value}(_tokenId, callbackGasLimit, _extraData);
    }

    function _deleteObjectCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
