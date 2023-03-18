// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC20 } from  "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

contract NPVToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable() {
    }

    function mint(address who, uint256 amount) external onlyOwner {
        _mint(who, amount);
    }

    function burn(address who, uint256 amount) external {
        require(who == msg.sender, "NPVT: can only burn own");
        require(balanceOf(who) >= amount, "NPVT: insufficient balance");
        _burn(who, amount);
    }
}
