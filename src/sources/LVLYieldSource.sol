// SPDX-License-Identifier: BSL
pragma solidity ^0.8.13;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { ILvlStaking, UserInfo } from "../interfaces/lvl/ILvlStaking.sol";
import { ILvlRouter } from "../interfaces/lvl/ILvlRouter.sol";
import { ILvlPool } from "../interfaces/lvl/ILvlPool.sol";

library LVLConstants {
    uint256 public constant NETWORK_BNB = 1;
    uint256 public constant NETWORK_ARBITRUM = 2;
    
    uint256 public constant TOKEN_LVL = 100;
    uint256 public constant TOKEN_LGO = 200;
}

/// @notice Wrapper interface for managing yield from LVL.
contract LVLYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    event TransferOwnership(address indexed recipient);

    IERC20 public override generatorToken;
    IERC20 public immutable override yieldToken;
    
    // for the user to pass in
    uint256 public immutable network;
    uint256 public immutable tokenType;

    // set based on network/tokentype
    IERC20 public weth;
    ILvlRouter public lvlRouter;
    ILvlPool public lvlPool;
    ILvlStaking public lvlStaking;
    IERC20 public seniorLlpToken;

    /** @notice Owner role is the owner of this yield source, and
        is allowed to make deposits, withdrawals, and harvest the
        yield from the generator tokens. The owner can set a new
        owner.
    */
    address public owner;

    /// @notice Create a LvlYieldSource.
    constructor(uint256 _network, uint256 _tokenType) {
        network = _network;
        tokenType = _tokenType;
        
        assert(network == LVLConstants.NETWORK_BNB || network == LVLConstants.NETWORK_ARBITRUM);
        assert(tokenType == LVLConstants.TOKEN_LGO || tokenType == LVLConstants.TOKEN_LVL);

        if (network == LVLConstants.NETWORK_BNB) {
            weth = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
            lvlRouter = ILvlRouter(0xBD8638C1fF477275E49aaAe3E4691b74AE76BeCd);
            lvlPool = ILvlPool(0xA5aBFB56a78D2BD4689b25B8A77fd49Bb0675874);
            seniorLlpToken = IERC20(0xB5C42F84Ab3f786bCA9761240546AA9cEC1f8821);

            if (tokenType == LVLConstants.TOKEN_LVL) {
                generatorToken = IERC20(0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149);
                lvlStaking = ILvlStaking(0x08A12FFedf49fa5f149C73B07E31f99249e40869);
            } else if (tokenType == LVLConstants.TOKEN_LGO) {
                generatorToken = IERC20(0xBe2B6C5E31F292009f495DDBda88e28391C9815E);
                lvlStaking = ILvlStaking(0xe5f3b669fd58AF914111759da054f3029734678C);
            }
        } else if (network == LVLConstants.NETWORK_ARBITRUM) {
            weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
            // TODO (after they launch)
        }
        
        yieldToken = weth;
        owner = msg.sender;
    }

    modifier validAddress(address who) {
        require(who != address(0), "LVLYS: zero address");
        require(who != address(this), "LVLYS: this address");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "LVLYS: only owner");
        _;
    }

    /// @notice Set a new owner.
    /// @param owner_ The new owner.
    function setOwner(address owner_) external override onlyOwner validAddress(owner_) {
        owner = owner_;
        emit TransferOwnership(owner);
    }

    /// @notice Deposit LVL.
    /// @param amount Amount of LVL to deposit.
    /// @param claim If true, harvest yield.
    function deposit(uint256 amount, bool claim) external override onlyOwner {
        generatorToken.safeTransferFrom(msg.sender, address(this), amount);

        generatorToken.safeApprove(address(lvlStaking), 0);
        generatorToken.safeApprove(address(lvlStaking), amount);
        lvlStaking.stake(address(this), amount);
        
        if (claim) _harvest();
    }

    /// @notice Withdraw LVL.
    /// @param amount Amount of LVL to withdraw.
    /// @param claim If true, harvest yield.
    /// @param to Recipient of the withdrawal.
    function withdraw(uint256 amount, bool claim, address to) external override onlyOwner {
        lvlStaking.unstake(address(this), amount);
        generatorToken.safeTransfer(to, amount);
        if (claim) _harvest();
    }

    function _amountPending() internal view returns (uint256) {
        uint256 llpAmount = lvlStaking.pendingRewards(address(this));
        (,uint256 outAmountAfterFee,) = lvlPool.calcRemoveLiquidity(address(seniorLlpToken), address(weth), llpAmount);
        return outAmountAfterFee;
    }

    function _harvest() internal {
        // claim our llp
        uint256 oldAmount = seniorLlpToken.balanceOf(address(this));
        lvlStaking.claimRewards(address(this));
        uint256 llpAmount = seniorLlpToken.balanceOf(address(this)) - oldAmount;
        
        // sell our llp for weth
        uint256 oldWeth = weth.balanceOf(address(this));
        seniorLlpToken.safeApprove(address(lvlRouter), 0);
        seniorLlpToken.safeApprove(address(lvlRouter), llpAmount);
        lvlRouter.removeLiquidity(address(seniorLlpToken), address(weth), llpAmount, 0, address(this));

        // send weth to owner
        uint256 delta = weth.balanceOf(address(this)) - oldWeth;
        yieldToken.safeTransfer(owner, delta);
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

    /// @notice Amount of LVL locked.
    /// @return Amount of LVL locked.
    function amountGenerator() external view override returns (uint256) {
        return lvlStaking.userInfo(address(this)).amount;
    }
}