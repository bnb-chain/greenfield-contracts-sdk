// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/utils/Strings.sol";

import "./storage/CmnStorage.sol";
import "./interface/ICrossChain.sol";

abstract contract BaseApp is Initializable {
    /*----------------- constants -----------------*/
    // error code
    string public constant ERROR_INVALID_CALLER = "0";
    string public constant ERROR_INVALID_RESOURCE = "1";
    string public constant ERROR_INVALID_OPERATION = "2";
    string public constant ERROR_INSUFFICIENT_VALUE = "3";

    // status of cross-chain package
    uint32 public constant STATUS_SUCCESS = 0;
    uint32 public constant STATUS_FAILED = 1;
    uint32 public constant STATUS_UNEXPECTED = 2;

    // operation type
    uint8 public constant TYPE_CREATE = 2;
    uint8 public constant TYPE_DELETE = 3;

    /*----------------- storage -----------------*/
    // system contract
    address public crossChain;

    // callback config
    uint256 public callbackGasLimit;
    address public refundAddress;
    CmnStorage.FailureHandleStrategy public failureHandleStrategy;

    // need initialize

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external virtual {}

    function retryPackage(uint8 resourceType) external virtual {}

    function skipPackage(uint8 resourceType) external virtual {}

    /*----------------- internal functions -----------------*/
    function _setCallbackGasLimit(uint256 _callbackGasLimit) internal {
        callbackGasLimit = _callbackGasLimit;
    }

    function _setRefundAddress(address _refundAddress) internal {
        refundAddress = _refundAddress;
    }

    function _setFailureHandleStrategy(CmnStorage.FailureHandleStrategy _failureHandleStrategy) internal {
        failureHandleStrategy = _failureHandleStrategy;
    }

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }
}
