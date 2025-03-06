// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE); // Add this line
    }

    //CONSTRUCTOR TESTS
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //PRICE FEED TESTS
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountfromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //DEPOSIT COLLATERAL TESTS
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        console.log("ranToken address:", address(ranToken));
        console.log("Price feed for ranToken:", dsce.getCollateralTokenPriceFeed(address(ranToken)));
        vm.startPrank(USER);
        ranToken.approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(ranToken)));
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // MINT DSC TESTS
    function testMintDscRevertsIfZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
    }

    function testMintDscRevertsIfHealthFactorBreaks() public depositedCollateral {
        // Mint amount that would break health factor (2000 USD worth with 20000 USD collateral)
        uint256 excessiveDscAmount = 15000 ether; // Assuming 1 ETH = 2000 USD
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0.666666666666666666e18)
        );
        dsce.mintDsc(excessiveDscAmount);
    }

    function testMintDscSuccess() public depositedCollateral {
        uint256 amountToMint = 100 ether;
        vm.startPrank(USER);
        dsc.approve(address(dsce), amountToMint);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);
    }

    // DEPOSIT COLLATERAL AND MINT DSC TESTS
    function testDepositCollateralAndMintDsc() public {
        uint256 amountCollateral = 5 ether;
        uint256 amountDsc = 50 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsc.approve(address(dsce), amountDsc);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountDsc);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValue) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountDsc);
        assertEq(dsce.getTokenAmountFromUsd(weth, collateralValue), amountCollateral);
    }

    // REDEEM COLLATERAL TESTS
    function testRedeemCollateralRevertsIfZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralSuccess() public depositedCollateral {
        uint256 amountToRedeem = 2 ether;
        vm.prank(USER);
        dsce.redeemCollateral(weth, amountToRedeem);

        (, uint256 collateralValue) = dsce.getAccountInformation(USER);
        uint256 expectedRemaining = AMOUNT_COLLATERAL - amountToRedeem;
        assertEq(dsce.getTokenAmountFromUsd(weth, collateralValue), expectedRemaining);
    }

    // BURN DSC TESTS
    function testBurnDscRevertsIfZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
    }

    function testBurnDscSuccess() public depositedCollateral {
        uint256 amountToMint = 100 ether;
        uint256 amountToBurn = 50 ether;

        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        dsc.approve(address(dsce), amountToBurn);
        dsce.burnDsc(amountToBurn);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint - amountToBurn);
    }

    // REDEEM COLLATERAL FOR DSC TESTS
    function testRedeemCollateralForDsc() public depositedCollateral {
        uint256 amountDscToMint = 100 ether;
        uint256 amountDscToBurn = 50 ether;
        uint256 amountCollateralToRedeem = 2 ether;

        vm.startPrank(USER);
        dsce.mintDsc(amountDscToMint);
        dsc.approve(address(dsce), amountDscToBurn);
        dsce.redeemCollateralForDsc(weth, amountCollateralToRedeem, amountDscToBurn);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValue) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountDscToMint - amountDscToBurn);
        assertEq(dsce.getTokenAmountFromUsd(weth, collateralValue), AMOUNT_COLLATERAL - amountCollateralToRedeem);
    }

    // LIQUIDATION TESTS
    modifier userUndercollateralized() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(18000 ether); // Assuming 1 ETH = 2000 USD, this puts user near liquidation
        vm.stopPrank();
        _;
    }

    function testLiquidateRevertsIfHealthFactorOk() public depositedCollateral {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, 100 ether);
    }

    function testLiquidateSuccess() public {
        // Set price to 2000 USD/ETH
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8); // 2000 * 10^8

        // User deposits 10 ETH and mints 9000 DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); // 10e18
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(9000e18); // 9000 DSC
        vm.stopPrank();

        // Verify initial health factor > 1
        // Collateral = 10 ETH * 2000 USD/ETH = 20000 USD
        // Adjusted = 20000 * 50 / 100 = 10000 USD
        // Health Factor = 10000e18 / 9000e18 ≈ 1.1111e18

        // Drop price to 1000 USD/ETH
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8); // 1000 * 10^8

        // New health factor < 1
        // Collateral = 10 ETH * 1000 USD/ETH = 10000 USD
        // Adjusted = 10000 * 50 / 100 = 5000 USD
        // Health Factor = 5000e18 / 9000e18 ≈ 0.5556e18

        // Liquidator covers 1000 DSC
        uint256 debtToCover = 1000e18;
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL); // 10 ETH = 10000 USD
        dsce.mintDsc(debtToCover); // Health factor = (10000 * 0.5) / 1000 = 5
        dsc.approve(address(dsce), debtToCover);
        dsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();

        // Assertions
        (uint256 userDscMinted, uint256 userCollateralUsd) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 9000e18 - debtToCover); // 8000e18

        uint256 userCollateralEth = dsce.getTokenAmountFromUsd(weth, userCollateralUsd);
        // Debt covered = 1000 USD
        // ETH seized = 1000 / 1000 = 1 ETH
        // Bonus = 10% of 1 ETH = 0.1 ETH
        // Total seized = 1.1 ETH
        // Remaining = 10 - 1.1 = 8.9 ETH
        assertEq(userCollateralEth, 8.9e18);

        (uint256 liquidatorDscMinted, uint256 liquidatorCollateralUsd) = dsce.getAccountInformation(LIQUIDATOR);
        assertEq(dsc.balanceOf(LIQUIDATOR), 0); // Should pass: balance is 0 after transfer
        assertEq(liquidatorDscMinted, 1000e18); // 1000 ether
        uint256 liquidatorCollateralEth = dsce.getTokenAmountFromUsd(weth, liquidatorCollateralUsd);
        // Initial 10 ETH + 1.1 ETH seized = 11.1 ETH
        assertEq(liquidatorCollateralEth, 10e18); // Deposited collateral remains 10 ETH
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        assertEq(liquidatorWethBalance, 1.1e18); // Received 1.1 ETH from liquidation
    }

    // HEALTH FACTOR TESTS
    function testGetAccountInformation() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
    }
}
