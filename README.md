## Overview

This document provides an overview of the Greenfield Contracts SDK, a library of smart contracts for the bnb-chain. The SDK enables developers to quickly and easily integrate contracts into their decentralized applications.

### Installation

```console
$ npm install @bnb-chain/greenfield-contracts-sdk
```

Alternatively, you can obtain the contracts directly from the GitHub repository (`bnb-chain/greenfield-contracts-sdk`). When doing so, ensure that you specify the appropriate release tag, such as `v1.0.0`, instead of using the `master` branch.


### Usage

After installing the library, import the desired contracts as follows:

```solidity
pragma solidity ^0.8.0;

import "@bnb-chain/contracts/BucketApp.sol";

contract MyDapp is BucketApp {
}
```

For security purposes, always use the installed code without modifications. Do not copy-paste code from online sources or modify it yourself. 

## Learn More

TODO

## Security

TODO

## Contribute

TODO

## License

Greenfield Contracts SDK is released under the [MIT License](LICENSE).
