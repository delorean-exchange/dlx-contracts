// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

// YieldData keeps track of historical average yields on a periodic basis. It
// uses this data to return the overall average yield for a range of blocks in
// the `yieldPerTokenPerBlock` method. This method is O(N) on the number of
// epochs recorded. Therefore, to prevent excessive gas costs, the interval
// should be set such that N does not exceed around a thousand. An interval of
// 10 days will stay below this limit for a few decades. Keep in mind, though,
// that a larger interval reduces accuracy.
contract YieldData is Ownable {
    uint256 public constant PRECISION_FACTOR = 10**18;

    address public writer;
    uint256 public immutable interval;

    struct Epoch {
        uint256 blockNumber;
        uint256 blocks;
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
                blockNumber: block.number,
                blocks: 0,
                tokens: tokens,
                yield: yield,
                acc: 0 });
        } else {
            Epoch memory c = epochs[epochIndex];

            uint256 blocks = block.number - c.blockNumber - c.blocks;
            uint256 delta = (yield - c.yield);

            c.acc += c.tokens == 0 ? 0 : delta * PRECISION_FACTOR / c.tokens;
            c.blocks += blocks;

            if (c.blocks >= interval) {
                epochPush = Epoch({
                    blockNumber: block.number,
                    blocks: 0,
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

        if (epochSet.blockNumber != 0) {
            epochs[epochIndex] = epochSet;
        }
        if (epochPush.blockNumber != 0) {
            epochs.push(epochPush);
            epochIndex = epochs.length - 1;
        }
    }

    function _find(uint256 blockNumber) internal view returns (uint256) {
        require(epochs.length > 0, "no epochs");
        if (blockNumber >= epochs[epochIndex].blockNumber) return epochIndex;
        if (blockNumber <= epochs[0].blockNumber) return 0;

        uint256 i = epochs.length / 2;
        uint256 start = 0;
        uint256 end = epochs.length;
        while (true) {
            uint256 bn = epochs[i].blockNumber;
            if (blockNumber >= bn &&
                (i + 1 > epochIndex || blockNumber < epochs[i + 1].blockNumber)) {
                return i;
            }

            if (blockNumber > bn) {
                start = i + 1;
            } else {
                end = i;
            }
            i = (start + end) / 2;
        }

        return epochIndex;
    }

    function yieldPerTokenPerBlock(uint256 start, uint256 end, uint256 tokens, uint256 yield) public view returns (uint256) {
        if (start == end) return 0;
        if (start == block.number) return 0;

        require(start < end, "YD: start must precede end");
        require(end <= block.number, "YD: end must be in the past or current");
        require(start < block.number, "YD: start must be in the past");

        uint256 index = _find(start);
        uint256 acc;
        uint256 sum;

        Epoch memory epochPush;
        Epoch memory epochSet;
        if (yield != 0) (epochPush, epochSet) = _record(tokens, yield);
        uint256 maxIndex = epochPush.blockNumber == 0 ? epochIndex : epochIndex + 1;

        while (true) {
            if (index > maxIndex) break;
            Epoch memory epoch;
            if (epochPush.blockNumber != 0 && index == maxIndex) {
                epoch = epochPush;
            } else if (epochSet.blockNumber != 0 && index == epochIndex) {
                epoch = epochSet;
            } else {
                epoch = epochs[index];
            }

            ++index;

            uint256 blocks = epoch.blocks;
            if (blocks == 0) break;
            if (end < epoch.blockNumber) break;

            if (start > epoch.blockNumber) {
                blocks -= start - epoch.blockNumber;
            }
            if (end < epoch.blockNumber + epoch.blocks) {
                blocks -= epoch.blockNumber + epoch.blocks - end;
            }

            uint256 incr = (blocks * epoch.acc) / epoch.blocks;

            acc += incr;
            sum += blocks;

            if (end < epoch.blockNumber + epoch.blocks) break;
        }

        if (sum == 0) return 0;

        return acc / sum;
    }
}
