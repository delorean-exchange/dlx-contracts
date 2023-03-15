// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import "./helpers/FakeToken.sol";
import "./helpers/FakeYieldSource.sol";
import "../src/liquidity/UniswapV3LiquidityPool.sol";
import "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import "../src/tokens/NPVToken.sol";
import "../src/core/YieldSlice.sol";
import "../src/core/NPVSwap.sol";
import "../src/data/Discounter.sol";
import "../src/data/YieldData.sol";

contract BaseTest is Test {
    // Arbitrum Mainnet
    address public arbitrumUniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public arbitrumNonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public arbitrumSwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public arbitrumQuoterV2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    address public arbitrumQuoterV1 = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    // Arbitrum Goerli
    /* address public arbitrumUniswapV3Factory = 0x4893376342d5D7b3e31d4184c08b265e5aB2A3f6; */
    /* address public arbitrumNonfungiblePositionManager = 0x622e4726a167799826d1E1D150b076A7725f5D81; */
    /* address public arbitrumSwapRouter = 0xab7664500b19a7a2362Ab26081e6DfB971B6F1B0; */
    /* address public arbitrumQuoterV2 = 0x1dd92b83591781D0C6d98d07391eea4b9a6008FA; */

    FakeYieldSource public source;

    NPVToken public npvToken;
    NPVSwap public npvSwap;
    YieldSlice public slice;
    YieldData public dataDebt;
    YieldData public dataCredit;
    Discounter public discounter;

    IERC20 public generatorToken;
    IERC20 public yieldToken;

    UniswapV3LiquidityPool public pool;
    IUniswapV3Pool public uniswapV3Pool;
    INonfungiblePositionManager public manager;

    address alice;
    address bob;
    address chad;

    uint256 arbitrumFork;

    function init() public {
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.selectFork(arbitrumFork);

        source = new FakeYieldSource(10000000000000);
        generatorToken = source.generatorToken();
        yieldToken = source.yieldToken();
        dataDebt = new YieldData(20);
        dataCredit = new YieldData(20);
        npvToken = new NPVToken("npv[ETH] of FAKE", "npvE:FAKE");
        discounter = new Discounter(1e13, 500, 360, 18);
        slice = new YieldSlice(address(npvToken),
                               address(source),
                               address(dataDebt),
                               address(dataCredit),
                               address(discounter),
                               1e18);

        alice = createUser(0);
        bob = createUser(1);
        chad = createUser(2);

        source.setOwner(address(slice));
        dataDebt.setWriter(address(slice));
        dataCredit.setWriter(address(slice));

        source.mintBoth(alice, 1000000e18);

        manager = INonfungiblePositionManager(arbitrumNonfungiblePositionManager);
        (address token0, address token1) = address(npvToken) < address(yieldToken)
            ? (address(npvToken), address(yieldToken))
            : (address(yieldToken), address(npvToken));
        uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(arbitrumUniswapV3Factory).getPool(token0, token1, 3000));
        if (address(uniswapV3Pool) == address(0)) {
            uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(arbitrumUniswapV3Factory).createPool(token0, token1, 3000));
            IUniswapV3Pool(uniswapV3Pool).initialize(79228162514264337593543950336);
        }
        pool = new UniswapV3LiquidityPool(address(uniswapV3Pool), arbitrumSwapRouter, arbitrumQuoterV2);

        npvSwap = new NPVSwap(address(npvToken), address(slice), address(pool));
    }

    function createUser(uint32 i) public returns (address) {
        string memory mnemonic = "test test test test test test test test test test test junk";
        uint256 privateKey = vm.deriveKey(mnemonic, i);
        address user = vm.addr(privateKey);
        vm.deal(user, 100 ether);
        return user;
    }

    function assertClose(uint256 x, uint256 target, uint256 tolerance) public {
        if (x > target) assertTrue(x - target <= tolerance);
        else assertTrue(target - x <= tolerance);
    }

}
