// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

contract CmnStorage {
    struct ExtraData {
        address appAddress;
        address refundAddress;
        FailureHandleStrategy failureHandleStrategy;
        bytes callbackData;
    }

    enum FailureHandleStrategy {
        BlockOnFail, // If a package fails, the subsequent SYN packages will be blocked until the failed ACK packages are handled in the order they were received.
        CacheOnFail, // When a package fails, it is cached for later handling. New SYN packages will continue to be handled normally.
        SkipOnFail // Failed ACK packages are ignored and will not affect subsequent SYN packages.
    }
}
