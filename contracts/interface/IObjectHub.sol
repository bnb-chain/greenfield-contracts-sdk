// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../storage/ObjectStorage.sol";

interface IObjectHub {
    function ERC721Token() external view returns (address);

    function deleteObject(uint256, uint256, CmnStorage.ExtraData memory) external payable returns (bool);

    function deleteObject(uint256) external payable returns (bool);

    function hasRole(bytes32 role, address granter, address account) external view returns (bool);

    function grant(address, uint32, uint256) external;

    function revoke(address, uint32) external;

    function retryPackage() external;

    function skipPackage() external;
}
