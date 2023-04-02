// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./CmnStorage.sol";

contract GroupStorage is CmnStorage {
    struct UpdateGroupSynPackage {
        address operator;
        uint256 id; // group id
        uint8 opType; // add/remove members
        address[] members;
        bytes extraData; // rlp encode of ExtraData
    }
}
