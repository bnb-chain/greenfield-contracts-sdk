// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../BucketApp.sol";
import "../ObjectApp.sol";
import "../GroupApp.sol";

contract EbookShop is BucketApp, ObjectApp, GroupApp {
    /*----------------- storage -----------------*/
    // A series is a bucket which can include many ebooks
    // A ebook is an object

    // tokenId => series name
    mapping(uint256 => string) public seriesName;
    // series name => tokenId
    mapping(string => uint256) public seriesId;

    // tokenId => Ebook name
    mapping(uint256 => string) public eBookName;
    // Ebook name => tokenId
    mapping(string => uint256) public eBookId;

    // tokenId => group name
    mapping(uint256 => string) public groupName;
    // group name => tokenId
    mapping(string => uint256) public groupId;

    // PlaceHolder reserve for future use
    uint256[25] public EbookShopSlots;

    function initialize(
        address _crossChain,
        address _bucketHub,
        address _objectHub,
        address _groupHub,
        address _paymentAddress,
        address _refundAddress,
        uint256 _callbackGasLimit,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        crossChain = _crossChain;
        bucketHub = _bucketHub;
        objectHub = _objectHub;
        groupHub = _groupHub;

        paymentAddress = _paymentAddress;
        refundAddress = _refundAddress;
        callbackGasLimit = _callbackGasLimit;
        failureHandleStrategy = _failureHandleStrategy;
    }

    function greenfieldCall(
        uint32 status,
        uint8 channelId,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override(BucketApp,ObjectApp,GroupApp) {
        require(msg.sender == crossChain, "EbookShop: caller is not the crossChain contract");

        if (channelId == BucketApp.BUCKET_CHANNEL_ID) {
            _bucketGreenfieldCall(status, operationType, resourceId, callbackData);
        } else if (channelId == ObjectApp.OBJECT_CHANNEL_ID) {
            _objectGreenfieldCall(status, operationType, resourceId, callbackData);
        } else if (channelId == GroupApp.GROUP_CHANNEL_ID) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("EbookShop: channelId is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function retryPackage(uint8 channelId) external override(BucketApp,ObjectApp,GroupApp) onlyOperator {
        if (channelId == BUCKET_CHANNEL_ID) {
            IBucketHub(bucketHub).retryPackage();
        } else if (channelId == OBJECT_CHANNEL_ID) {
            IObjectHub(objectHub).retryPackage();
        } else if (channelId == GROUP_CHANNEL_ID) {
            IGroupHub(groupHub).retryPackage();
        } else {
            revert("EbookShop: channelId is not supported");
        }
    }

    function skipPackage(uint8 channelId) external override(BucketApp,ObjectApp,GroupApp) onlyOperator {
        if (channelId == BUCKET_CHANNEL_ID) {
            IBucketHub(bucketHub).skipPackage();
        } else if (channelId == OBJECT_CHANNEL_ID) {
            IObjectHub(objectHub).skipPackage();
        } else if (channelId == GROUP_CHANNEL_ID) {
            IGroupHub(groupHub).skipPackage();
        } else {
            revert("EbookShop: channelId is not supported");
        }
    }
}