
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import "../MVGTokenVesting.sol";

/**
 * @title MVGSetTime
 * WARNING: use only for testing and debugging purpose
 */
contract MVGSetTime is MVGTokenVesting {
    uint256 _mockTime = 0;

    constructor(address token_) MVGTokenVesting(token_) {}

    function setCurrentTime(uint256 _time) external {
        _mockTime = _time;
    }

    function getCurrentTime() public view virtual override returns (uint256) {
        return _mockTime;
    }
}
