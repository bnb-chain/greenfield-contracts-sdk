// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./CmnStorage.sol";

contract BucketStorage is CmnStorage {
    struct CreateBucketSynPackage {
        address creator;
        string name;
        BucketVisibilityType visibility;
        address paymentAddress;
        address primarySpAddress;
        uint256 primarySpApprovalExpiredHeight;
        bytes primarySpSignature;
        uint64 chargedReadQuota;
        bytes extraData; // rlp encode of ExtraData
    }

    enum BucketVisibilityType {
        Unspecified,
        PublicRead,
        Private,
        Inherit // If the bucket Visibility is inherit, it's finally set to private.
    }
}
