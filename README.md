# Linear Token Sale

## Token Pricing Linear Formula

### P = Pᵢ + (α × ETHᵣ)

Where:
- P: Current token price in ETH
- Pᵢ: Initial price constant (0.001 ETH <- arbitrary, can be any number)
- α: Price increment rate constant (0.00000001 ETH/ETH <- arbitrary, can be any number)
- ETHᵣ: Total ETH received by contract

(Figure 1) shows the graph of the formula, where x-axis is the total ETH received by contract and y-axis is the token price in ETH.

<svg width="800" height="400" xmlns="http://www.w3.org/2000/svg">
    <rect width="100%" height="100%" fill="white"/>
    <line x1="50" y1="350" x2="750" y2="350" stroke="black"/>
    <line x1="50" y1="50" x2="50" y2="350" stroke="black"/>
    <line x1="50" y1="350" x2="750" y2="50" stroke="blue" stroke-width="2"/>
    <text x="400" y="380" text-anchor="middle">ETH Received</text>
    <text x="30" y="200" transform="rotate(-90,30,200)">Price</text>
    <text x="400" y="30" text-anchor="middle">P = Pᵢ + (α × ETHᵣ)</text>
</svg>

The reason it is implemented like this, is because it requires minimum effort and it is hard to game this sale model.
Price pump or dump depends only on one factor - total ETH received by contract.
This is much better, because if it was implemented with time - t, or with amount of holder, or with average 
holder balance, it would be much easier to game the system.

TL;DR - Price increases linearly with ETH received

------------------

## Contracts:
- DualLinearTokenSale.sol - Linear token sale contract
- LinearToken.sol - ERC20 token contract with mint-burn capabilities
- DualLinearTokenSale.t.sol - Test cases for LinearTokenSale contract

## Run tests:
```bash
$ forge test
```

Tests cases are testing different invariants, like:
- Price is increasing linearly with ETH received
- Price is decreasing when ETH is withdrawn
- Sequential trade fairness
- ETH and token balance consistency after multiple trades