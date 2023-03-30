// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/IBucketHub.sol";
import "./interface/ICrossChain.sol";

abstract contract BucketApp is Ownable, Initializable {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    uint8 public constant BUCKET_CHANNEL_ID = 0x04;

    // status of cross-chain package
    uint32 public constant STATUS_SUCCESS = 0;
    uint32 public constant STATUS_FAILED = 1;
    uint32 public constant STATUS_UNEXPECTED = 2;

    // operation type
    uint8 public constant TYPE_CREATE = 2;
    uint8 public constant TYPE_DELETE = 3;

    mapping(address => bool) public operators;

    // system contract
    address public crossChain;
    address public bucketHub;

    // callback config
    uint256 public callbackGasLimit;
    address public refundAddress;
    CmnStorage.FailureHandleStrategy public failureHandleStrategy;

    address public paymentAddress;

    DoubleEndedQueueUpgradeable.Bytes32Deque public createQueue;
    mapping(bytes32 => BucketStorage.CreateBucketSynPackage) public createQueueMap;

    event CreateBucketSuccess(bytes bucketName, uint256 indexed tokenId);
    event CreateBucketFailed(uint32 status, bytes bucketName);
    event DeleteBucketSuccess(uint256 indexed tokenId);
    event DeleteBucketFailed(uint32 status, uint256 indexed tokenId);

    modifier onlyOperator() {
        require(msg.sender == owner() || _isOperator(msg.sender), "BucketApp: caller is not the owner or operator");
        _;
    }

    function initialize(
        address _crossChain,
        address _bucketHub,
        address _paymentAddress,
        uint256 _callbackGasLimit,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        crossChain = _crossChain;
        bucketHub = _bucketHub;
        paymentAddress = _paymentAddress;

        callbackGasLimit = _callbackGasLimit;
        refundAddress = _refundAddress;
        failureHandleStrategy = _failureHandleStrategy;
    }

    function greenfieldCall(
        uint32 status,
        uint8 channelId,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual {
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
    function retryPackage() external onlyOperator {
        IBucketHub(bucketHub).retryPackage();
    }

    function skipPackage() external onlyOperator {
        IBucketHub(bucketHub).skipPackage();
    }

    /*----------------- settings -----------------*/
    function addOperator(address newOperator) public onlyOwner {
        operators[newOperator] = true;
    }

    function removeOperator(address operator) public onlyOwner {
        delete operators[operator];
    }

    function setPaymentAddress(address _paymentAddress) public onlyOperator {
        paymentAddress = _paymentAddress;
    }

    function setCallbackConfig(
        uint256 _callbackGasLimit,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public onlyOperator {
        callbackGasLimit = _callbackGasLimit;
        refundAddress = _refundAddress;
        failureHandleStrategy = _failureHandleStrategy;
    }

    /*----------------- internal functions -----------------*/
    function _isOperator(address account) internal view returns (bool) {
        return operators[account];
    }

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

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }

    function _createBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    function _deleteBucketCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
