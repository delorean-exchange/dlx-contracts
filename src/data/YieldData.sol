// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

// YieldData keeps track of historical average yields on a periodic basis. It
// uses this data to return the overall average yield for a range of time in
// the `yieldPerTokenPerSlock` method. This method is O(N) on the number of
// epochs recorded. Therefore, to prevent excessive gas costs, the interval
// should be set such that N does not exceed around a thousand. An interval of
// 10 days will stay below this limit for a few decades. Keep in mind, though,
// that a larger interval reduces accuracy.
contract YieldData is Ownable {
    uint256 public constant PRECISION_FACTOR = 10**18;

    address public writer;
    uint256 public immutable interval;

    struct Epoch {
        uint256 blockTimestamp;
        uint256 epochSeconds;
        uint256 tokens;
        uint256 yield;
        uint256 acc;
    }
    Epoch[] public epochs;
    uint256 public epochIndex;

    constructor(uint256 interval_) {
        interval = interval_;
    }

    function setWriter(address writer_) external onlyOwner {
        require(writer_ != address(0), "YD: zero address");
        writer = writer_;
    }

    function isEmpty() external view returns (bool) {
        return epochs.length == 0;
    }

    function current() external view returns (Epoch memory) {
        return epochs[epochIndex];
    }

    function _record(uint256 tokens, uint256 yield) internal view returns
        (Epoch memory epochPush, Epoch memory epochSet) {

        if (epochs.length == 0) {
            epochPush = Epoch({
                blockTimestamp: block.timestamp,
                epochSeconds: 0,
                tokens: tokens,
                yield: yield,
                acc: 0 });
        } else {
            Epoch memory c = epochs[epochIndex];

            console.log("uint256 epochSeconds =", block.timestamp, c.blockTimestamp, c.epochSeconds);
            uint256 epochSeconds = block.timestamp - c.blockTimestamp - c.epochSeconds;
            uint256 delta = (yield - c.yield);

            c.acc += c.tokens == 0 ? 0 : delta * PRECISION_FACTOR / c.tokens;
            c.epochSeconds += epochSeconds;

            if (c.epochSeconds >= interval) {
                epochPush = Epoch({
                    blockTimestamp: block.timestamp,
                    epochSeconds: 0,
                    tokens: tokens,
                    yield: yield,
                    acc: 0 });
            } else {
                c.tokens = tokens;
            }

            c.yield = yield;
            epochSet = c;
        }
    }

    function record(uint256 tokens, uint256 yield) external {
        require(msg.sender == writer, "YD: only writer");

        (Epoch memory epochPush, Epoch memory epochSet) = _record(tokens, yield);

        if (epochSet.blockTimestamp != 0) {
            epochs[epochIndex] = epochSet;
        }
        if (epochPush.blockTimestamp != 0) {
            epochs.push(epochPush);
            epochIndex = epochs.length - 1;
        }
    }

    function _find(uint256 blockTimestamp) internal view returns (uint256) {
        require(epochs.length > 0, "no epochs");
        if (blockTimestamp >= epochs[epochIndex].blockTimestamp) return epochIndex;
        if (blockTimestamp <= epochs[0].blockTimestamp) return 0;

        uint256 i = epochs.length / 2;
        uint256 start = 0;
        uint256 end = epochs.length;
        while (true) {
            uint256 bn = epochs[i].blockTimestamp;
            if (blockTimestamp >= bn &&
                (i + 1 > epochIndex || blockTimestamp < epochs[i + 1].blockTimestamp)) {
                return i;
            }

            if (blockTimestamp > bn) {
                start = i + 1;
            } else {
                end = i;
            }
            i = (start + end) / 2;
        }

        return epochIndex;
    }

    function yieldPerTokenPerSecond(uint256 start, uint256 end, uint256 tokens, uint256 yield) public view returns (uint256) {
        if (start == end) return 0;
        if (start == block.timestamp) return 0;

        require(start < end, "YD: start must precede end");
        require(end <= block.timestamp, "YD: end must be in the past or current");
        require(start < block.timestamp, "YD: start must be in the past");

        uint256 index = _find(start);
        uint256 acc;
        uint256 sum;

        Epoch memory epochPush;
        Epoch memory epochSet;
        if (yield != 0) (epochPush, epochSet) = _record(tokens, yield);
        uint256 maxIndex = epochPush.blockTimestamp == 0 ? epochIndex : epochIndex + 1;

        while (true) {
            if (index > maxIndex) break;
            Epoch memory epoch;
            if (epochPush.blockTimestamp != 0 && index == maxIndex) {
                epoch = epochPush;
            } else if (epochSet.blockTimestamp != 0 && index == epochIndex) {
                epoch = epochSet;
            } else {
                epoch = epochs[index];
            }

            ++index;

            uint256 epochSeconds = epoch.epochSeconds;
            if (epochSeconds == 0) break;
            if (end < epoch.blockTimestamp) break;

            if (start > epoch.blockTimestamp) {
                epochSeconds -= start - epoch.blockTimestamp;
            }
            if (end < epoch.blockTimestamp + epoch.epochSeconds) {
                epochSeconds -= epoch.blockTimestamp + epoch.epochSeconds - end;
            }

            uint256 incr = (epochSeconds * epoch.acc) / epoch.epochSeconds;

            acc += incr;
            sum += epochSeconds;

            if (end < epoch.blockTimestamp + epoch.epochSeconds) break;
        }

        if (sum == 0) return 0;

        return acc / sum;
    }
}
