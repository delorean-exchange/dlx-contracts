// SPDX-License-Identifier: BSL
pragma solidity ^0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IYieldSource} from "../interfaces/IYieldSource.sol";
import {IGMDVault, PoolInfo} from "../interfaces/gmd/IGMDVault.sol";
import {IWrappedETH} from "../interfaces/IWrappedETH.sol";

/// @notice Wrapper interface for managing yield from GMD.
contract GMDYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    event TransferOwnership(address indexed recipient);

    IERC20 public immutable override generatorToken;
    IERC20 public immutable override yieldToken;

    IERC20 public constant gmdToken =
        IERC20(0x1E95A37Be8A17328fbf4b25b9ce3cE81e271BeB3);
    IGMDVault public constant gmdVault =
        IGMDVault(0x8080B5cE6dfb49a6B86370d6982B3e2A86FBBb08);
    IERC20 public constant weth =
        IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    uint256 public totalDepositedETH = 0;

    /** @notice Owner role is the owner of this yield source, and
        is allowed to make deposits, withdrawals, and harvest the
        yield from the generator tokens. The owner can set a new
        owner.
    */
    address public owner;

    function totalStaked() internal view returns (uint256) {
        uint256 timepass = block.timestamp - gmdVault.poolInfo(1).lastUpdate;
        uint256 reward = gmdVault.poolInfo(1).EarnRateSec * timepass;
        return gmdVault.poolInfo(1).totalStaked + reward;
    }

    function eth2gmd(uint256 ethAmount) internal view returns (uint256) {
        return (ethAmount * generatorToken.totalSupply()) / totalStaked();
    }

    function gmd2eth(uint256 gmdAmount) internal view returns (uint256) {
        return (gmdAmount * totalStaked()) / generatorToken.totalSupply();
    }

    modifier validAddress(address who) {
        require(who != address(0), "SGYS: zero address");
        require(who != address(this), "SGYS: this address");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "SGYS: only owner");
        _;
    }

    /// @notice Create a GMDYieldSource.
    constructor() {
        generatorToken = gmdToken;
        yieldToken = weth;
        owner = msg.sender;
    }

    /// @notice Set a new owner.
    /// @param owner_ The new owner.
    function setOwner(
        address owner_
    ) external override onlyOwner validAddress(owner_) {
        owner = owner_;
        emit TransferOwnership(owner);
    }

    /// @notice Deposit GMD.
    /// @param amount Amount of GMD to deposit.
    /// @param claim If true, harvest yield.
    function deposit(uint256 amount, bool claim) external override onlyOwner {
        generatorToken.safeTransferFrom(msg.sender, address(this), amount);
        totalDepositedETH += gmd2eth(amount);
        if (claim) _harvest();
    }

    /// @notice Withdraw GMD.
    /// @param amount Amount of GMD to withdraw.
    /// @param claim If true, harvest yield.
    /// @param to Recipient of the withdrawal.
    function withdraw(
        uint256 amount,
        bool claim,
        address to
    ) external override onlyOwner {
        totalDepositedETH -= gmd2eth(amount);
        generatorToken.safeTransfer(to, amount);
        if (claim) _harvest();
    }

    function _amountPending() internal view returns (uint256) {
        return gmd2eth(_amountGenerator()) - totalDepositedETH;
    }

    function _harvest() internal {
        uint256 ethToHarvest = _amountPending();
        uint256 gmdToHarvest = eth2gmd(ethToHarvest);

        uint256 before = address(this).balance;
        gmdVault.leaveETH(gmdToHarvest, 1);
        uint256 amount = address(this).balance - before;

        IWrappedETH(address(weth)).deposit{value: amount}();
        yieldToken.safeTransfer(owner, amount);
    }

    /// @notice Harvest yield, and transfer it to the owner.
    function harvest() external override onlyOwner {
        _harvest();
    }

    /// @notice Amount of WETH yield pending that will be harvestable.
    /// @return Amount of WETH yield pending that will be harvestable.
    function amountPending() external view override returns (uint256) {
        return _amountPending();
    }

    function _amountGenerator() internal view returns (uint256) {
        return generatorToken.balanceOf(address(this));
    }

    /// @notice Amount of GMD locked.
    /// @return Amount of GMD locked.
    function amountGenerator() external view override returns (uint256) {
        return _amountGenerator();
    }

    // allow this contract to receive eth
    receive() external payable {}
}
