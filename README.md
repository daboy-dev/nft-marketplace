# NFT Marketplace

[![CI](https://github.com/daboy-dev/nft-marketplace/actions/workflows/test.yml/badge.svg)](https://github.com/daboy-dev/nft-marketplace/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A minimal, non-custodial marketplace for ERC-721 tokens, written in Solidity and tested with [Foundry](https://book.getfoundry.sh/).

Sellers list any ERC-721 token at a fixed price in ETH, buyers purchase it in a single transaction, and the marketplace owner collects a configurable fee on each sale.

## Features

- **List / unlist**: the token owner lists an NFT at a fixed price and can cancel the listing at any time.
- **Buy**: the buyer sends the exact price in ETH; the NFT and the payment are swapped atomically.
- **Non-custodial**: the marketplace never holds NFTs. Sellers keep them until a sale happens, and must approve the marketplace for the purchase to succeed.
- **Marketplace fee**: 0.5 % by default, charged to the seller (the buyer always pays exactly the listing price). The owner can change it up to a hard cap of 5 %.
- **Pull-based fee withdrawal**: fees accumulate in the contract and the owner withdraws them on demand, so a failing owner account can never block a sale.

## How it works

```
Seller                      Marketplace                     Buyer
  │  approve(marketplace)       │                             │
  │────────────────────────────▶│ (on the ERC-721 contract)   │
  │  listNFT(nft, id, price)    │                             │
  │────────────────────────────▶│                             │
  │                             │   buyNFT(nft, id) + price   │
  │                             │◀────────────────────────────│
  │   price - fee (ETH)         │   NFT (safeTransferFrom)    │
  │◀────────────────────────────│────────────────────────────▶│
                          fee stays in the contract
                          until the owner withdraws it
```

## Contract API

| Function | Access | Description |
|---|---|---|
| `listNFT(nft, tokenId, price)` | Token owner | Lists an NFT. Reverts on zero price or if the caller is not the owner. Relisting overwrites the previous listing. |
| `unlistNFT(nft, tokenId)` | Seller | Cancels a listing. |
| `buyNFT(nft, tokenId)` | Anyone (payable) | Buys a listed NFT. `msg.value` must equal the price. |
| `setFee(newFeeBps)` | Owner | Updates the fee in basis points (max `MAX_FEE_BPS` = 500). |
| `withdrawFees()` | Owner | Withdraws all accumulated fees. |
| `listings(nft, tokenId)` | View | Returns the `Listing` for a token. An empty listing means "not listed". |
| `feeBps()` / `accumulatedFees()` | View | Current fee and fees pending withdrawal. |

Events: `NFTListed`, `NFTUnlisted`, `NFTSold`, `FeeUpdated`, `FeesWithdrawn`.
Errors are custom errors prefixed with `NFTMarketplace__`. All public functions are documented with NatSpec.

## Design decisions and security

- **Checks-effects-interactions**: in `buyNFT` the listing is deleted and the fee accounted for before any external call.
- **Reentrancy protection**: `buyNFT` and `withdrawFees` use OpenZeppelin's `ReentrancyGuard`.
- **Fees in basis points**: `fee = price * feeBps / 10_000`, multiplying before dividing to keep precision. Prices below 200 wei produce a zero fee at the default rate because of integer division.
- **Capped owner power**: the owner can't raise the fee above `MAX_FEE_BPS`.
- **Custom errors** instead of revert strings, to save gas.

### Known limitations

- Approval is not checked when listing, only when buying: a listing without approval can't be bought.
- Listings are not invalidated if the seller transfers the NFT elsewhere; the purchase simply reverts.
- A fee change applies to all sales made after it, including already active listings.
- ETH only; there is no support for ERC-20 payments or ERC-2981 royalties.

## Getting started

Requirements: [Foundry](https://book.getfoundry.sh/getting-started/installation).

```shell
git clone --recurse-submodules https://github.com/daboy-dev/nft-marketplace.git
cd nft-marketplace
forge build
```

If you already cloned without submodules: `git submodule update --init --recursive`.

### Test

```shell
forge test           # run the test suite
forge test -vvv      # with traces for failing tests
forge coverage       # coverage report
```

The suite covers listing, unlisting, buying, fee configuration, fee distribution (including a fuzz test) and fee withdrawal, checking both success paths and revert cases with exact custom errors and emitted events.

### Format and gas

```shell
forge fmt
forge snapshot
```

### Deploy

The contract has no constructor arguments; the deployer becomes the owner.

```shell
forge create src/NFTMarketplace.sol:NFTMarketplace --rpc-url <rpc_url> --account <keystore_account>
```

Use an encrypted keystore (`cast wallet import`) instead of passing a private key on the command line.

## Project structure

```
src/NFTMarketplace.sol      Marketplace contract
test/NFTMarketplace.t.sol   Unit and fuzz tests
test/mocks/MockNFT.sol      Minimal ERC-721 used in tests
.github/workflows/test.yml  CI: format check, build and tests
```

## Built with

- [Solidity](https://soliditylang.org/) ^0.8.34
- [Foundry](https://book.getfoundry.sh/) (forge, forge-std)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) (`Ownable`, `ReentrancyGuard`, `ERC721`)

## License

[MIT](LICENSE)
