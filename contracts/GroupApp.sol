// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/IGroupHub.sol";
import "./interface/ICrossChain.sol";
import "./interface/IERC721NonTransferable.sol";
import "./interface/IERC1155NonTransferable.sol";

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

    // authorization code
    // can be used by bit operations
    uint32 public constant AUTH_CODE_CREATE = 1; // 0001
    uint32 public constant AUTH_CODE_DELETE = 2; // 0010
    uint32 public constant AUTH_CODE_UPDATE = 4; // 0100

    // role
    bytes32 public constant ROLE_CREATE = keccak256("ROLE_CREATE");
    bytes32 public constant ROLE_DELETE = keccak256("ROLE_DELETE");
    bytes32 public constant ROLE_UPDATE = keccak256("ROLE_UPDATE");

    mapping(address => bool) public operators;

    // system contract
    address public crossChain;
    address public tokenHub;
    address public groupHub;
    address public groupToken;
    address public memberToken;

    address public paymentAddress;

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
    event DeleteGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event DeleteGroupFailed(uint32 status, uint256 indexed tokenId);
    event UpdateGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event UpdateGroupFailed(uint32 status, bytes groupName, uint256 indexed tokenId);

    modifier onlyOperator() {
        require(msg.sender == owner() || _isOperator(msg.sender), "GroupApp: caller is not the owner or operator");
        _;
    }

    function initialize(
        address _crossChain,
        address _tokenHub,
        address _groupHub,
        address _paymentAddress,
        uint256 _callbackGasLimit,
        address _refundAddress,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        crossChain = _crossChain;
        tokenHub = _tokenHub;
        groupHub = _groupHub;
        groupToken = IGroupHub(groupHub).ERC721Token();
        memberToken = IGroupHub(groupHub).ERC1155Token();
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
        require(msg.sender == crossChain, "GroupApp: caller is not the crossChain contract");
        require(channelId == GROUP_CHANNEL_ID, "GroupApp: channelId is not supported");

        if (operationType == TYPE_CREATE) {
            _createGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_DELETE) {
            _deleteGroupCallback(status, resourceId);
        } else {
            revert("GroupApp: operationType is not supported");
        }
    }

    /*----------------- external functions -----------------*/
    function createGroup(
        bytes calldata groupName
    ) external {
        require(tokenIdMap[groupName] == 0, "GroupApp: group already exists");

        CmnStorage.ExtraData memory extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: groupName
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).createGroup{value: totalFee}(msg.sender, string(groupName), callbackGasLimit, extraData);
    }

    function deleteGroup(bytes calldata groupName) external {
        uint256 tokenId = tokenIdMap[groupName];
        require(tokenId != 0, "GroupApp: group not exists");
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            "GroupApp: caller is not the owner of the group"
        );

        _deleteGroup(tokenId, groupName);
    }

    function deleteGroup(uint256 tokenId) external {
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            "GroupApp: caller is not the owner of the group"
        );
        bytes memory groupName = groupNameMap[tokenId];

        _deleteGroup(tokenId, groupName);
    }

    function addMembers(bytes calldata groupName, address[] calldata members) external {
        uint256 tokenId = tokenIdMap[groupName];
        require(tokenId != 0, "GroupApp: group not exists");
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            "GroupApp: caller is not the owner of the group"
        );

        _updateGroup(msg.sender, groupName, tokenId, UPDATE_ADD, members);
    }

    function addMembers(uint256 tokenId, address[] calldata members) external {
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            "GroupApp: caller is not the owner of the group"
        );
        bytes memory groupName = groupNameMap[tokenId];

        _updateGroup(msg.sender, groupName, tokenId, UPDATE_ADD, members);
    }

    function deleteMembers(bytes calldata groupName, address[] calldata members) external {
        uint256 tokenId = tokenIdMap[groupName];
        require(tokenId != 0, "GroupApp: group not exists");
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            "GroupApp: caller is not the owner of the group"
        );

        _updateGroup(msg.sender, groupName, tokenId, UPDATE_DELETE, members);
    }

    function deleteMembers(uint256 tokenId, address[] calldata members) external {
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            "GroupApp: caller is not the owner of the group"
        );
        bytes memory groupName = groupNameMap[tokenId];

        _updateGroup(msg.sender, groupName, tokenId, UPDATE_DELETE, members);
    }

    function registerGroup(bytes calldata groupName, uint256 tokenId) external {
        require(tokenIdMap[groupName] == 0, "GroupApp: group already exists");
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            "GroupApp: caller is not the owner of the group"
        );

        tokenIdMap[groupName] = tokenId;
        groupNameMap[tokenId] = groupName;
    }

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

    function _deleteGroup(uint256 tokenId, bytes memory groupName) internal {
        CmnStorage.ExtraData memory extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: groupName
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).deleteGroup{value: totalFee}(tokenId, callbackGasLimit, extraData);
    }

    function _updateGroup(address owner, bytes memory groupName, uint256 tokenId, uint8 opType, address[] memory newMembers) internal {
        GroupStorage.UpdateGroupSynPackage memory pkg = GroupStorage.UpdateGroupSynPackage({
            operator: owner,
            id: tokenId,
            opType: opType,
            members: newMembers,
            extraData: ""
        });

        CmnStorage.ExtraData memory extraData = CmnStorage.ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: groupName
        });

        uint256 totalFee = _getTotalFee();
        IGroupHub(groupHub).updateGroup{value: totalFee}(pkg, callbackGasLimit, extraData);
    }

    function _createGroupCallback(uint32 status, uint256 tokenId, bytes memory callbackData) internal {
        if (status == STATUS_SUCCESS) {
            tokenIdMap[callbackData] = tokenId;
            groupNameMap[tokenId] = callbackData;
            emit CreateGroupSuccess(callbackData, tokenId);
        } else {
            emit CreateGroupFailed(status, callbackData);
        }
    }

    function _deleteGroupCallback(uint32 status, uint256 tokenId) internal {
        if (status == STATUS_SUCCESS) {
            bytes memory groupName = groupNameMap[tokenId];
            delete tokenIdMap[groupName];
            delete groupNameMap[tokenId];
            emit DeleteGroupSuccess(groupName, tokenId);
        } else {
            emit DeleteGroupFailed(status, tokenId);
        }
    }

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }
}
