// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol"
import "./interface/IBucketHub.sol";

abstract contract BucketApp is BaseApp {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    uint8 public constant BUCKET_CHANNEL_ID = 0x04;

    /*----------------- storage -----------------*/
    address public bucketHub;
    address public paymentAddress;

    DoubleEndedQueueUpgradeable.Bytes32Deque public createQueue;
    mapping(bytes32 => BucketStorage.CreateBucketSynPackage) public createQueueMap;

    event CreateBucketSuccess(bytes bucketName, uint256 indexed tokenId);
    event CreateBucketFailed(uint32 status, bytes bucketName);
    event DeleteBucketSuccess(uint256 indexed tokenId);
    event DeleteBucketFailed(uint32 status, uint256 indexed tokenId);

    // need initialize

    function greenfieldCall(
        uint32 status,
        uint8 channelId,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override virtual {
        require(msg.sender == crossChain, "BucketApp: caller is not the crossChain contract");
        require(channelId == BUCKET_CHANNEL_ID, "BucketApp: channelId is not supported");

        if (operationType == TYPE_CREATE) {
            _createBucketCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_DELETE) {
            _deleteBucketCallback(status, resourceId, callbackData);
        } else {
            revert("BucketApp: operationType is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function retryPackage() external override virtual onlyOperator {
        IBucketHub(bucketHub).retryPackage();
    }

    function skipPackage() external override virtual onlyOperator {
        IBucketHub(bucketHub).skipPackage();
    }

    /*----------------- settings -----------------*/
    function setPaymentAddress(address _paymentAddress) public onlyOperator {
        paymentAddress = _paymentAddress;
    }

    /*----------------- internal functions -----------------*/
    function _getCreateBucketPackage() internal view returns (BucketStorage.CreateBucketSynPackage memory) {
        bytes32 packageHash = createQueue.front();
        return createQueueMap[packageHash];
    }

    function _sendCreateBucketPacakge(
        address _spAddress,
        uint256 _expireHeight,
        bytes calldata _sig
    ) internal {
        BucketStorage.CreateBucketSynPackage memory createPkg = _getCreateBucketPackage();
        createPkg.primarySpAddress = _spAddress;
        createPkg.primarySpApprovalExpiredHeight = _expireHeight;
        createPkg.primarySpSignature = _sig;

        uint256 totalFee = _getTotalFee();
        IBucketHub(bucketHub).createBucket{value: totalFee}(createPkg);
    }

    function _sendCreateBucketPacakge(
        address _spAddress,
        uint256 _expireHeight,
        bytes calldata _sig,
        bytes memory _callbackData
    ) internal {
        BucketStorage.CreateBucketSynPackage memory createPkg = _getCreateBucketPackage();
        createPkg.primarySpAddress = _spAddress;
        createPkg.primarySpApprovalExpiredHeight = _expireHeight;
        createPkg.primarySpSignature = _sig;

        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        IBucketHub(bucketHub).createBucket{value: totalFee}(createPkg, callbackGasLimit, _extraData);
    }

    function _deleteBucket(uint256 _tokenId) internal {
        uint256 totalFee = _getTotalFee();
        IBucketHub(bucketHub).deleteBucket{value: totalFee}(_tokenId);
    }

    function _deleteBucket(uint256 _tokenId, bytes memory _callbackData) internal {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        IBucketHub(bucketHub).deleteBucket{value: totalFee}(_tokenId, callbackGasLimit, _extraData);
    }

    function _createBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    function _deleteBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
