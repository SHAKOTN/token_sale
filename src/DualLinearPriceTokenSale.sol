// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {console} from "../lib/forge-std/src/console.sol";

contract LinearToken is ERC20, Ownable {
    constructor(uint256 totalSupply) ERC20("Linear Price Token", "LPT") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

contract DualLinearPriceTokenSale is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    LinearToken public immutable token;

    // Price parameters. Those are arbitrary values and should be adjusted based on the tokenomics
    uint256 public constant INITIAL_PRICE = 0.001 ether; // 0.001 ETH
    uint256 public constant SUPPLY_RATE = 0.00000001 ether; // 0.00000001 ETH per token
    uint256 public constant HOLDER_RATE = 0.0000001 ether; // 0.0000001 ETH per holder

    // Holder tracking
    EnumerableSet.AddressSet private holders;

    event TokensPurchased(address indexed buyer, uint256 ethAmount, uint256 tokenAmount);
    event TokensSold(address indexed seller, uint256 tokenAmount, uint256 ethAmount);
    event PriceUpdate(uint256 newPrice);

    constructor(uint256 totalSupply) Ownable(msg.sender) {
        require(totalSupply > 0, "Total supply must be greater than 0");
        token = new LinearToken(totalSupply);
    }

    /////////////////////////////////////////////////////////////////
    //////////////////////// View functions /////////////////////////
    /////////////////////////////////////////////////////////////////

    function getCurrentPrice() public view returns (uint256) {
        if (holders.length() == 0 || token.totalSupply() == 0) {
            return INITIAL_PRICE;
        }
        uint256 supplyImpact = SUPPLY_RATE * token.totalSupply() / 10 ** token.decimals();
        uint256 holderImpact = HOLDER_RATE * holders.length();
        return INITIAL_PRICE + supplyImpact + holderImpact;
    }

    function calculateSellPrice(uint256 tokenAmount) public view returns (uint256) {
        uint256 adjustedHolders = holders.length() - 1;
        uint256 adjustedBalance = token.totalSupply() - tokenAmount;

        if (adjustedHolders == 0 || adjustedBalance == 0) {
            return INITIAL_PRICE;
        }

        uint256 supplyImpact = SUPPLY_RATE * adjustedBalance / 10 ** token.decimals();
        uint256 holderImpact = HOLDER_RATE * adjustedHolders;
        return INITIAL_PRICE + supplyImpact + holderImpact;
    }

    function getPrice(bool isBuying, uint256 amount) public view returns (uint256) {
        if (isBuying) {
            // For buying, use future state (after buyer joins)
            uint256 futureHolders = holders.length() + 1;
            uint256 futureBalance = token.totalSupply() + amount;
            uint256 supplyImpact = SUPPLY_RATE * futureBalance / 10 ** token.decimals();
            uint256 holderImpact = HOLDER_RATE * futureHolders;
            return INITIAL_PRICE + supplyImpact + holderImpact;
        } else {
            // For selling, use state after seller leaves
            uint256 remainingHolders = holders.length() - 1;
            uint256 remainingBalance = token.totalSupply() - amount;

            if (remainingHolders == 0 || remainingBalance == 0) {
                return INITIAL_PRICE;
            }

            uint256 supplyImpact = SUPPLY_RATE * remainingBalance / 10 ** token.decimals();
            uint256 holderImpact = HOLDER_RATE * remainingHolders;
            return INITIAL_PRICE + supplyImpact + holderImpact;
        }
    }

    function calculateTokenAmount(uint256 ethAmount) public view returns (uint256) {
        require(ethAmount > 0, "Amount must be greater than 0");
        uint256 currentPrice = getCurrentPrice();
        return (ethAmount * 10 ** token.decimals()) / currentPrice;
    }

    function calculateEthAmount(uint256 tokenAmount) public view returns (uint256) {
        require(tokenAmount > 0, "Amount must be greater than 0");
        // In case there is one holder, we should give back only the initial price
        uint256 currentPrice = holders.length() > 1 ? calculateSellPrice(tokenAmount) : INITIAL_PRICE;
        return (tokenAmount * currentPrice) / 10 ** token.decimals();
    }

    function getHolderCount() external view returns (uint256) {
        return holders.length();
    }

    function isHolder(address user) external view returns (bool) {
        return holders.contains(user);
    }

    /////////////////////////////////////////////////////////////////
    //////////////////////// State modifying functions //////////////
    /////////////////////////////////////////////////////////////////

    function buyTokens() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH to buy tokens");

        uint256 tokenAmount = calculateTokenAmount(msg.value);
        require(tokenAmount > 0, "Not enough ETH sent");

        token.mint(msg.sender, tokenAmount);
        _updateHolderInfo(msg.sender);
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }

    function sellTokens(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Amount must be greater than 0");

        uint256 ethAmount = calculateEthAmount(tokenAmount);
        require(address(this).balance >= ethAmount, "Contract has insufficient ETH balance");

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");

        token.burn(address(this), tokenAmount);
        _updateHolderInfo(msg.sender);
        (bool success,) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        emit TokensSold(msg.sender, tokenAmount, ethAmount);
    }

    //////////////////////// Internal functions /////////////////////////
    function _updateHolderInfo(address user) private {
        uint256 userBalance = token.balanceOf(user);
        if (!holders.contains(user) && userBalance > 0) {
            // New holder
            holders.add(user);
        } else if (holders.contains(user)) {
            // Existing holder
            if (userBalance == 0) {
                // Remove holder
                holders.remove(user);
            }
        }
    }

    // Admin functions
    function withdrawEth() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "ETH transfer failed");
    }
}
