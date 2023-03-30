// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

contract PackageQueue {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    // app address => retry queue of package hash
    mapping(address => DoubleEndedQueueUpgradeable.Bytes32Deque) public retryQueue;
    // app retry package hash => retry package
    mapping(bytes32 => RetryPackage) public packageMap;

    // PlaceHolder reserve for future usage
    uint256[50] public PkgQueueSlots;

    /*
     * This enum provides different strategies for handling a failed ACK package.
     */
    enum FailureHandleStrategy {
        BlockOnFail, // If a package fails, the subsequent SYN packages will be blocked until the failed ACK packages are handled in the order they were received.
        CacheOnFail, // When a package fails, it is cached for later handling. New SYN packages will continue to be handled normally.
        SkipOnFail // Failed ACK packages are ignored and will not affect subsequent SYN packages.
    }

    struct RetryPackage {
        address appAddress;
        uint32 status;
        uint8 operationType;
        uint256 resourceId;
        bytes callbackData;
        bytes failReason;
    }

    event AppHandleAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
    event AppHandleFailAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
}

abstract contract Config {
    uint8 public constant TRANSFER_IN_CHANNEL_ID = 0x01;
    uint8 public constant TRANSFER_OUT_CHANNEL_ID = 0x02;
    uint8 public constant GOV_CHANNEL_ID = 0x03;
    uint8 public constant BUCKET_CHANNEL_ID = 0x04;
    uint8 public constant OBJECT_CHANNEL_ID = 0x05;
    uint8 public constant GROUP_CHANNEL_ID = 0x06;

    // contract address
    // will calculate their deployed addresses from deploy script
    address public constant PROXY_ADMIN = address(0);
    address public constant GOV_HUB = address(0);
    address public constant CROSS_CHAIN = address(0);
    address public constant TOKEN_HUB = address(0);
    address public constant LIGHT_CLIENT = address(0);
    address public constant RELAYER_HUB = address(0);
    address public constant BUCKET_HUB = address(0);
    address public constant OBJECT_HUB = address(0);
    address public constant GROUP_HUB = address(0);

    // PlaceHolder reserve for future usage
    uint256[50] public ConfigSlots;

    modifier onlyCrossChain() {
        require(msg.sender == CROSS_CHAIN, "only CrossChain contract");
        _;
    }

    modifier onlyGov() {
        require(msg.sender == GOV_HUB, "only GovHub contract");
        _;
    }

    // Please note this is a weak check, don't use this when you need a strong verification.
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function versionInfo()
        external
        pure
        virtual
        returns (uint256 version, string memory name, string memory description)
    {
        return (0, "Config", "");
    }
}

contract CmnStorage is Config, PackageQueue {
    /*----------------- constants -----------------*/
    // status of cross-chain package
    uint32 public constant STATUS_SUCCESS = 0;
    uint32 public constant STATUS_FAILED = 1;
    uint32 public constant STATUS_UNEXPECTED = 2;

    // operation type
    uint8 public constant TYPE_MIRROR = 1;
    uint8 public constant TYPE_CREATE = 2;
    uint8 public constant TYPE_DELETE = 3;

    // authorization code
    // can be used by bit operations
    uint32 public constant AUTH_CODE_CREATE = 1; // 0001
    uint32 public constant AUTH_CODE_DELETE = 2; // 0010

    // role
    bytes32 public constant ROLE_CREATE = keccak256("ROLE_CREATE");
    bytes32 public constant ROLE_DELETE = keccak256("ROLE_DELETE");

    /*----------------- storage -----------------*/
    uint8 public channelId;

    address public ERC721Token;
    address public additional;
    address public rlp;

    // PlaceHolder reserve for future use
    uint256[25] public CmnStorageSlots;

    /*----------------- structs -----------------*/
    // cross-chain package
    // GNFD to BSC
    struct CmnCreateAckPackage {
        uint32 status;
        uint256 id;
        address creator;
        bytes extraData; // rlp encode of ExtraData
    }

    // BSC to GNFD
    struct CmnDeleteSynPackage {
        address operator;
        uint256 id;
        bytes extraData; // rlp encode of ExtraData
    }

    // GNFD to BSC
    struct CmnDeleteAckPackage {
        uint32 status;
        uint256 id;
        bytes extraData; // rlp encode of ExtraData
    }

    // GNFD to BSC
    struct CmnMirrorSynPackage {
        uint256 id; // resource ID
        address owner;
    }

    // BSC to GNFD
    struct CmnMirrorAckPackage {
        uint32 status;
        uint256 id;
    }

    // extra data for callback
    struct ExtraData {
        address appAddress;
        address refundAddress;
        FailureHandleStrategy failureHandleStrategy;
        bytes callbackData;
    }

    /*----------------- events -----------------*/
    event MirrorSuccess(uint256 indexed id, address indexed owner);
    event MirrorFailed(uint256 indexed id, address indexed owner, bytes failReason);
    event CreateSubmitted(address indexed owner, address indexed operator, string name);
    event CreateSuccess(address indexed creator, uint256 indexed id);
    event CreateFailed(address indexed creator, uint256 indexed id);
    event DeleteSubmitted(address indexed owner, address indexed operator, uint256 indexed id);
    event DeleteSuccess(uint256 indexed id);
    event DeleteFailed(uint256 indexed id);
    event FailAckPkgReceived(uint8 indexed channelId, bytes msgBytes);
    event UnexpectedPackage(uint8 indexed channelId, bytes msgBytes);
    event ParamChange(string key, bytes value);
}
