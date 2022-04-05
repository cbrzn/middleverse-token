// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MiddleverseGold is ERC20, Ownable {
    constructor()
        ERC20("Middleverse Gold", "MVG")
    {
        _mint(msg.sender, 500000000 * 10 ** decimals());

    }

    
}