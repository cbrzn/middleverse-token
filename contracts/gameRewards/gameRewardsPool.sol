// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Game Reward Pool Contract
/// @author SoluLab
/// @notice You can use this contract for the game reward pool 

contract GameRewardPool is Ownable {
    using SafeERC20 for IERC20;

    /// @notice interface for the ERC20 token to be used
    IERC20 private _token;
    address public gameContract;

    /// @notice variables to allow the reward system to work
    uint256 public tokenForGameRewardPool;
    uint256 public gameLaunchTime;

    /// @notice setting of the pre defined time durations
    uint256 _totalTime = 92 weeks;
    uint256 _intervalTime = 4 weeks;
    uint256 public claimedAmount = 0;

    /// @notice token address is used to import tokens from a given contract
    /// @param _mdvToken that is supposed to be called into the contract
    /// @param _gameContract is used to determine the contract where the rewards will be sent 
    constructor(
        address _mdvToken,
        address _gameContract,
        uint256 _gameLaunchTime
    ) {
        require(_mdvToken != address(0x0));
        require(_gameContract != address(0x0));

        _token = IERC20(_mdvToken);
        gameContract = _gameContract;
        gameLaunchTime = _gameLaunchTime;

        tokenForGameRewardPool = (_token.totalSupply() * 45) / 100;
    }

    /// @notice used to withdraw the amount
    function withdraw() public onlyOwner {
        uint256 currentTime = _getCurrentTime();
        require(currentTime > gameLaunchTime, "Game is not Launch yet.");
        require(
            claimedAmount < tokenForGameRewardPool,
            "You have withdraw all amount."
        );
        uint256 amount = _calculateReward();
        require(
            amount > 0,
            "There is no amount for withdrawal in current phase."
        );
        claimedAmount += amount;
        _token.safeTransfer(gameContract, amount);
    }

    /// @notice Used to calulcate the reward that is to be sent
    function _calculateReward() internal view returns (uint256) {
        uint256 currentTime = _getCurrentTime();
        if (currentTime >= (gameLaunchTime + _totalTime)) {
            return (tokenForGameRewardPool - claimedAmount);
        }
        uint256 gameTime = currentTime - gameLaunchTime;
        uint256 perSlotAmount = (tokenForGameRewardPool * _intervalTime) /
            _totalTime;
        uint256 totalSlot = (gameTime + _intervalTime) / _intervalTime;
        uint256 claimableAmount = (totalSlot * perSlotAmount) - claimedAmount;
        return claimableAmount;
    }

    function _getCurrentTime() internal view returns (uint256) {
        return block.timestamp;
    }
}
