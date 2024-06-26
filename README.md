> Disclaimer!! This is an old version of the DAMM protocol. Use for educational purposes only.

# DAMM Protocol

Decentralized Autonomous Money Management **(DAMM)** is a protocol that facilitates the active management of DeFi positions by operators on behalf of investor(s). It is compatible with _any_ EVM based blockchain. **DAMM** is designed to be a non-custoial, permissionless, and trustless solution for money management in Ethereum DeFi ecosystem.


## Protocol Design

There are four main components that make the **DAMM** protocol:
- Routers
- TokenWhitelistRegistry
- VaultRouterModule
- RouterWhitelistRegistry

### Routers
A Router is an immutable stateless modular contract that interfaces with an external DeFi protocol. It is responsible for verifying and executing trades on behalf of the caller. Routers provide the following guarantees:
- A trade can only be executed if the underlying assets have been previously whitelisted to the `TokenWhitelistRegistry` by the caller.
- The caller must be the current holder of the assets to be traded.
- **ALL** output generated by a trade (profits, liquidity positions, etc) must be sent back to the caller.

> Anyone can create and launch a DAMM Router by extending the [`BaseRouter.sol`](./src/base/BaseRouter.sol) contract.

---

### [TokenWhitelistRegistry](./src/base/TokenWhitelistRegistry.sol)
The `TokenWhitelistRegistry` is a registry of whitelisted tokens. It is responsible for keeping track of the tokens that have been whitelisted by individual investors. Investors can whitelist or blacklist tokens from the registry at any time. Callers can **ONLY** whitelist (or blacklist) tokens on behalf of themselves.

---

### [VaultRouterModule](./src/base/VaultRouterModule.sol)
The `VaultRouterModule` is a Gnosis Safe module that allows operators to trade assets escrowed inside a safe on behalf of the owner(s). Operators are enabled by the safe owners. To enable operators to trade assets on their behalf, the Safe owner(s) must first: 
- Enable the `VaultRouterModule` module on the Gnosis Safe.
- Whitelist the routers that the operator will be allowed to use to the `RouterWhitelistRegsitry`.
- Whitelist the tokens that the operator will be allowed to trade to the `TokenWhitelistRegistry`.

The `VaultRouterModule` provides the following guarantees:
- Only whitelisted routers can be used.
- Only whitelisted tokens can be traded on the whitelisted routers.
- Only whitelisted operators can execute trades that comply with the above whitelist permissions on behalf of the Gnosis Safe owner(s).
- All Router guarantees are inherited.

---

### [RouterWhitelistRegistry](./src/base/RouterWhitelistRegistry.sol)
The RouterWhitelistRegistry is a registry of whitelisted routers. It is responsible for keeping track of the routers that have been whitelisted by Gnosis Safe Owners. The owner can add or remove routers from the registry at any time. Callers cannot whitelist routers on behalf of others.

## Available Routers

> Reminder: Assets must be whitelisted in the TokenWhitelistRegistry in order to be traded by the routers.

### [UniswapV3PositionRouter](./src/routers/UniswapV3PositionRouter.sol)
The `UniswapV3PositionRouter` is a router that allows users to create and manage Uniswap V3 positions.

---

### [UniswapV3SwapRouter](./src/routers/UniswapV3SwapRouter.sol)
The `UniswapV3SwapRouter` is a router that allows users to swap tokens through Uniswap V3.

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
