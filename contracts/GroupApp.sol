// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/IGroupHub.sol";
import "./interface/ICrossChain.sol";

contract GroupApp is Ownable, Initializable {
    /*----------------- constants -----------------*/
    uint8 public constant GROUP_CHANNEL_ID = 0x06;

    // status of cross-chain package
    uint32 public constant STATUS_SUCCESS = 0;
    uint32 public constant STATUS_FAILED = 1;
    uint32 public constant STATUS_UNEXPECTED = 2;

    // operation type
    uint8 public constant TYPE_CREATE = 2;
    uint8 public constant TYPE_DELETE = 3;
    uint8 public constant TYPE_UPDATE = 4;

    // update type
    uint8 public constant UPDATE_ADD = 1;
    uint8 public constant UPDATE_DELETE = 2;

    mapping(address => bool) public operators;

    // system contract
    address public crossChain;
    address public groupHub;

    // callback config
    uint256 public callbackGasLimit;
    address public refundAddress;
    CmnStorage.FailureHandleStrategy public failureHandleStrategy;

    // group name => token id
    mapping(bytes => uint256) public tokenIdMap;
    // token id => group name
    mapping(uint256 => bytes) public groupNameMap;

    event CreateGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event CreateGroupFailed(uint32 status, bytes groupName);
    event DeleteGroupSuccess(uint256 indexed tokenId);
    event DeleteGroupFailed(uint32 status, uint256 indexed tokenId);
    event UpdateGroupSuccess(uint256 indexed tokenId);
    event UpdateGroupFailed(uint32 status, uint256 indexed tokenId);

    modifier onlyOperator() {
        require(msg.sender == owner() || _isOperator(msg.sender), "GroupApp: caller is not the owner or operator");
        _;
    }

    function initialize(
        address _crossChain,
        address _groupHub,
        uint256 _callbackGasLimit,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        crossChain = _crossChain;
        groupHub = _groupHub;

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
        require(msg.sender == crossChain, "GroupApp: caller is not the crossChain contract");
        require(channelId == GROUP_CHANNEL_ID, "GroupApp: channelId is not supported");

        if (operationType == TYPE_CREATE) {
            _createGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_DELETE) {
            _deleteGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_UPDATE) {
            _updateGroupCallback(status, resourceId, callbackData);
        } else {
            revert("GroupApp: operationType is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function createGroup(bytes calldata _groupName) external virtual {}

    function deleteGroup(uint256 _tokenId) external virtual {}

    function addMembers(uint256 _tokenId, address[] calldata _members) external virtual {}

    function deleteMembers(uint256 _tokenId, address[] calldata _members) external virtual {}

    function retryPackage() external onlyOperator {
        IGroupHub(groupHub).retryPackage();
    }

    function skipPackage() external onlyOperator {
        IGroupHub(groupHub).skipPackage();
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

    function _deleteGroup(uint256 _tokenId, bytes memory _callbackData) internal virtual {
        CmnStorage.ExtraData memory extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).deleteGroup{value: totalFee}(_tokenId, callbackGasLimit, extraData);
    }

    function _updateGroup(
        address _owner,
        uint256 _tokenId,
        uint8 _opType,
        address[] memory _members,
        bytes memory _callbackData
    ) internal {
        GroupStorage.UpdateGroupSynPackage memory updatePkg = GroupStorage.UpdateGroupSynPackage({
            operator: _owner,
            id: _tokenId,
            opType: _opType,
            members: _members,
            extraData: ""
        });

        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).updateGroup{value: totalFee}(updatePkg, callbackGasLimit, _extraData);
    }

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }

    function _createGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    function _deleteGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
