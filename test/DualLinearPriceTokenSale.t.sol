// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {VmSafe} from "forge-std/StdUtils.sol";
import {LinearToken} from "../src/DualLinearPriceTokenSale.sol";
import {DualLinearPriceTokenSale} from "../src/DualLinearPriceTokenSale.sol";

contract DualLinearPriceTokenSaleTest is Test {
    using stdStorage for StdStorage;

    DualLinearPriceTokenSale public linearSale;
    LinearToken public token;
    uint256 public constant TOTAL_SUPPLY = 100_000_000e18;
    // Create 3 users
    VmSafe.Wallet public User1;
    VmSafe.Wallet public User2;
    VmSafe.Wallet public User3;

    // Create admin
    VmSafe.Wallet public Admin;

    function _setStorage(address _user, bytes4 _selector, address _contract, uint256 value) public {
        uint256 slot = stdstore.target(_contract).sig(_selector).with_key(_user).find();
        vm.store(_contract, bytes32(slot), bytes32(value));
    }

    function setUp() public virtual {
        User1 = vm.createWallet("User1");
        User2 = vm.createWallet("User2");
        User3 = vm.createWallet("User3");
        Admin = vm.createWallet("Admin");
        vm.deal(User1.addr, 100 ether);
        vm.deal(User2.addr, 100 ether);
        vm.deal(User3.addr, 100 ether);
        vm.deal(Admin.addr, 100 ether);
        vm.startPrank(Admin.addr);
        linearSale = new DualLinearPriceTokenSale(TOTAL_SUPPLY);
        vm.stopPrank();

        token = linearSale.token();
    }

    // Just basic test to make sure the contract is setup correctly
    function testBuySellTokensBasic__OneHolder(uint256 purchaseAmount) public {
        purchaseAmount = bound(purchaseAmount, 1 ether, 100 ether);
        uint256 currentPrice = linearSale.getCurrentPrice();
        // Current price should be base price as we have not added any supply or holders
        assertEq(currentPrice, linearSale.INITIAL_PRICE());

        uint256 tokenAmount = linearSale.calculateTokenAmount(purchaseAmount);
        // Snap the current balance of User1
        uint256 user1EthBalance = User1.addr.balance;
        // Buy tokens for user1
        vm.prank(User1.addr);
        linearSale.buyTokens{value: purchaseAmount}();
        assert(user1EthBalance - purchaseAmount == User1.addr.balance);
        assertEq(tokenAmount, token.balanceOf(User1.addr));

        // Sell tokens back
        vm.startPrank(User1.addr);
        token.approve(address(linearSale), tokenAmount);
        linearSale.sellTokens(tokenAmount);
        vm.stopPrank();

        // Make sure the user1 balance is restored
        assertEq(user1EthBalance, User1.addr.balance);
        assertEq(0, token.balanceOf(User1.addr));
        // Make sure price is back to base price
        assertEq(linearSale.INITIAL_PRICE(), linearSale.getCurrentPrice());
    }

    // Invariant to test price increases linearly
    function testPriceIncreasesLinearly() public {
        // Setup multiple users and give them ETH
        uint256 numUsers = 120;
        address[] memory addresses = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            string memory seed = string(abi.encodePacked("user", i));
            addresses[i] = vm.createWallet(seed).addr;
            vm.deal(addresses[i], 1 ether);
        }
        uint256 priceDifference;
        uint256 previousPrice = linearSale.getCurrentPrice();

        // Have each user buy same amount to isolate holder count impact
        uint256 constantBuyAmount = 1 ether;

        for (uint256 i = 0; i < numUsers; i++) {
            // Buy tokens
            vm.prank(addresses[i]);
            linearSale.buyTokens{value: constantBuyAmount}();

            // Get new price
            uint256 newPrice = linearSale.getCurrentPrice();

            // Store price difference (skip first one as we don't have previous)
            if (i > 0) {
                // Calculate price difference only once (as it should be same for all) as we have linear equation
                if (priceDifference == 0) {
                    priceDifference = newPrice - previousPrice;
                }
                uint256 priceDifferenceActual = newPrice - previousPrice;

                // If not first difference, compare with previous difference
                if (i > 1) {
                    assertEq(priceDifference, priceDifferenceActual);
                }
            }

            previousPrice = newPrice;
        }
    }

    // Invariant to test price decreases linearly at constant rate
    function testPriceDecreasesLinearly() public {
        // Setup multiple users and give them ETH
        uint256 numUsers = 100;
        address[] memory addresses = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            string memory seed = string(abi.encodePacked("user", i));
            addresses[i] = vm.createWallet(seed).addr;
            vm.deal(addresses[i], 1 ether);
        }

        // Have each user buy tokens with 1 ETH
        uint256 constantBuyAmount = 1 ether;
        for (uint256 i = 0; i < numUsers; i++) {
            vm.prank(addresses[i]);
            linearSale.buyTokens{value: constantBuyAmount}();
        }

        uint256 priceDifference;
        uint256 previousPrice = linearSale.getCurrentPrice();

        // Have each user sell their tokens, but in reverse order so we can prove price decreases linearly
        for (uint256 i = numUsers - 1; i >= 0; i--) {
            // Select minimum amount of tokens to sell
            uint256 tokenAmount = token.balanceOf(addresses[i]);
            vm.startPrank(addresses[i]);
            token.approve(address(linearSale), tokenAmount);
            linearSale.sellTokens(tokenAmount);
            vm.stopPrank();

            // Get new price
            uint256 newPrice = linearSale.getCurrentPrice();
            // Store price difference (skip first one as we don't have previous)
            if (i > 0) {
                // Calculate price difference only once (as it should be same for all) as we have linear equation
                if (priceDifference == 0) {
                    priceDifference = previousPrice - newPrice;
                }
                uint256 priceDifferenceActual = previousPrice - newPrice;
                // Allow very small margin of error
                assertApproxEqAbs(priceDifference, priceDifferenceActual, 1);
            }

            previousPrice = newPrice;
            // Break the loop if i is 0
            if (i == 0) {
                break;
            }
        }
    }

    // Testing invariant that the price increases as more tokens are bought
    function testBuySellTokensWithMultipleHolders_PriceClimb() public {
        // Define the number of users to test
        uint256 numUsers = 100;
        address[] memory addresses = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            string memory seed = string(abi.encodePacked("user", i));
            addresses[i] = vm.createWallet(seed).addr;
        }
        // Loop through the users and have them purchase tokens
        uint256 previousPrice = linearSale.INITIAL_PRICE();
        for (uint256 i = 0; i < numUsers; i++) {
            // Get the user address
            address user = addresses[i];
            vm.deal(user, 100 ether);
            // Calculate the purchase amount for this user
            uint256 purchaseAmount = (i + 1) * 1 ether;
            // Have the user purchase the tokens
            vm.prank(user);
            linearSale.buyTokens{value: purchaseAmount}();

            // Check that the price has increased
            uint256 currentPrice = linearSale.getCurrentPrice();
            if (i > 0) {
                assertGt(currentPrice, previousPrice);
                previousPrice = currentPrice;
            }
        }
    }

    // Testing invariant that the price decreases as more tokens are sold
    function testBuySellTokensWithMultipleHolders_PriceDrop() public {
        // Define the number of users to test
        uint256 numUsers = 100;
        address[] memory addresses = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            string memory seed = string(abi.encodePacked("user", i));
            addresses[i] = vm.createWallet(seed).addr;
        }
        // Loop through the users and have them purchase tokens
        uint256 previousPrice = linearSale.INITIAL_PRICE();
        uint256 totalHoldersBalance = token.totalSupply();
        for (uint256 i = 0; i < numUsers; i++) {
            // Get the user address
            address user = addresses[i];
            vm.deal(user, 100 ether);
            // Calculate the purchase amount for this user
            uint256 purchaseAmount = (i + 1) * 1 ether;
            // Have the user purchase the tokens
            vm.prank(user);
            linearSale.buyTokens{value: purchaseAmount}();

            // Check that the price has increased
            uint256 currentPrice = linearSale.getCurrentPrice();
            // Making sure invariant holds
            assertGt(currentPrice, previousPrice);
            previousPrice = currentPrice;
            assertGt(token.totalSupply(), totalHoldersBalance);
            totalHoldersBalance = token.totalSupply();
        }
        previousPrice = linearSale.getCurrentPrice();
        totalHoldersBalance = token.totalSupply();
        // Loop through the users and have them sell tokens
        for (uint256 i = 0; i < numUsers; i++) {
            // Get the user address
            address user = addresses[i];
            // Jeet all the tokens
            uint256 sellAmount = token.balanceOf(user);
            // Have the user sell the tokens
            vm.startPrank(user);
            token.approve(address(linearSale), sellAmount);
            linearSale.sellTokens(sellAmount);
            // Check that the price has increased
            uint256 currentPrice = linearSale.getCurrentPrice();
            // Making sure invariant holds
            assertLt(currentPrice, previousPrice);
            previousPrice = currentPrice;
            assertLt(token.totalSupply(), totalHoldersBalance);
            totalHoldersBalance = token.totalSupply();

            // Make sure user is no longer holder after selling all tokens
            assertEq(0, token.balanceOf(user));
        }
        // Make sure no eth in the contract
        assertLe(address(linearSale).balance, 1 ether);
    }

    // Invariant to test token balance consistency
    function testTokenBalanceConsistency() public {
        uint256 initialSupply = token.totalSupply();
        uint256 totalUserBalance = 0;
        // Perform multiple buy and sell operations
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(User1.addr);
            linearSale.buyTokens{value: 1 ether}();
            totalUserBalance += token.balanceOf(User1.addr);
            vm.startPrank(User1.addr);
            uint256 tokenAmount = token.balanceOf(User1.addr);
            token.approve(address(linearSale), tokenAmount);
            linearSale.sellTokens(tokenAmount);
            totalUserBalance -= tokenAmount;
            vm.stopPrank();
        }
        // Ensure total token balance is consistent
        uint256 contractBalance = token.balanceOf(address(linearSale));
        assertEq(initialSupply, totalUserBalance + contractBalance);
    }

    // Invariant to test ETH balance consistency
    function testEthBalanceConsistency() public {
        uint256 initialEthBalance = address(linearSale).balance;
        uint256 totalEthReceived = 0;
        uint256 totalEthPaidOut = 0;

        // Perform multiple buy and sell operations
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(User1.addr);
            linearSale.buyTokens{value: 1 ether}();
            totalEthReceived += 1 ether;

            vm.startPrank(User1.addr);
            uint256 tokenAmount = token.balanceOf(User1.addr);
            token.approve(address(linearSale), tokenAmount);
            linearSale.sellTokens(tokenAmount);
            totalEthPaidOut += linearSale.calculateEthAmount(tokenAmount);
            vm.stopPrank();
        }

        // Ensure ETH balance is consistent
        uint256 expectedEthBalance = initialEthBalance + totalEthReceived - totalEthPaidOut;
        assertEq(expectedEthBalance, address(linearSale).balance);
    }

    // Invariant to test price calculation accuracy
    function testPriceCalculationAccuracy() public {
        uint256 totalEthReceived = 0;
        // Perform multiple buy operations
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(User1.addr);
            linearSale.buyTokens{value: 1 ether}();
            totalEthReceived += 1 ether;
            uint256 expectedPrice =
                linearSale.INITIAL_PRICE() + (linearSale.PRICE_INCREMENT() * totalEthReceived / 10 ** token.decimals());
            assertEq(linearSale.getCurrentPrice(), expectedPrice);
        }
    }

    // Invariant to test totalEthReceived is not less than the price of the total supply
    function testTotalEthReceivedInvariant() public {
        uint256 totalEthReceived = 0;

        for (uint256 i = 0; i < 50; i++) {
            vm.prank(User1.addr);
            linearSale.buyTokens{value: 1 ether}();
            totalEthReceived += 1 ether;
            vm.stopPrank();
        }

        // Ensure totalEthReceived is not less than the price of the total supply
        uint256 totalSupplyPrice = linearSale.calculateEthAmount(token.totalSupply());
        assertGe(totalEthReceived, totalSupplyPrice);
    }
}
