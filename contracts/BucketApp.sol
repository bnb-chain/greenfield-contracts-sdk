// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/IBucketHub.sol";
import "./interface/ICrossChain.sol";
import "./interface/IERC721NonTransferable.sol";

contract BucketApp is Ownable, Initializable {
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

    // authorization code
    // can be used by bit operations
    uint32 public constant AUTH_CODE_CREATE = 1; // 0001
    uint32 public constant AUTH_CODE_DELETE = 2; // 0010

    // role
    bytes32 public constant ROLE_CREATE = keccak256("ROLE_CREATE");
    bytes32 public constant ROLE_DELETE = keccak256("ROLE_DELETE");

    mapping(address => bool) public operators;

    // system contract
    address public crossChain;
    address public tokenHub;
    address public bucketHub;
    address public bucketToken;

    address public paymentAddress;

    // callback config
    uint256 public callbackGasLimit;
    address public refundAddress;
    CmnStorage.FailureHandleStrategy public failureHandleStrategy;

    DoubleEndedQueueUpgradeable.Bytes32Deque public createQueue;
    mapping(bytes32 => BucketStorage.CreateBucketSynPackage) public createQueueMap;

    // bucket name => token id
    mapping(bytes => uint256) public tokenIdMap;
    // token id => bucket name
    mapping(uint256 => bytes) public bucketNameMap;

    event CreateBucketSuccess(bytes bucketName, uint256 indexed tokenId);
    event CreateBucketFailed(uint32 status, bytes bucketName);
    event DeleteBucketSuccess(bytes bucketName, uint256 indexed tokenId);
    event DeleteBucketFailed(uint32 status, uint256 indexed tokenId);

    modifier onlyOperator() {
        require(msg.sender == owner() || _isOperator(msg.sender), "BucketApp: caller is not the owner or operator");
        _;
    }

    function initialize(
        address _crossChain,
        address _tokenHub,
        address _bucketHub,
        address _paymentAddress,
        uint256 _callbackGasLimit,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        crossChain = _crossChain;
        tokenHub = _tokenHub;
        bucketHub = _bucketHub;
        bucketToken = IBucketHub(bucketHub).ERC721Token();
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
            _deleteBucketCallback(status, resourceId);
        } else {
            revert("BucketApp: operationType is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function createBucket(
        bytes calldata bucketName,
        BucketStorage.BucketVisibilityType visibility,
        uint64 chargedReadQuota
    ) external {
        require(tokenIdMap[bucketName] == 0, "BucketApp: bucket already exists");

        bytes32 packageHash = keccak256(abi.encodePacked(msg.sender, bucketName));
        require(createQueueMap[packageHash].creator == address(0), "BucketApp: package already in queue");

        createQueue.pushBack(packageHash);
        createQueueMap[packageHash] = BucketStorage.CreateBucketSynPackage({
            creator: msg.sender,
            name: string(bucketName),
            visibility: visibility,
            paymentAddress: paymentAddress,
            primarySpAddress: address(0),
            primarySpApprovalExpiredHeight: 0,
            primarySpSignature: "",
            chargedReadQuota: chargedReadQuota,
            extraData: ""
        });
    }

    function deleteBucket(bytes calldata bucketName) external {
        uint256 tokenId = tokenIdMap[bucketName];
        require(tokenId != 0, "BucketApp: bucket not exists");
        require(
            IERC721NonTransferable(bucketToken).ownerOf(tokenId) == msg.sender,
            "BucketApp: caller is not the owner of the bucket"
        );

        _deleteBucket(tokenId, bucketName);
    }

    function deleteBucket(uint256 tokenId) external {
        require(
            IERC721NonTransferable(bucketToken).ownerOf(tokenId) == msg.sender,
            "BucketApp: caller is not the owner of the bucket"
        );
        bytes memory bucketName = bucketNameMap[tokenId];

        _deleteBucket(tokenId, bucketName);
    }

    function registerBucket(bytes calldata bucketName, uint256 tokenId) external {
        require(tokenIdMap[bucketName] == 0, "BucketApp: bucket already exists");
        require(
            IERC721NonTransferable(bucketToken).ownerOf(tokenId) == msg.sender,
            "BucketApp: caller is not the owner of the bucket"
        );

        tokenIdMap[bucketName] = tokenId;
        bucketNameMap[tokenId] = bucketName;
    }

    function getCreateBucketPackage() public view returns (BucketStorage.CreateBucketSynPackage memory) {
        bytes32 packageHash = createQueue.front();
        return createQueueMap[packageHash];
    }

    function sendCreateBucketPacakge(address _spAddress, uint256 _expireHeight, bytes calldata _sig) external payable onlyOperator {
        BucketStorage.CreateBucketSynPackage memory package = getCreateBucketPackage();
        package.primarySpAddress = _spAddress;
        package.primarySpApprovalExpiredHeight = _expireHeight;
        package.primarySpSignature = _sig;

        CmnStorage.ExtraData memory extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: bytes(package.name)
        });

        uint256 totalFee = _getTotalFee();
        IBucketHub(bucketHub).createBucket{value: totalFee}(package, callbackGasLimit, extraData);
    }

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

    function _deleteBucket(uint256 tokenId, bytes memory bucketName) internal {
        CmnStorage.ExtraData memory extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: bucketName
        });

        uint256 totalFee = _getTotalFee();
        IBucketHub(bucketHub).deleteBucket{value: totalFee}(tokenId, callbackGasLimit, extraData);
    }

    function _createBucketCallback(uint32 status, uint256 tokenId, bytes memory callbackData) internal {
        if (status == STATUS_SUCCESS) {
            tokenIdMap[callbackData] = tokenId;
            bucketNameMap[tokenId] = callbackData;
            emit CreateBucketSuccess(callbackData, tokenId);
        } else {
            emit CreateBucketFailed(status, callbackData);
        }
    }

    function _deleteBucketCallback(uint32 status, uint256 tokenId) internal {
        if (status == STATUS_SUCCESS) {
            bytes memory bucketName = bucketNameMap[tokenId];
            delete tokenIdMap[bucketName];
            delete bucketNameMap[tokenId];
            emit DeleteBucketSuccess(bucketName, tokenId);
        } else {
            emit DeleteBucketFailed(status, tokenId);
        }
    }

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }
}
