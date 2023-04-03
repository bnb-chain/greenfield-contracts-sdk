// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol";
import "./interface/IBucketHub.sol";

abstract contract BucketApp is BaseApp {
    /*----------------- constants -----------------*/
    uint8 public constant RESOURCE_BUCKET = 0x04;

    /*----------------- storage -----------------*/
    address public bucketHub;
    address public paymentAddress;

    event CreateBucketSuccess(bytes bucketName, uint256 indexed tokenId);
    event CreateBucketFailed(uint32 status, bytes bucketName);
    event DeleteBucketSuccess(uint256 indexed tokenId);
    event DeleteBucketFailed(uint32 status, uint256 indexed tokenId);

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual override {
        require(msg.sender == crossChain, string.concat("BucketApp: ", ERROR_INVALID_CALLER));
        require(resourceType == RESOURCE_BUCKET, string.concat("BucketApp: ", ERROR_INVALID_RESOURCE));

        _bucketGreenfieldCall(status, operationType, resourceId, callbackData);
    }

    /*----------------- internal functions -----------------*/
    function _bucketGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal virtual {
        if (operationType == TYPE_CREATE) {
            _createBucketCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_DELETE) {
            _deleteBucketCallback(status, resourceId, callbackData);
        } else {
            revert(string.concat("BucketApp: ", ERROR_INVALID_OPERATION));
        }
    }

    function _retryBucketPackage() internal virtual {
        IBucketHub(bucketHub).retryPackage();
    }

    function _skipBucketPackage() internal virtual {
        IBucketHub(bucketHub).skipPackage();
    }

    function _setPaymentAddress(address _paymentAddress) internal {
        paymentAddress = _paymentAddress;
    }

    function _createBucket(
        address _creator,
        string memory _name,
        BucketStorage.BucketVisibilityType _visibility,
        uint64 _chargedReadQuota,
        address _spAddress,
        uint256 _expireHeight,
        bytes calldata _sig
    ) internal {
        BucketStorage.CreateBucketSynPackage memory createPkg = BucketStorage.CreateBucketSynPackage({
            creator: _creator,
            name: _name,
            visibility: _visibility,
            paymentAddress: paymentAddress,
            primarySpAddress: _spAddress,
            primarySpApprovalExpiredHeight: _expireHeight,
            primarySpSignature: _sig,
            chargedReadQuota: _chargedReadQuota,
            extraData: ""
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).createBucket{value: msg.value}(createPkg);
    }

    function _createBucket(
        address _creator,
        string memory _name,
        BucketStorage.BucketVisibilityType _visibility,
        uint64 _chargedReadQuota,
        address _spAddress,
        uint256 _expireHeight,
        bytes calldata _sig,
        bytes memory _callbackData
    ) internal {
        BucketStorage.CreateBucketSynPackage memory createPkg = BucketStorage.CreateBucketSynPackage({
            creator: _creator,
            name: _name,
            visibility: _visibility,
            paymentAddress: paymentAddress,
            primarySpAddress: _spAddress,
            primarySpApprovalExpiredHeight: _expireHeight,
            primarySpSignature: _sig,
            chargedReadQuota: _chargedReadQuota,
            extraData: ""
        });

        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).createBucket{value: msg.value}(createPkg, callbackGasLimit, _extraData);
    }

    function _deleteBucket(uint256 _tokenId) internal {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).deleteBucket{value: msg.value}(_tokenId);
    }

    function _deleteBucket(uint256 _tokenId, bytes memory _callbackData) internal {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("BucketApp: ", ERROR_INSUFFICIENT_VALUE));
        IBucketHub(bucketHub).deleteBucket{value: msg.value}(_tokenId, callbackGasLimit, _extraData);
    }

    function _createBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    function _deleteBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
