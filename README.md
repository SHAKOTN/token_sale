# Linear Token Sale

## Token Pricing Linear Formula

### P = Pᵢ + (α × ETHᵣ)

Where:
- P: Current token price in ETH
- Pᵢ: Initial price constant (0.001 ETH <- arbitrary, can be any number)
- α: Price increment rate constant (0.00000001 ETH/ETH <- arbitrary, can be any number)
- ETHᵣ: Total ETH received by contract

(Figure 1) shows the graph of the formula, where x-axis is the total ETH received by contract and y-axis is the token price in ETH.

```
Price
^
|                                      *
|                                 *
|                            *
|                       *
|                  *
|             *
|        *
|   *
|*
+---------------------------------> ETH Received
0                             100k
```

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