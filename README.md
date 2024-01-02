# DAMM Protocol

Decentralized Autonomous Money Management *(DAMM)* is a protocol for that facilitates the active management of DeFi positions by operators on behalf of investor(s). It is compatible with _any_ EVM based blockchains. DAMM is designed to be non-custoial, permissionless, and trustless solution for money management in Ethereum DeFi ecosystem.


## Protocol Design

There are four main components in the DAMM protocol:
- Routers
- TokenWhitelistRegistry
- DAMMGnosisSafeModule
- RouterWhitelistRegistry

### Routers
Routers are immutable stateless modular contracts that interface with external DeFi protocols. They are responsible for executing trades on behalf of the caller. Anyone can create and launch a router by extending the [`BaseRouter.sol`](./src/base/BaseRouter.sol) contract. Routers provide the following garantuees:
- Only assets that have been previously whitelisted by the owner in the TokenWhitelistRegistry can be traded.
- The router caller must be the holder of the assets.
- Outbound funds (profits, liquidity positions, etc) from the underlying router's DeFi protocol can only be sent back to the owner of the assets.

### [TokenWhitelistRegistry](./src/base/TokenWhitelistRegistry.sol)
The TokenWhitelistRegistry is a registry of whitelisted tokens. It is responsible for keeping track of the tokens that have been whitelisted by the owner. The owner can add or remove tokens from the registry at any time. Callers cannot whitelist tokens on behalf of others.

### [DAMMGnosisSafeModule](./src/base/DAMMGnosisSafeModule.sol)
The DAMMGnosisSafeModule is a Gnosis Safe module that allows operators to trade assets escrowed inside the safe on behalf of the Safe owner(s). Routers must be whitelisted in the RouterWhitelistRegistry by the Gnosis Safe in order to be used by the module. Tokens must also be whitelisted in the TokenWhitelistRegistry by the Gnosis Safe in order to be traded by the module. The DAMMGnosisSafeModule provides the following garantuees:
- Only whitelisted routers can be used.
- Only whitelisted tokens can be traded on the whitelisted routers.
- Only whitelisted operators can execute trades that comply with the above whitelist permissions on behalf of the Gnosis Safe owner(s).

### [RouterWhitelistRegistry](./src/base/RouterWhitelistRegistry.sol)
The RouterWhitelistRegistry is a registry of whitelisted routers. It is responsible for keeping track of the routers that have been whitelisted by Gnosis Safe Owners. The owner can add or remove routers from the registry at any time. Callers cannot whitelist routers on behalf of others.

## Current Routers

> Reminder: Assets must be whitelisted in the TokenWhitelistRegistry in order to be traded by the routers.

### [UniswapV3PositionRouter](./src/routers/UniswapV3PositionRouter.sol)
The UniswapV3PositionRouter is a router that allows users to create and manage Uniswap V3 positions.

### [UniswapV3SwapRouter](./src/routers/UniswapV3SwapRouter.sol)
The UniswapV3SwapRouter is a router that allows users to swap tokens using Uniswap V3.

## Usage

### Build

```shell
$ forge build
```

### Unit Test

```shell
$ forge test
```

### Symbolic Test

> Requires previously installation of the [halmos library.](https://github.com/a16z/halmos)

```shell
$ halmos --test-parallel
```
