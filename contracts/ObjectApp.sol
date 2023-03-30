// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/IObjectHub.sol";
import "./interface/ICrossChain.sol";

abstract contract ObjectApp is Ownable, Initializable {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    uint8 public constant OBJECT_CHANNEL_ID = 0x05;

    // status of cross-chain package
    uint32 public constant STATUS_SUCCESS = 0;
    uint32 public constant STATUS_FAILED = 1;
    uint32 public constant STATUS_UNEXPECTED = 2;

    // operation type
    uint8 public constant TYPE_DELETE = 3;

    mapping(address => bool) public operators;

    // system contract
    address public crossChain;
    address public objectHub;

    // callback config
    uint256 public callbackGasLimit;
    address public refundAddress;
    CmnStorage.FailureHandleStrategy public failureHandleStrategy;

    event DeleteObjectSuccess(uint256 indexed tokenId);
    event DeleteObjectFailed(uint32 status, uint256 indexed tokenId);

    modifier onlyOperator() {
        require(msg.sender == owner() || _isOperator(msg.sender), "ObjectApp: caller is not the owner or operator");
        _;
    }

    function initialize(
        address _crossChain,
        address _objectHub,
        uint256 _callbackGasLimit,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        crossChain = _crossChain;
        objectHub = _objectHub;

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
        require(msg.sender == crossChain, "ObjectApp: caller is not the crossChain contract");
        require(channelId == OBJECT_CHANNEL_ID, "ObjectApp: channelId is not supported");

        if (operationType == TYPE_DELETE) {
            _deleteObjectCallback(status, resourceId, callbackData);
        } else {
            revert("ObjectApp: operationType is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function deleteObject(bytes calldata objectName) external virtual {}

    function retryPackage() external virtual onlyOperator {
        IObjectHub(objectHub).retryPackage();
    }

    function skipPackage() external virtual onlyOperator {
        IObjectHub(objectHub).skipPackage();
    }

    /*----------------- settings -----------------*/
    function addOperator(address newOperator) public onlyOwner {
        operators[newOperator] = true;
    }

    function removeOperator(address operator) public onlyOwner {
        delete operators[operator];
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

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }

    function _deleteObjectCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
