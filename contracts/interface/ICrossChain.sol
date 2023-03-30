// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface ICrossChain {
    function getRelayFees() external returns (uint256 relayFee, uint256 minAckRelayFee);

    function callbackGasPrice() external returns (uint256);
}
