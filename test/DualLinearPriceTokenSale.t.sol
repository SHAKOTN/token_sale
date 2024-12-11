// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

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
        assertEq(0, linearSale.getHolderCount());
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
            console.log("Purchase amount: ", purchaseAmount);
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
        uint256 totalHoldersCount = linearSale.getHolderCount();
        for (uint256 i = 0; i < numUsers; i++) {
            // Get the user address
            address user = addresses[i];
            vm.deal(user, 100 ether);
            // Calculate the purchase amount for this user
            uint256 purchaseAmount = (i + 1) * 1 ether;
            console.log("Buy amount: ", purchaseAmount, " for user: ", i);
            console.log("Current price: ", linearSale.getCurrentPrice());
            console.log("Contract eth balance: ", address(linearSale).balance);
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
            assertGt(linearSale.getHolderCount(), totalHoldersCount);
            totalHoldersCount = linearSale.getHolderCount();
        }
        previousPrice = linearSale.getCurrentPrice();
        totalHoldersBalance = token.totalSupply();
        totalHoldersCount = linearSale.getHolderCount();
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
            assertLt(linearSale.getHolderCount(), totalHoldersCount);
            totalHoldersCount = linearSale.getHolderCount();

            // Make sure user is no longer holder after selling all tokens
            assertFalse(linearSale.isHolder(user));
        }
        // Make sure no eth in the contract
        assertLe(address(linearSale).balance, 1 ether);
    }
}
