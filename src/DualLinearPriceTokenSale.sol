// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LinearToken.sol";

contract DualLinearPriceTokenSale is Ownable, ReentrancyGuard {
    LinearToken public immutable token;

    // Price parameters. Those are arbitrary values and should be adjusted based on the tokenomics
    uint256 public constant INITIAL_PRICE = 0.001 ether; // 0.001 ETH
    uint256 public constant PRICE_INCREMENT = 0.00000001 ether; // 0.00000001 ETH per ETH received

    /// @notice Internal accounting variable to prevent any donation attacks
    uint256 public totalEthReceived;

    event TokensPurchased(address indexed buyer, uint256 ethAmount, uint256 tokenAmount);
    event TokensSold(address indexed seller, uint256 tokenAmount, uint256 ethAmount);
    event PriceUpdate(uint256 newPrice);

    error InvalidTotalSupply();
    error InvalidAmount();
    error NoETHReceived();
    error TransferFailed();

    constructor(uint256 totalSupply) Ownable(msg.sender) {
        if (totalSupply == 0) {
            revert InvalidTotalSupply();
        }
        token = new LinearToken(totalSupply);
    }

    /////////////////////////////////////////////////////////////////
    //////////////////////// View functions /////////////////////////
    /////////////////////////////////////////////////////////////////

    /// @notice Returns the current price of the token
    function getCurrentPrice() public view returns (uint256) {
        return INITIAL_PRICE + (PRICE_INCREMENT * totalEthReceived / 10 ** token.decimals());
    }

    /// @notice Returns the amount of tokens that can be bought with the given amount of ETH
    /// @param ethAmount The amount of ETH to be used to buy tokens
    /// @return The amount of tokens that can be bought
    function calculateTokenAmount(uint256 ethAmount) public view returns (uint256) {
        if (ethAmount == 0) {
            revert InvalidAmount();
        }
        uint256 currentPrice = getCurrentPrice();
        return (ethAmount * 10 ** token.decimals()) / currentPrice;
    }

    /// @notice Returns the amount of ETH that can be received by selling the given amount of tokens
    /// @param tokenAmount The amount of tokens to be sold
    /// @return The amount of ETH that can be received
    function calculateEthAmount(uint256 tokenAmount) public view returns (uint256) {
        if (tokenAmount == 0) {
            revert InvalidAmount();
        }
        uint256 currentPrice = _calculateSellPrice(tokenAmount);
        return (tokenAmount * currentPrice) / 10 ** token.decimals();
    }

    /////////////////////////////////////////////////////////////////
    //////////////////////// State modifying functions //////////////
    /////////////////////////////////////////////////////////////////

    /// @notice Allows users to buy tokens by sending ETH to the contract
    function buyTokens() external payable nonReentrant {
        if (msg.value == 0) {
            revert NoETHReceived();
        }

        uint256 tokenAmount = calculateTokenAmount(msg.value);
        if (tokenAmount == 0) {
            revert InvalidAmount();
        }
        totalEthReceived += msg.value;
        token.mint(msg.sender, tokenAmount);
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }

    /// @notice Allows users to sell tokens and receive ETH from the contract
    /// @param tokenAmount The amount of tokens to be sold
    function sellTokens(uint256 tokenAmount) external nonReentrant {
        if (tokenAmount == 0) {
            revert InvalidAmount();
        }
        uint256 ethAmount = calculateEthAmount(tokenAmount);

        bool success = token.transferFrom(msg.sender, address(this), tokenAmount);
        if (!success) {
            revert TransferFailed();
        }
        // Decrease the totalEthReceived to decrease the price after the sell
        totalEthReceived -= ethAmount;
        token.burn(address(this), tokenAmount);
        (success,) = payable(msg.sender).call{value: ethAmount}("");
        if (!success) {
            revert TransferFailed();
        }
        emit TokensSold(msg.sender, tokenAmount, ethAmount);
    }

    /// @notice Returns the amount of ETH that can be received by selling the given amount of tokens,
    /// @notice we do it, because each sell should decrease the price, kinda like get_dy in Curve
    /// @param tokenAmount The amount of tokens to be sold
    /// @return The amount of ETH that can be received
    function _calculateSellPrice(uint256 tokenAmount) private view returns (uint256) {
        // Sell price is calculated in a get_dy fashion, as we need to know price derivative
        uint256 ethAmount = (tokenAmount * getCurrentPrice()) / 10 ** token.decimals();
        uint256 adjustedEthReceived = totalEthReceived > ethAmount ? totalEthReceived - ethAmount : 0;
        return INITIAL_PRICE + (PRICE_INCREMENT * adjustedEthReceived / 10 ** token.decimals());
    }

    // Admin functions
    /// @notice Withdraws the ETH balance of the contract to the owner
    function withdrawEth() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "ETH transfer failed");
    }
}
