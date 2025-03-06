// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;

// //What are our invariants?
// //1. The total supply of DSC should be less than the total value of collateral
// //2.Getter view functions should never revert -> evergreen invariant

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "script/DeployDSC.s.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "script/HelperConfig.s.sol";
// import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         (,, weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         //get all the value of all the collateral in the protocol
//         //compare it to all the debt (dsc)
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethdeposited = IERC20(weth).balanceOf(address(dsce)); //total amount of weth deposited into that contract
//         uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce)); //total amount of btc deposited into that contract
//         uint256 wethValue = dsce.getUsdValue(weth, totalWethdeposited);
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
