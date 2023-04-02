// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../BucketApp.sol";
import "../ObjectApp.sol";
import "../GroupApp.sol";
import "../interface/IERC721Nontransferable.sol";
import "../interface/IERC1155Nontransferable.sol";

contract EbookShop is BucketApp, ObjectApp, GroupApp {
    /*----------------- constants -----------------*/
    string public constant ERROR_INVALID_NAME = "4";
    string public constant ERROR_RESOURCE_EXISTED = "5";

    /*----------------- storage -----------------*/
    address public owner;
    mapping(address => bool) public operators;

    // system contract
    address public bucketToken;
    address public objectToken;
    address public groupToken;
    address public memberToken;

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

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == owner || _isOperator(msg.sender), "caller is not the owner or operator");
        _;
    }

    function initialize(
        address _owner,
        address _crossChain,
        address _bucketHub,
        address _objectHub,
        address _groupHub,
        address _paymentAddress,
        address _refundAddress,
        uint256 _callbackGasLimit,
        CmnStorage.FailureHandleStrategy _failureHandleStrategy
    ) public initializer {
        require(_owner != address(0), string.concat("EbookShop: ", ERROR_INVALID_CALLER));
        _transferOwnership(_owner);

        crossChain = _crossChain;
        bucketHub = _bucketHub;
        objectHub = _objectHub;
        groupHub = _groupHub;

        bucketToken = IBucketHub(_bucketHub).ERC721Token();
        objectToken = IObjectHub(_objectHub).ERC721Token();
        groupToken = IGroupHub(_groupHub).ERC721Token();
        memberToken = IGroupHub(_groupHub).ERC1155Token();

        paymentAddress = _paymentAddress;
        refundAddress = _refundAddress;
        callbackGasLimit = _callbackGasLimit;
        failureHandleStrategy = _failureHandleStrategy;
    }

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resoureceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override(BucketApp, ObjectApp, GroupApp) {
        require(msg.sender == crossChain, string.concat("EbookShop: ", ERROR_INVALID_CALLER));

        if (resoureceType == RESOURCE_BUCKET) {
            _bucketGreenfieldCall(status, operationType, resourceId, callbackData);
        } else if (resoureceType == RESOURCE_OBJECT) {
            _objectGreenfieldCall(status, operationType, resourceId, callbackData);
        } else if (resoureceType == RESOURCE_GROUP) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert(string.concat("EbookShop: ", ERROR_INVALID_RESOURCE));
        }
    }

    // TODO assume sp provider's info will be provided by front-end
    function createSeries(string calldata name, BucketStorage.BucketVisibilityType visibility, uint64 chargedReadQuota, address spAddress,
        uint256 expireHeight, bytes calldata sig) external {
        require(seriesId[name] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        bytes memory _callbackData = bytes(name); // use name as callback data
        _createBucket(msg.sender, name, visibility, chargedReadQuota, spAddress, expireHeight, sig, _callbackData);
    }

    // register resource that mirrored from GreenField to BSC
    function registerSeries(string calldata name, uint256 tokenId) external {
        require(
            IERC721NonTransferable(bucketToken).ownerOf(tokenId) == msg.sender,
            string.concat("EbookShop: ", ERROR_INVALID_CALLER)
        );
        require(bytes(name).length > 0, string.concat("EbookShop: ", ERROR_INVALID_NAME));
        require(seriesId[name] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        seriesName[tokenId] = name;
        seriesId[name] = tokenId;
    }

    function registerEbook(string calldata name, uint256 tokenId) external {
        require(
            IERC721NonTransferable(objectToken).ownerOf(tokenId) == msg.sender,
            string.concat("EbookShop: ", ERROR_INVALID_CALLER)
        );
        require(bytes(name).length > 0, string.concat("EbookShop: ", ERROR_INVALID_NAME));
        require(eBookId[name] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        eBookName[tokenId] = name;
        eBookId[name] = tokenId;
    }

    function registerGroup(string calldata name, uint256 tokenId) external {
        require(
            IERC721NonTransferable(groupToken).ownerOf(tokenId) == msg.sender,
            string.concat("EbookShop: ", ERROR_INVALID_CALLER)
        );
        require(bytes(name).length > 0, string.concat("EbookShop: ", ERROR_INVALID_NAME));
        require(groupId[name] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        groupName[tokenId] = name;
        groupId[name] = tokenId;
    }

    /*----------------- admin functions -----------------*/
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), string.concat("EbookShop: ", ERROR_INVALID_CALLER));
        _transferOwnership(newOwner);
    }

    function addOperator(address newOperator) public onlyOwner {
        operators[newOperator] = true;
    }

    function removeOperator(address operator) public onlyOwner {
        delete operators[operator];
    }

    function retryPackage(uint8 resoureceType) external override onlyOperator {
        if (resoureceType == RESOURCE_BUCKET) {
            _retryBucketPackage();
        } else if (resoureceType == RESOURCE_OBJECT) {
            _retryObjectPackage();
        } else if (resoureceType == RESOURCE_GROUP) {
            _retryGroupPackage();
        } else {
            revert(string.concat("EbookShop: ", ERROR_INVALID_RESOURCE));
        }
    }

    function skipPackage(uint8 resoureceType) external override onlyOperator {
        if (resoureceType == RESOURCE_BUCKET) {
            _skipBucketPackage();
        } else if (resoureceType == RESOURCE_OBJECT) {
            _skipObjectPackage();
        } else if (resoureceType == RESOURCE_GROUP) {
            _skipGroupPackage();
        } else {
            revert(string.concat("EbookShop: ", ERROR_INVALID_RESOURCE));
        }
    }

    function createSeries(
        address _creator,
        string memory _name,
        BucketStorage.BucketVisibilityType _visibility,
        uint64 _chargedReadQuota,
        address _spAddress,
        uint256 _expireHeight,
        bytes calldata _sig
    ) external payable onlyOperator {
        require(bytes(_name).length > 0, string.concat("EbookShop: ", ERROR_INVALID_NAME));
        require(seriesId[_name] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        bytes memory _callbackData = bytes(_name); // we will use this to identify the resource in callback
        _createBucket(_creator, _name, _visibility, _chargedReadQuota, _spAddress, _expireHeight, _sig, _callbackData);
    }

    /*----------------- internal functions -----------------*/
    function _transferOwnership(address newOwner) internal {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function _isOperator(address account) internal view returns (bool) {
        return operators[account];
    }
}
