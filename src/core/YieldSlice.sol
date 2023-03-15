// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/IYieldSlice.sol";
import "../interfaces/IYieldSource.sol";
import "../interfaces/IDiscounter.sol";
import "../data/YieldData.sol";
import "../tokens/NPVToken.sol";

contract YieldSlice is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event NewDebtSlice(address indexed owner, uint256 indexed id, uint256 tokens, uint256 yield, uint256 npv);
    event NewCreditSlice(address indexed owner, uint256 indexed id, uint256 npv);
    event UnlockDebtSlice(address indexed owner, uint256 indexed id);

    uint256 public constant GENERATION_PERIOD = 7 * 7200;  // 7 days at rate of 12 seconds per block

    uint256 public nextId = 1;
    uint256 public totalShares;
    uint256 public harvestedYield;
    uint256 public immutable dustLimit;

    NPVToken public npvToken;
    IERC20 public immutable generatorToken;
    IERC20 public immutable yieldToken;

    IYieldSource public immutable yieldSource;
    IDiscounter public immutable discounter;
    YieldData public immutable debtData;
    YieldData public immutable creditData;

    struct DebtSlice {
        address owner;
        uint256 createdBlockNumber;
        uint256 unlockedBlockNumber;
        uint256 timestamp;
        uint256 shares;
        uint256 tokens;  // TODO: redundant with shares?
        uint256 npv;
    }
    mapping(uint256 => DebtSlice) public debtSlices;

    struct CreditSlice {
        address owner;
        uint256 blockNumber;
        uint256 timestamp;
        uint256 npv;
        uint256 claimed;
    }
    mapping(uint256 => CreditSlice) public creditSlices;

    constructor(address npvToken_,
                address yieldSource_,
                address debtData_,
                address creditData_,
                address discounter_,
                uint256 dustLimit_) {
        npvToken = NPVToken(npvToken_);
        yieldSource = IYieldSource(yieldSource_);
        generatorToken = IYieldSource(yieldSource_).generatorToken();
        yieldToken = IYieldSource(yieldSource_).yieldToken();
        discounter = IDiscounter(discounter_);
        dustLimit = dustLimit_;
        debtData = YieldData(debtData_);
        creditData = YieldData(creditData_);
    }

    function _min(uint256 x1, uint256 x2) private pure returns (uint256) {
        return x1 < x2 ? x1 : x2;
    }

    function _max(uint256 x1, uint256 x2) private pure returns (uint256) {
        return x1 > x2 ? x1 : x2;
    }

    function totalTokens() public view returns (uint256) {
        return yieldSource.amountGenerator();
    }

    function cumulativeYield() public view returns (uint256) {
        return harvestedYield + yieldSource.amountPending();
    }

    function harvest() external nonReentrant {
        _harvest();
    }

    function _harvest() private {
        uint256 pending = yieldSource.amountPending();
        if (pending == 0) return;
        yieldSource.harvest();
        harvestedYield += pending;
    }

    function recordData() public nonReentrant {
        _recordData();
    }

    function _recordData() private {
        debtData.record(totalTokens(), cumulativeYield());
        creditData.record(npvToken.totalSupply(), cumulativeYield());
    }

    function tokens(uint256 id) public view returns (uint256) {
        if (totalShares == 0) return 0;
        return totalTokens() * debtSlices[id].shares / totalShares;
    }

    function debtSlice(address owner,
                       address recipient,
                       uint256 tokens_,
                       uint256 yield) external returns (uint256) {

        uint256 newTotalShares;
        uint256 delta;
        uint256 oldTotalTokens = totalTokens();
        if (totalShares == 0 || oldTotalTokens == 0) {
            newTotalShares = tokens_;
            delta = tokens_;
        } else {
            newTotalShares = (oldTotalTokens + tokens_) * totalShares / oldTotalTokens;
            delta = newTotalShares - totalShares;
        }

        generatorToken.safeTransferFrom(msg.sender, address(this), tokens_);
        generatorToken.safeApprove(address(yieldSource), 0);
        generatorToken.safeApprove(address(yieldSource), tokens_);

        yieldSource.deposit(tokens_, false);

        uint256 npv = discounter.discounted(tokens_, yield);

        uint256 id = nextId++;
        DebtSlice memory slice = DebtSlice({
            owner: owner,
            createdBlockNumber: block.number,
            unlockedBlockNumber: 0,
            timestamp: block.timestamp,
            shares: delta,
            tokens: tokens_,
            npv: npv });
        debtSlices[id] = slice;

        totalShares = newTotalShares;
        npvToken.mint(recipient, npv);
        _recordData();

        emit NewDebtSlice(owner, id, tokens_, yield, npv);
        
        return id;
    }

    function unlockDebtSlice(uint256 id) external {
        DebtSlice storage slice = debtSlices[id];
        require(slice.unlockedBlockNumber == 0, "YS: already unlocked");

        (, uint256 npv, uint256 refund) = generated(id);
        uint256 remaining = npv > slice.npv ? 0 : slice.npv - npv;
        if (remaining > 0) {
            IERC20(npvToken).safeTransferFrom(msg.sender, address(this), remaining);
            npvToken.burn(address(this), remaining);
        }
        if (refund > 0) {
            // TODO: if we implement transfer ownership, make sure refund is separate
            _harvest();
            uint256 balance = IERC20(yieldToken).balanceOf(address(this));
            IERC20(yieldToken).safeTransfer(slice.owner, _min(balance, refund));
        }
        uint256 amount = tokens(id);
        yieldSource.withdraw(amount, false, slice.owner);
        slice.unlockedBlockNumber = block.number;

        emit UnlockDebtSlice(slice.owner, id);
    }

    function creditSlice(uint256 npv, address who) external returns (uint256) {
        IERC20(npvToken).safeTransferFrom(msg.sender, address(this), npv);

        uint256 id = nextId++;
        CreditSlice memory slice = CreditSlice({
            owner: who,
            blockNumber: block.number,
            timestamp: block.timestamp,
            npv: npv,
            claimed: 0 });
        creditSlices[id] = slice;

        emit NewCreditSlice(who, id, npv);

        return id;
    }

    function claimCreditSlice(uint256 id) external returns (uint256) {
        CreditSlice storage slice = creditSlices[id];
        (, , uint256 claimable) = generatedCredit(id);

        if (claimable == 0) return 0;
        if (claimable == slice.claimed) return 0;
        assert(slice.claimed <= claimable);

        uint256 delta = claimable - slice.claimed;
        _harvest();
        yieldToken.safeTransfer(slice.owner, delta);
        slice.claimed = claimable;

        // TODO: record data?

        return delta;
    }
        
    function generated(uint256 id) public view returns (uint256, uint256, uint256) {
        DebtSlice storage slice = debtSlices[id];
        uint256 nominal = 0;
        uint256 npv = 0;
        uint256 refund = 0;
        uint256 last = slice.unlockedBlockNumber == 0 ? block.number : slice.unlockedBlockNumber;

        for (uint256 i = slice.createdBlockNumber; i < last; i += GENERATION_PERIOD) {
            uint256 end = _min(last - 1, i + GENERATION_PERIOD);
            uint256 ytb = debtData.yieldPerTokenPerBlock(i,
                                                         end,
                                                         totalTokens(),
                                                         cumulativeYield());

            uint256 yield = (ytb * (end - i) * slice.tokens) / debtData.PRECISION_FACTOR();
            uint256 estimatedDays = (12 * (end - slice.createdBlockNumber)) / (24 * 3600);
            uint256 pv = discounter.pv(estimatedDays, yield);

            if (npv == slice.npv) {
                refund += yield;
            } else if (npv + pv > slice.npv) {
                uint256 owed = discounter.nominal(estimatedDays, slice.npv - npv);
                uint256 leftover = yield - owed;
                nominal += owed;
                refund += leftover;
                npv = slice.npv;
            } else {
                npv += pv;
                nominal += yield;
            }
        }

        return (nominal, npv, refund);
    }
        
    function generatedCredit(uint256 id) public view returns (uint256, uint256, uint256) {
        CreditSlice storage slice = creditSlices[id];
        uint256 nominal = 0;
        uint256 npv = 0;
        uint256 claimable = 0;

        for (uint256 i = slice.blockNumber; npv < slice.npv && i < block.number; i += GENERATION_PERIOD) {
            uint256 end = _min(block.number - 1, i + GENERATION_PERIOD);
            uint256 ytb = creditData.yieldPerTokenPerBlock(i,
                                                           end,
                                                           npvToken.totalSupply(),
                                                           cumulativeYield());

            uint256 yield = (ytb * (end - i) * slice.npv) / creditData.PRECISION_FACTOR();
            uint256 estimatedDays = (12 * (end - slice.blockNumber)) / (24 * 3600);
            uint256 pv = discounter.pv(estimatedDays, yield);

            if (npv + pv > slice.npv) {
                pv = slice.npv - npv;
                yield = discounter.nominal(estimatedDays, pv);
            }

            claimable += yield;
            nominal += yield;
            npv += pv;
        }

        return (nominal, npv, claimable);
    }
}
