// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseApp.sol";
import "./interface/IGroupHub.sol";

abstract contract GroupApp is BaseApp {
    /*----------------- constants -----------------*/
    // Group's resource code
    uint8 public constant RESOURCE_GROUP = 0x06;

    // operation code
    // This operation is only used for group.
    uint8 public constant TYPE_UPDATE = 4;

    // update type
    // add or remove members
    uint8 public constant UPDATE_ADD = 0;
    uint8 public constant UPDATE_REMOVE = 1;

    /*----------------- storage -----------------*/
    // system contract
    address public groupHub;

    event CreateGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event CreateGroupFailed(uint32 status, bytes groupName);
    event DeleteGroupSuccess(uint256 indexed tokenId);
    event DeleteGroupFailed(uint32 status, uint256 indexed tokenId);
    event UpdateGroupSuccess(uint256 indexed tokenId);
    event UpdateGroupFailed(uint32 status, uint256 indexed tokenId);

    /*----------------- initializer -----------------*/
    /**
     * @dev Sets the values for {crossChain}, {callbackGasLimit}, {refundAddress}, {failureHandleStrategy} and {groupHub}.
     */
    function __group_app_init(
        address _crossChain,
        uint256 _callbackGasLimit,
        address _refundAddress,
        uint8 _failureHandlerStrategy,
        address _groupHub
    ) internal onlyInitializing {
        __base_app_init_unchained(_crossChain, _callbackGasLimit, _refundAddress, _failureHandlerStrategy);
        __group_app_init_unchained(_groupHub);
    }

    function __group_app_init_unchained(address _groupHub) internal onlyInitializing {
        groupHub = _groupHub;
    }

    /*----------------- external functions -----------------*/
    /**
     * @dev see {BaseApp-greenfieldCall}
     */
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual override {
        require(msg.sender == crossChain, string.concat("GroupApp: ", ERROR_INVALID_CALLER));
        require(resourceType == RESOURCE_GROUP, string.concat("GroupApp: ", ERROR_INVALID_RESOURCE));

        _groupGreenfieldCall(status, operationType, resourceId, callbackData);
    }

    /*----------------- internal functions -----------------*/
    /**
     * @dev Callback router for group resource.
     * It will call the corresponding callback function according to the operation type.
     */
    function _groupGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal virtual {
        if (operationType == TYPE_CREATE) {
            _createGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_DELETE) {
            _deleteGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_UPDATE) {
            _updateGroupCallback(status, resourceId, callbackData);
        } else {
            revert(string.concat("GroupApp: ", ERROR_INVALID_OPERATION));
        }
    }

    /**
     * @dev Retry the first failed package of this app address in the GroupHub's queue.
     */
    function _retryGroupPackage() internal virtual {
        IGroupHub(groupHub).retryPackage();
    }

    /**
     * @dev Skip the first failed package of this app address in the GroupHub's queue.
     */
    function _skipGroupPackage() internal virtual {
        IGroupHub(groupHub).skipPackage();
    }

    /**
     * @dev Send the `createGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _createGroup(address _owner, string memory _groupName) internal {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).createGroup{value: msg.value}(_owner, _groupName);
    }

    /**
     * @dev Send the `createGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _createGroup(address _owner, string memory _groupName, bytes memory _callbackData) internal {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).createGroup{value: msg.value}(_owner, _groupName, callbackGasLimit, _extraData);
    }

    /**
     * @dev Send the `deleteGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _deleteGroup(uint256 _tokenId) internal virtual {
        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).deleteGroup{value: msg.value}(_tokenId);
    }

    /**
     * @dev Send the `deleteGroup` transaction to GroupHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
    function _deleteGroup(uint256 _tokenId, bytes memory _callbackData) internal virtual {
        CmnStorage.ExtraData memory _extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: _callbackData
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).deleteGroup{value: msg.value}(_tokenId, callbackGasLimit, _extraData);
    }

    /**
     * @dev Assemble a `GroupStorage.UpdateGroupSynPackage` from provided elements
     * and send the transaction to GroupHub.
     *
     * This function is used for the case that the caller does not need to receive the callback.
     */
    function _updateGroup(address _owner, uint256 _tokenId, uint8 _opType, address[] memory _members) internal {
        GroupStorage.UpdateGroupSynPackage memory updatePkg = GroupStorage.UpdateGroupSynPackage({
            operator: _owner,
            id: _tokenId,
            opType: _opType,
            members: _members,
            extraData: ""
        });

        uint256 totalFee = _getTotalFee();
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).updateGroup{value: msg.value}(updatePkg);
    }

    /**
     * @dev Assemble a `GroupStorage.UpdateGroupSynPackage` from provided elements
     * and send the transaction to GroupHub.
     *
     * This function is used for the case that the caller needs to receive the callback.
     */
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
        require(msg.value >= totalFee, string.concat("GroupApp: ", ERROR_INSUFFICIENT_VALUE));
        IGroupHub(groupHub).updateGroup{value: msg.value}(updatePkg, callbackGasLimit, _extraData);
    }

    /**
     * @dev Handler for `createGroup`'s callback.
     */
    function _createGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    /**
     * @dev Handler for `deleteGroup`'s callback.
     */
    function _deleteGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}

    /**
     * @dev Handler for `updateGroup`'s callback.
     */
    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal virtual {}
}
