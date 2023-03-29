// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/IObjectHub.sol";
import "./interface/ICrossChain.sol";
import "./interface/IERC721NonTransferable.sol";

contract ObjectApp is Ownable, Initializable {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    uint8 public constant OBJECT_CHANNEL_ID = 0x05;

    // status of cross-chain package
    uint32 public constant STATUS_SUCCESS = 0;
    uint32 public constant STATUS_FAILED = 1;
    uint32 public constant STATUS_UNEXPECTED = 2;

    // operation type
    uint8 public constant TYPE_DELETE = 3;

    // authorization code
    // can be used by bit operations
    uint32 public constant AUTH_CODE_DELETE = 2; // 0010

    // role
    bytes32 public constant ROLE_DELETE = keccak256("ROLE_DELETE");

    mapping(address => bool) public operators;

    // system contract
    address public crossChain;
    address public tokenHub;
    address public objectHub;
    address public objectToken;

    address public paymentAddress;

    // callback config
    uint256 public callbackGasLimit;
    address public refundAddress;
    CmnStorage.FailureHandleStrategy public failureHandleStrategy;

    // object name => token id
    mapping(bytes => uint256) public tokenIdMap;
    // token id => object name
    mapping(uint256 => bytes) public objectNameMap;

    event CreateObjectSuccess(bytes objectName, uint256 indexed tokenId);
    event CreateObjectFailed(uint32 status, bytes objectName);
    event DeleteObjectSuccess(bytes objectName, uint256 indexed tokenId);
    event DeleteObjectFailed(uint32 status, uint256 indexed tokenId);

    modifier onlyOperator() {
        require(msg.sender == owner() || _isOperator(msg.sender), "ObjectApp: caller is not the owner or operator");
        _;
    }

    function initialize(
        address _crossChain,
        address _tokenHub,
        address _objectHub,
        address _paymentAddress,
        uint256 _callbackGasLimit,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        crossChain = _crossChain;
        tokenHub = _tokenHub;
        objectHub = _objectHub;
        objectToken = IObjectHub(objectHub).ERC721Token();
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
        bytes calldata
    ) external virtual {
        require(msg.sender == crossChain, "ObjectApp: caller is not the crossChain contract");
        require(channelId == OBJECT_CHANNEL_ID, "ObjectApp: channelId is not supported");

        if (operationType == TYPE_DELETE) {
            _deleteObjectCallback(status, resourceId);
        } else {
            revert("ObjectApp: operationType is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function deleteObject(bytes calldata objectName) external {
        uint256 tokenId = tokenIdMap[objectName];
        require(tokenId != 0, "ObjectApp: object not exists");
        require(
            IERC721NonTransferable(objectToken).ownerOf(tokenId) == msg.sender,
            "ObjectApp: caller is not the owner of the object"
        );

        _deleteObject(tokenId, objectName);
    }

    function deleteObject(uint256 tokenId) external {
        require(
            IERC721NonTransferable(objectToken).ownerOf(tokenId) == msg.sender,
            "ObjectApp: caller is not the owner of the object"
        );
        bytes memory objectName = objectNameMap[tokenId];

        _deleteObject(tokenId, objectName);
    }

    function registerObject(bytes calldata objectName, uint256 tokenId) external {
        require(tokenIdMap[objectName] == 0, "ObjectApp: object already exists");
        require(
            IERC721NonTransferable(objectToken).ownerOf(tokenId) == msg.sender,
            "ObjectApp: caller is not the owner of the object"
        );

        tokenIdMap[objectName] = tokenId;
        objectNameMap[tokenId] = objectName;
    }

    function retryPackage() external onlyOperator {
        IObjectHub(objectHub).retryPackage();
    }

    function skipPackage() external onlyOperator {
        IObjectHub(objectHub).skipPackage();
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

    function _deleteObject(uint256 tokenId, bytes memory objectName) internal {
        CmnStorage.ExtraData memory extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: objectName
        });

        uint256 totalFee = _getTotalFee();
        IObjectHub(objectHub).deleteObject{value: totalFee}(tokenId, callbackGasLimit, extraData);
    }

    function _deleteObjectCallback(uint32 status, uint256 tokenId) internal {
        if (status == STATUS_SUCCESS) {
            bytes memory objectName = objectNameMap[tokenId];
            delete tokenIdMap[objectName];
            delete objectNameMap[tokenId];
            emit DeleteObjectSuccess(objectName, tokenId);
        } else {
            emit DeleteObjectFailed(status, tokenId);
        }
    }

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }
}
