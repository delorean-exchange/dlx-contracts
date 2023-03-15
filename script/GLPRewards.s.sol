// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import "../src/interfaces/IDiscounter.sol";

contract GLPRewardsScript is Script {
    using stdJson for string;

    function setUp() public {}

    function run() public {
        uint256 pk = vm.envUint("LOCALHOST_PRIVATE_KEY");
        /* uint256 pk = vm.envUint("ARBITRUM_PRIVATE_KEY"); */
        vm.startBroadcast(pk);

        string memory historical = vm.readFile("json/historical.json");
        string memory config = vm.readFile("json/config.localhost.json");
        /* string memory config = vm.readFile("json/config.arbitrum.json"); */

        uint256 daily = vm.parseJsonUint(historical, ".glp.avgDailyRewardPerToken");
        address discounter = vm.parseJsonAddress(config, ".fakeglp_discounter.address");
        
        console.log("daily", daily);
        console.log("discounter", discounter);

        IDiscounter(discounter).setDaily(daily);

        vm.stopBroadcast();
    }
}
