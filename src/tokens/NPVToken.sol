// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NPVToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    }

    // TODO: access control
    function mint(address who, uint256 amount) external {
        _mint(who, amount);
    }

    function burn(address who, uint256 amount) external {
        require(who ==  msg.sender, "NPVT: only self burn");
        require(balanceOf(who) >= amount, "NPVT: insufficient balance");
        _burn(who, amount);
    }
}
