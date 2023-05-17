// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../BucketApp.sol";
import "../ObjectApp.sol";
import "../GroupApp.sol";
import "../interface/IERC1155.sol";
import "../interface/IERC721Nontransferable.sol";
import "../interface/IERC1155Nontransferable.sol";

/**
 * @dev An example of a simple ebook shop
 *
 * A `series` is a `bucket` resource and an `ebook` is an `object` resource
 * An ebook must be put into a series
 * A series can contain multiple ebooks
 * Anyone must create a series before creating an ebook
 *
 * And an ebook should be bonding to a group
 * Only members of the group can get the ebook
 *
 */
contract EbookShop is BucketApp, ObjectApp, GroupApp {
    /*----------------- constants -----------------*/
    // error code
    // 0-3: defined in `baseApp`
    string public constant ERROR_INVALID_NAME = "4";
    string public constant ERROR_RESOURCE_EXISTED = "5";
    string public constant ERROR_INVALID_PRICE = "6";
    string public constant ERROR_GROUP_NOT_EXISTED = "7";
    string public constant ERROR_EBOOK_NOT_ONSHELF = "8";
    string public constant ERROR_NOT_ENOUGH_VALUE = "9";
    string public constant ERROR_INVALID_TAX = "10";

    /*----------------- storage -----------------*/
    // admins
    address public owner;
    mapping(address => bool) public operators;

    // ERC1155 token for onshelf ebook
    address public ebookToken;

    // system contract
    address public bucketToken;
    address public objectToken;
    address public groupToken;
    address public memberToken;

    // tokenId => series name
    mapping(uint256 => string) public seriesName;
    // series name => tokenId
    mapping(string => uint256) public seriesId;

    // tokenId => Ebook name
    mapping(uint256 => string) public ebookName;
    // Ebook name => tokenId
    mapping(string => uint256) public ebookId;
    // Ebook id => group id
    mapping(uint256 => uint256) public ebookGroup;

    // tokenId => group name
    mapping(uint256 => string) public groupName;
    // group name => tokenId
    mapping(string => uint256) public groupId;
    // group id => Ebook id
    mapping(uint256 => uint256) public groupEbook;

    // ebookId => price
    mapping(uint256 => uint256) public ebookPrice;

    uint256 public tax;
    mapping(address => uint256) public income;

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
        address _crossChain,
        address _bucketHub,
        address _objectHub,
        address _groupHub,
        address _paymentAddress,
        uint256 _callbackGasLimit,
        address _refundAddress,
        uint8 _failureHandleStrategy,
        address _owner,
        address _ebookToken,
        uint256 _tax
    ) public initializer {
        require(_owner != address(0), string.concat("EbookShop: ", ERROR_INVALID_CALLER));
        _transferOwnership(_owner);

        tax = _tax;
        ebookToken = _ebookToken;
        bucketToken = IBucketHub(_bucketHub).ERC721Token();
        objectToken = IObjectHub(_objectHub).ERC721Token();
        groupToken = IGroupHub(_groupHub).ERC721Token();
        memberToken = IGroupHub(_groupHub).ERC1155Token();

        __base_app_init_unchained(_crossChain, _callbackGasLimit, _refundAddress, _failureHandleStrategy);
        __bucket_app_init_unchained(_bucketHub, _paymentAddress);
        __group_app_init_unchained(_groupHub);
        __object_app_init_unchained(_objectHub);
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

    /**
     * @dev Create a new series.
     *
     * Assuming the sp provider's info will be provided by the front-end.
     */
    function createSeries(
        string calldata name,
        BucketStorage.BucketVisibilityType visibility,
        uint64 chargedReadQuota,
        address spAddress,
        uint256 expireHeight,
        bytes calldata sig
    ) external payable {
        require(bytes(name).length > 0, string.concat("EbookShop: ", ERROR_INVALID_NAME));
        require(seriesId[name] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        bytes memory _callbackData = bytes(name); // use name as callback data
        _createBucket(msg.sender, name, visibility, chargedReadQuota, spAddress, expireHeight, sig, _callbackData);
    }

    /**
     * @dev Provide an ebook's ID to create a group for it.
     */
    function createGroup(uint256 _ebookId) public payable {
        require(
            IERC721NonTransferable(objectToken).ownerOf(_ebookId) == msg.sender,
            string.concat("EbookShop: ", ERROR_INVALID_CALLER)
        );

        string memory name = string.concat("Group for ", ebookName[_ebookId]);
        require(groupId[name] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        bytes memory _callbackData = bytes(name); // use name as callback data
        _createGroup(msg.sender, name, _callbackData);
    }

    /**
     * @dev Provide an ebook's ID to publish it.
     *
     * An ERC1155 token will be minted to the owner.
     * Other users can buy the ebook by calling `buyEbook` function with given price.
     */
    function publishEbook(uint256 _ebookId, uint256 price) external {
        require(
            IERC721NonTransferable(objectToken).ownerOf(_ebookId) == msg.sender,
            string.concat("EbookShop: ", ERROR_INVALID_CALLER)
        );
        require(ebookGroup[_ebookId] != 0, string.concat("EbookShop: ", ERROR_GROUP_NOT_EXISTED));
        require(price > 0, string.concat("EbookShop: ", ERROR_INVALID_PRICE));

        ebookPrice[_ebookId] = price;
        IERC1155(ebookToken).mint(msg.sender, _ebookId, 1, "");
    }

    /**
     * @dev Provide an ebook's ID to buy it.
     *
     * Buyer will be added to the group of the ebook.
     * An ERC1155 token will be minted to the buyer.
     */
    function buyEbook(uint256 _ebookId) external payable {
        require(ebookPrice[_ebookId] > 0, string.concat("EbookShop: ", ERROR_EBOOK_NOT_ONSHELF));

        uint256 price = ebookPrice[_ebookId];
        require(msg.value >= price, string.concat("EbookShop: ", ERROR_NOT_ENOUGH_VALUE));

        IERC1155(ebookToken).mint(msg.sender, _ebookId, 1, "");

        uint256 _groupId = ebookGroup[_ebookId];
        address _owner = IERC721NonTransferable(groupToken).ownerOf(_groupId);
        address[] memory _member = new address[](1);
        _member[0] = msg.sender;
        _updateGroup(_owner, _groupId, GroupStorage.UpdateGroupOpType.AddMembers, _member);

        uint256 _income = price * (100 - tax) / 100;
        income[_owner] += _income;
    }

    /**
     * @dev Provide an ebook's ID to downshelf it.
     *
     * The ebook will be removed from the shelf and cannot be bought.
     * Those who have already purchased are not affected.
     */
    function downshelfEbook(uint256 _ebookId) external {
        require(
            IERC721NonTransferable(objectToken).ownerOf(_ebookId) == msg.sender,
            string.concat("EbookShop: ", ERROR_INVALID_CALLER)
        );
        require(ebookPrice[_ebookId] > 0, string.concat("EbookShop: ", ERROR_EBOOK_NOT_ONSHELF));

        ebookPrice[_ebookId] = 0;
    }

    /**
     * @dev Register bucket resource that mirrored from GreenField to BSC.
     */
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

    /**
     * @dev Register object resource that mirrored from GreenField to BSC.
     */
    function registerEbook(
        string calldata _ebookName,
        uint256 _ebookId,
        string calldata _groupName,
        uint256 _groupId
    ) external {
        require(
            IERC721NonTransferable(objectToken).ownerOf(_ebookId) == msg.sender,
            string.concat("EbookShop: ", ERROR_INVALID_CALLER)
        );
        require(bytes(_ebookName).length > 0, string.concat("EbookShop: ", ERROR_INVALID_NAME));
        require(ebookId[_ebookName] == 0, string.concat("EbookShop: ", ERROR_RESOURCE_EXISTED));

        ebookName[_ebookId] = _ebookName;
        ebookId[_ebookName] = _ebookId;

        if (_groupId != 0) {
            require(
                IERC721NonTransferable(groupToken).ownerOf(_groupId) == msg.sender,
                string.concat("EbookShop: ", ERROR_INVALID_CALLER)
            );
            require(bytes(_groupName).length > 0, string.concat("EbookShop: ", ERROR_INVALID_NAME));

            groupName[_groupId] = _groupName;
            groupId[_groupName] = _groupId;

            groupEbook[_groupId] = _ebookId;
            ebookGroup[_ebookId] = _groupId;
        }
    }

    /**
     * @dev Register group resource that mirrored from GreenField to BSC.
     */
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

    function setTax(uint256 _tax) external onlyOwner {
        require(_tax < 100, string.concat("EbookShop: ", ERROR_INVALID_TAX));
        tax = _tax;
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
