# ERC20 AMM Token

A custom ERC20 token with a built-in Automated Market Maker (AMM) 
pricing model, built with Solidity and tested with Hardhat 3.

## Features
- Dynamic pricing using constant product formula (x*y=k)
- 0.3% trading fee with separate fee tracking
- Slippage protection on all trades
- State machine (Waiting/Active/Paused)
- Owner fee withdrawal without draining liquidity
- Max supply cap
- Ownership transfer
- 12 passing Hardhat tests

## How the pricing works
Price is determined by the ratio of ETH to tokens in the contract.
When someone buys, ETH goes up and tokens go down, raising the price.
When someone sells, the opposite happens.

## Tech Stack
- Solidity 0.8.28
- OpenZeppelin ERC20 + ReentrancyGuard
- Hardhat 3
- Ethers.js
- Mocha + Chai

## Setup
```bash
npm install
npx hardhat test
```

## Warning
This is a learning project. Not audited. 
Do not use with real funds on mainnet.
