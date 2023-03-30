// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol";
import "./interface/IGroupHub.sol";

abstract contract GroupApp is BaseApp {
    /*----------------- constants -----------------*/
    uint8 public constant GROUP_CHANNEL_ID = 0x06;

    // operation type
    uint8 public constant TYPE_UPDATE = 4;

    // update type
    uint8 public constant UPDATE_ADD = 1;
    uint8 public constant UPDATE_DELETE = 2;

    /*----------------- storage -----------------*/
    // system contract
    address public groupHub;

    event CreateGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event CreateGroupFailed(uint32 status, bytes groupName);
    event DeleteGroupSuccess(uint256 indexed tokenId);
    event DeleteGroupFailed(uint32 status, uint256 indexed tokenId);
    event UpdateGroupSuccess(uint256 indexed tokenId);
    event UpdateGroupFailed(uint32 status, uint256 indexed tokenId);

    // need initialize

    function greenfieldCall(
        uint32 status,
        uint8 channelId,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override virtual {
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
    function retryPackage() external override virtual onlyOperator {
        IGroupHub(groupHub).retryPackage();
    }

    function skipPackage() external override virtual onlyOperator {
        IGroupHub(groupHub).skipPackage();
    }

    /*----------------- internal functions -----------------*/
    function _createGroup(
        address _owner,
        string memory _groupName
    ) internal {
        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).createGroup{value: totalFee}(_owner, _groupName);
    }

    function _createGroup(
        address _owner,
        string memory _groupName,
        bytes memory _callbackData
    ) internal {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).createGroup{value: totalFee}(_owner, _groupName, callbackGasLimit, _extraData);
    }

    function _deleteGroup(uint256 _tokenId) internal virtual {
        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).deleteGroup{value: totalFee}(_tokenId);
    }

    function _deleteGroup(uint256 _tokenId, bytes memory _callbackData) internal virtual {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).deleteGroup{value: totalFee}(_tokenId, callbackGasLimit, _extraData);
    }

    function _updateGroup(
        address _owner,
        uint256 _tokenId,
        uint8 _opType,
        address[] memory _members
    ) internal {
        GroupStorage.UpdateGroupSynPackage memory updatePkg = GroupStorage.UpdateGroupSynPackage({
            operator: _owner,
            id: _tokenId,
            opType: _opType,
            members: _members,
            extraData: ""
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).updateGroup{value: totalFee}(updatePkg);
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

    function _createGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    function _deleteGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
