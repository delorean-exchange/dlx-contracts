// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { IYieldSlice } from "../interfaces/IYieldSlice.sol";
import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { IDiscounter } from "../interfaces/IDiscounter.sol";
import { YieldData } from "../data/YieldData.sol";
import { NPVToken } from "../tokens/NPVToken.sol";

contract YieldSlice is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event NewDebtSlice(address indexed owner,
                       uint256 indexed id,
                       uint256 tokens,
                       uint256 yield,
                       uint256 npv,
                       uint256 fees);

    event NewCreditSlice(address indexed owner,
                         uint256 indexed id,
                         uint256 npv,
                         uint256 fees);

    event UnlockDebtSlice(address indexed owner,
                          uint256 indexed id);

    event PayDebt(uint256 indexed id,
                  uint256 amount);

    event ReceiveNPV(address indexed recipient,
                     uint256 indexed id,
                     uint256 amount);

    event Claimed(uint256 indexed id,
                  uint256 amount);

    uint256 public constant FEE_DENOM = 100_0;

    // Max fees limit what can be set by governance. Actual fee may be lower.

    // -- Debt fees -- //
    // Debt fees are a percent of the difference between nominal yield
    // sold, and the net present value. This results in low borrowing
    // cost for short term debt.
    uint256 public constant MAX_DEBT_FEE = 50_0;

    // -- Credit fees -- //
    // Credit fees are are simple percent of the NPV tokens being purchased.
    uint256 public constant MAX_CREDIT_FEE = 20_0;

    address public gov;
    address public treasury;

    // The unallocated credit slice tracks yield that has been sold using a
    // debt slice, but hasn't been purchased using a credit slice. When a
    // credit slice purchase takes place, the receiver of that purhcase gets
    // a proportional share of the claimable yield from this slice.
    uint256 public constant unallocId = 1;

    uint256 public nextId = unallocId + 1;
    uint256 public totalShares;
    uint256 public harvestedYield;
    uint256 public dustLimit;
    uint256 public cumulativePaidYield;

    // Track separately from NPV token total supply, because burns
    // happen on credit slice claims, even though debt slice unlocks
    // are what result in yield generation changes.
    uint256 public activeNPV;

    uint256 public debtFee;
    uint256 public creditFee;

    NPVToken public npvToken;
    IERC20 public immutable generatorToken;
    IERC20 public immutable yieldToken;

    IYieldSource public immutable yieldSource;
    IDiscounter public immutable discounter;
    YieldData public immutable debtData;
    YieldData public immutable creditData;

    struct DebtSlice {
        address owner;
        uint128 blockTimestamp;
        uint128 unlockedBlockTimestamp;
        uint256 shares;  // Share of the vault's locked generators
        uint256 tokens;  // Tokens locked for generation
        uint256 npvDebt;
        bytes memo;
    }
    mapping(uint256 => DebtSlice) public debtSlices;

    struct CreditSlice {
        address owner;

        // The slice is entitled to `npvCredit` amount of yield, discounted
        // relative to `blockTimestamp`.
        uint128 blockTimestamp;
        uint256 npvCredit;

        // This slice's share of yield, as a fraction of total NPV tokens.
        uint256 npvTokens;

        // `pending` is accumulated but unclaimed yield for this slice,
        // in nominal terms.
        uint256 pending;

        // `claimed` is the amount of yield claimed by this slice, in
        // nominal terms
        uint256 claimed;

        bytes memo;
    }
    mapping(uint256 => CreditSlice) public creditSlices;
    mapping(uint256 => uint256) public pendingClaimable;

    modifier onlyGov() {
        require(msg.sender == gov, "YS: gov only");
        _;
    }

    modifier isSlice(uint256 id) {
        require(id < nextId, "YS: invalid id");
        _;
    }

    modifier isDebtSlice(uint256 id) {
        require(debtSlices[id].owner != address(0), "YS: no such debt slice");
        _;
    }

    modifier isCreditSlice(uint256 id) {
        require(creditSlices[id].owner != address(0), "YS: no such credit slice");
        _;
    }

    modifier debtSliceOwner(uint256 id) {
        require(debtSlices[id].owner == msg.sender, "YS: only owner");
        _;
    }

    modifier creditSliceOwner(uint256 id) {
        require(creditSlices[id].owner == msg.sender, "YS: only owner");
        _;
    }

    modifier noDust(uint256 amount) {
        require(amount > dustLimit, "YS: dust");
        _;
    }

    constructor(string memory symbol,
                address yieldSource_,
                address debtData_,
                address creditData_,
                address discounter_,
                uint256 dustLimit_) {
        gov = msg.sender;
        treasury = msg.sender;

        npvToken = new NPVToken(symbol, symbol);
        yieldSource = IYieldSource(yieldSource_);
        generatorToken = IYieldSource(yieldSource_).generatorToken();
        yieldToken = IYieldSource(yieldSource_).yieldToken();
        discounter = IDiscounter(discounter_);
        dustLimit = dustLimit_;
        debtData = YieldData(debtData_);
        creditData = YieldData(creditData_);

        creditSlices[unallocId] = CreditSlice({
            owner: address(this),
            blockTimestamp: uint128(block.timestamp),
            npvCredit: 0,
            npvTokens: 0,
            pending: 0,
            claimed: 0,
            memo: new bytes(0) });
    }

    function _min(uint256 x1, uint256 x2) private pure returns (uint256) {
        return x1 < x2 ? x1 : x2;
    }

    function setGov(address gov_) external onlyGov {
        gov = gov_;
    }

    function setTreasury(address treasury_) external onlyGov {
        treasury = treasury_;
    }

    function setDustLimit(uint256 dustLimit_) external onlyGov {
        dustLimit = dustLimit_;
    }

    function setDebtFee(uint256 debtFee_) external onlyGov {
        require(debtFee_ <= MAX_DEBT_FEE, "YS: max debt fee");
        debtFee = debtFee_;
    }

    function setCreditFee(uint256 creditFee_) external onlyGov {
        require(creditFee_ <= MAX_CREDIT_FEE, "YS: max credit fee");
        creditFee = creditFee_;
    }

    function totalTokens() public view returns (uint256) {
        return yieldSource.amountGenerator();
    }

    function cumulativeYield() public view returns (uint256) {
        return harvestedYield + yieldSource.amountPending();
    }

    function cumulativeYieldCredit() public view returns (uint256) {
        return harvestedYield + cumulativePaidYield + yieldSource.amountPending();
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
        creditData.record(activeNPV, cumulativeYieldCredit());
    }

    function tokens(uint256 id) public view isDebtSlice(id) returns (uint256) {
        if (totalShares == 0) return 0;
        return totalTokens() * debtSlices[id].shares / totalShares;
    }

    function _previewDebtSlice(uint256 tokens_, uint256 yield) internal view returns (uint256, uint256) {
        uint256 npv = discounter.discounted(tokens_, yield);
        uint256 fees = ((yield - npv) * debtFee) / FEE_DENOM;
        return (npv, fees);
    }

    function previewDebtSlice(uint256 tokens_, uint256 yield) public view returns (uint256, uint256) {
        return _previewDebtSlice(tokens_, yield);
    }

    function _modifyDebtPosition(uint256 id, uint256 deltaGenerator, uint256 deltaYield)
        internal
        isDebtSlice(id)
        returns (uint256, uint256) {

        DebtSlice storage slice = debtSlices[id];

        // Update generator shares and deposit the tokens
        uint256 newTotalShares;
        uint256 deltaShares;
        uint256 oldTotalTokens = totalTokens();
        if (totalShares == 0 || oldTotalTokens == 0) {
            newTotalShares = deltaGenerator;
            deltaShares = deltaGenerator;
        } else {
            newTotalShares = (oldTotalTokens + deltaGenerator) * totalShares / oldTotalTokens;
            deltaShares = newTotalShares - totalShares;
        }

        generatorToken.safeTransferFrom(msg.sender, address(this), deltaGenerator);
        generatorToken.safeApprove(address(yieldSource), 0);
        generatorToken.safeApprove(address(yieldSource), deltaGenerator);
        yieldSource.deposit(deltaGenerator, false);

        // Update NPV debt for the slice
        assert(slice.npvDebt == 0);
        (uint256 npv, uint256 fees) = _previewDebtSlice(deltaGenerator, deltaYield);
        slice.npvDebt = npv;
        slice.blockTimestamp = uint128(block.timestamp);
        slice.shares += deltaShares;
        slice.tokens += deltaGenerator;

        totalShares = newTotalShares;

        return (npv, fees);
    }

    function debtSlice(address owner,
                       address recipient,
                       uint256 amountGenerator,
                       uint256 amountYield,
                       bytes calldata memo)
        external
        nonReentrant
        noDust(amountGenerator)
        returns (uint256) {

        uint256 id = nextId++;
        debtSlices[id] = DebtSlice({
            owner: owner,
            blockTimestamp: 0,
            unlockedBlockTimestamp: 0,
            shares: 0,
            tokens: 0,
            npvDebt: 0,
            memo: memo });

        (uint256 npv, uint256 fees) = _modifyDebtPosition(id, amountGenerator, amountYield);

        npvToken.mint(recipient, npv - fees);
        npvToken.mint(treasury, fees);
        activeNPV += npv;

        _modifyCreditPosition(unallocId, int256(npv - fees));

        _recordData();

        emit NewDebtSlice(owner, id, amountGenerator, amountYield, npv, fees);
        
        return id;
    }

    function payDebt(uint256 id, uint256 amount) external nonReentrant isDebtSlice(id) returns (uint256) {
        DebtSlice storage slice = debtSlices[id];
        require(slice.unlockedBlockTimestamp == 0, "YS: already unlocked");

        ( , uint256 npvGen, ) = generatedDebt(id);
        uint256 left = npvGen > slice.npvDebt ? 0 : slice.npvDebt - npvGen;
        uint256 actual = _min(left, amount);
        IERC20(npvToken).safeTransferFrom(msg.sender, address(this), actual);
        slice.npvDebt -= actual;
        npvToken.burn(address(this), actual);
        activeNPV -= actual;

        emit PayDebt(id, actual);

        return actual;
    }

    function transferOwnership(uint256 id, address who) external nonReentrant isSlice(id) {
        if (debtSlices[id].owner != address(0)) {
            DebtSlice storage slice = debtSlices[id];
            require(slice.owner == msg.sender, "YS: only debt slice owner");
            slice.owner = who;
        } else {
            assert(creditSlices[id].owner != address(0));
            CreditSlice storage slice = creditSlices[id];
            require(slice.owner == msg.sender, "YS: only credit slice owner");
            _claim(id, 0);
            slice.owner = who;
        }
    }

    function unlockDebtSlice(uint256 id) external nonReentrant debtSliceOwner(id) {
        DebtSlice storage slice = debtSlices[id];
        require(slice.unlockedBlockTimestamp == 0, "YS: already unlocked");

        (uint256 nominalGen, uint256 npvGen, uint256 refund) = generatedDebt(id);

        require(npvGen >= slice.npvDebt, "YS: npv debt");

        if (refund > 0) {
            _harvest();
            uint256 balance = IERC20(yieldToken).balanceOf(address(this));
            IERC20(yieldToken).safeTransfer(slice.owner, _min(balance, refund));
        }
        uint256 amount = tokens(id);
        yieldSource.withdraw(amount, false, slice.owner);
        slice.unlockedBlockTimestamp = uint128(block.timestamp);
        activeNPV -= slice.npvDebt;

        emit UnlockDebtSlice(slice.owner, id);
    }

    function _creditFees(uint256 npv) internal view returns (uint256) {
        return (npv * creditFee) / FEE_DENOM;
    }

    function creditFees(uint256 npv) external view returns (uint256) {
        return _creditFees(npv);
    }

    function _modifyCreditPosition(uint256 id, int256 deltaNPV) internal isCreditSlice(id) {
        if (deltaNPV == 0) return;
        CreditSlice storage slice = creditSlices[id];
        require(deltaNPV > 0 || uint256(-deltaNPV) <= slice.npvTokens, "YS: invalid negative delta");

        // The new NPV credited will be the existing NPV's value shifted
        // forward to the current timestamp, subtracting the already generated
        // NPV to this point.
        ( , uint256 npvGen, uint256 claimable) = generatedCredit(id);
        uint256 numDays = ((block.timestamp - uint256(slice.blockTimestamp))
                           / discounter.DISCOUNT_PERIOD());
        uint256 shiftedNPV = discounter.shiftNPV(slice.npvCredit - npvGen, numDays);

        // Checkpoint what we can claim as pending, and set claimed to zero
        // as it is now relative to the new timestamp.
        slice.blockTimestamp = uint128(block.timestamp);
        slice.pending = claimable;
        slice.claimed = 0;

        if (deltaNPV > 0) {
            slice.npvCredit = shiftedNPV + uint256(deltaNPV);
            slice.npvTokens += uint256(deltaNPV);
        } else {
            slice.npvCredit = shiftedNPV - uint256(-deltaNPV);
            slice.npvTokens -= uint256(-deltaNPV);
        }
    }

    function creditSlice(uint256 npv, address who, bytes calldata memo) external returns (uint256) {
        uint256 fees = _creditFees(npv);
        IERC20(npvToken).safeTransferFrom(msg.sender, address(this), npv);
        IERC20(npvToken).safeTransfer(treasury, fees);

        // Checkpoint the unallocated NPV slice, and transfer proportional
        // amount of pending yield to the new position.
        _modifyCreditPosition(unallocId, -int256(npv - fees));
        CreditSlice storage unalloc = creditSlices[unallocId];
        uint256 pendingShare = unalloc.pending * (npv - fees) / (unalloc.npvTokens + npv - fees);
        unalloc.pending -= pendingShare;

        uint256 id = nextId++;
        CreditSlice memory slice = CreditSlice({
            owner: who,
            blockTimestamp: uint128(block.timestamp),
            npvCredit: npv - fees,
            npvTokens: npv - fees,
            pending: pendingShare,
            claimed: 0,
            memo: memo });
        creditSlices[id] = slice;

        emit NewCreditSlice(who, id, npv, fees);

        return id;
    }

    function _claim(uint256 id, uint256 limit) internal returns (uint256) {
        CreditSlice storage slice = creditSlices[id];
        ( , uint256 npvGen, uint256 claimable) = generatedCredit(id);

        if (claimable == 0) return 0;

        _harvest();
        uint256 amount = _min(claimable, yieldToken.balanceOf(address(this)));
        if (limit > 0) {
            amount = _min(limit, amount);
        }
        yieldToken.safeTransfer(slice.owner, amount);
        slice.claimed += amount;

        if (npvGen == slice.npvCredit) {
            npvToken.burn(address(this), slice.npvTokens);
        }

        emit Claimed(id, amount);

        return amount;
    }

    function claim(uint256 id, uint256 limit) external nonReentrant creditSliceOwner(id) returns (uint256) {
        return _claim(id, limit);
    }

    function receiveNPV(uint256 id,
                        address recipient,
                        uint256 amount) external nonReentrant creditSliceOwner(id) {
        CreditSlice storage slice = creditSlices[id];
        ( , uint256 npvGen, ) = generatedCredit(id);
        uint256 available = slice.npvCredit - npvGen;
        if (amount == 0) {
            amount = available;
        }
        require(amount <= available, "YS: insufficient NPV");

        npvToken.transfer(recipient, amount);
        _modifyCreditPosition(id, -int256(amount));

        emit ReceiveNPV(recipient, id, amount);
    }

    function remaining(uint256 id) public view returns (uint256) {
        ( , uint256 npvGen, ) = generatedDebt(id);
        return debtSlices[id].npvDebt - npvGen;
    }

    function generatedDebt(uint256 id) public view returns (uint256, uint256, uint256) {
        DebtSlice storage slice = debtSlices[id];
        uint256 nominal = 0;
        uint256 npv = 0;
        uint256 refund = 0;
        uint256 last = slice.unlockedBlockTimestamp == 0 ? block.timestamp : slice.unlockedBlockTimestamp;

        for (uint256 i = slice.blockTimestamp;
             i < last;
             i += discounter.DISCOUNT_PERIOD()) {

            uint256 end = _min(last - 1, i + discounter.DISCOUNT_PERIOD());
            uint256 yts = debtData.yieldPerTokenPerSecond(uint128(i),
                                                          uint128(end),
                                                          totalTokens(),
                                                          cumulativeYield());

            uint256 yield = (yts * (end - i) * slice.tokens) / debtData.PRECISION_FACTOR();
            uint256 estimatedDays = (end - slice.blockTimestamp) / discounter.DISCOUNT_PERIOD();
            uint256 pv = discounter.pv(estimatedDays, yield);

            if (npv == slice.npvDebt) {
                refund += yield;
            } else if (npv + pv > slice.npvDebt) {
                uint256 owed = discounter.nominal(estimatedDays, slice.npvDebt - npv);
                uint256 leftover = yield - owed;
                nominal += owed;
                refund += leftover;
                npv = slice.npvDebt;
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

        for (uint256 i = slice.blockTimestamp;
             npv < slice.npvCredit && i < block.timestamp;
             i += discounter.DISCOUNT_PERIOD()) {

            uint256 end = _min(block.timestamp - 1, i + discounter.DISCOUNT_PERIOD());
            uint256 yts = creditData.yieldPerTokenPerSecond(uint128(i),
                                                            uint128(end),
                                                            activeNPV,
                                                            cumulativeYieldCredit());

            uint256 yield = (yts * (end - i) * slice.npvTokens) / creditData.PRECISION_FACTOR();
            uint256 estimatedDays = (end - slice.blockTimestamp) / discounter.DISCOUNT_PERIOD();
            uint256 pv = discounter.pv(estimatedDays, yield);

            if (npv + pv > slice.npvCredit) {
                pv = slice.npvCredit - npv;
                yield = discounter.nominal(estimatedDays, pv);
            }

            claimable += yield;
            nominal += yield;
            npv += pv;
        }

        return (slice.pending + nominal,
                npv,
                slice.pending + claimable - slice.claimed);
    }
}
