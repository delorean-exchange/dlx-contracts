// SPDX-License-Identifier: BSL
pragma solidity ^0.8.13;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { IPirexRewards } from "../interfaces/pxgmx/IPirexRewards.sol";

/// @notice Wrapper interface for managing yield from PirexGMX.
contract PirexGMXYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    event TransferOwnership(address indexed recipient);

    IERC20 public immutable override generatorToken;
    IERC20 public immutable override yieldToken;

    IERC20 public constant pxGMXToken = IERC20(0x9A592B4539E22EeB8B2A3Df679d572C7712Ef999);
    IPirexRewards public constant pxRewards = IPirexRewards(0x612293B0b3aD2dCa6770E74478A30E0FCe266fDE);
    IERC20 public constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    /** @notice Owner role is the owner of this yield source, and
        is allowed to make deposits, withdrawals, and harvest the
        yield from the generator tokens. The owner can set a new
        owner.
    */
    address public owner;

    modifier validAddress(address who) {
        require(who != address(0), "PXYS: zero address");
        require(who != address(this), "PXYS: this address");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "PXYS: only owner");
        _;
    }

    /// @notice Create a PirexGMXYieldSource.
    constructor() {
        generatorToken = pxGMXToken;
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

    /// @notice Deposit pxGMX.
    /// @param amount Amount of pxGMX to deposit.
    /// @param claim If true, harvest yield.
    function deposit(uint256 amount, bool claim) external override onlyOwner {
        pxGMXToken.safeTransferFrom(msg.sender, address(this), amount);
        if (claim) _harvest();
    }

    /// @notice Withdraw pxGMX.
    /// @param amount Amount of pxGMX to withdraw.
    /// @param claim If true, harvest yield.
    /// @param to Recipient of the withdrawal.
    function withdraw(uint256 amount, bool claim, address to) external override onlyOwner {
        pxGMXToken.safeTransfer(to, amount);
        if (claim) _harvest();
    }

    function _amountPending() internal view returns (uint256) {
        return pxRewards.getUserRewardsAccrued(address(this), address(yieldToken));
    }

    function _harvest() internal {
        uint256 before = yieldToken.balanceOf(address(this));
        pxRewards.accrueAndClaim(address(this));
        uint256 amount = yieldToken.balanceOf(address(this)) - before;
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

    /// @notice Amount of pxGMX locked.
    /// @return Amount of pxGMX locked.
    function amountGenerator() external view override returns (uint256) {
        return generatorToken.balanceOf(address(this));
    }
}
