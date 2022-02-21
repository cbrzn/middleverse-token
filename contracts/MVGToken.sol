// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./extentions/ERC20Votes.sol";
import "./utils/Ownable.sol";

contract MiddleverseGold is ERC20, ERC20Votes, Ownable {
    constructor()
        ERC20("Middleverse Gold", "MVG")
        ERC20Permit("Middleverse Gold")
    {
        _mint(msg.sender, 500000000 * 10 ** decimals());

    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}