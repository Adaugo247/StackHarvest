# 🌾 StackHarvest: Auto-Compounding DeFi Vaults on Stacks

**StackHarvest** is a decentralized yield optimizer built on the Stacks blockchain. It enables users to automatically compound their crypto earnings via vault-based strategies — optimized for performance, risk control, and transparency.

---

## 🚀 Features

- 🔁 **Auto-Compounding Vaults**  
  Automatically reinvests yield back into strategies to maximize investor returns over time.

- 📦 **Strategy-Based Vaults**  
  Each vault has configurable APY targets, performance multipliers, and allocation caps.

- ⚖️ **Risk & Access Management**  
  Vault-level risk tiers, emergency shutdowns, and protocol role-based authorization.

- 📊 **Performance Tracking**  
  Epoch-based yield reporting and APY estimations per strategy.

- 🧠 **Stacked Intelligence**  
  Compound rewards at both the strategy and individual investor level with reward multipliers.

---

## 🔧 Contract Overview

### 🔑 Key Components

- `PROTOCOL_ADMIN`: Admin principal that manages critical protocol settings.
- `yield-strategies`: Registry of active investment strategies.
- `investor-vault-positions`: Tracks individual user deposits, shares, and yield.
- `protocol-performance-fee`: Percentage fee on auto-compounded earnings (default 2%).

---

## 📥 How Deposits Work

Users deposit STX (or a vault-supported asset) into a specific strategy. In return, they receive vault shares that represent their proportional stake.

```clarity
(deposit-to-strategy u1 u50000)
````

* Validates strategy status
* Calculates proportional vault shares
* Updates user and protocol balances

---

## 📤 How Withdrawals Work

Users can withdraw based on the number of shares they hold in the vault. A cooldown period prevents rapid drain attacks.

```clarity
(withdraw-from-strategy u1 u25000)
```

* Checks cooldown timer
* Calculates proportional withdrawal amount
* Updates strategy totals and user position

---

## 🔁 Auto-Compounding Engine

```clarity
(trigger-auto-compound u1)
```

* Callable by any user or automated bot
* Calculates rewards using APY and blocks passed
* Deducts performance fee and reinvests the rest

```clarity
(compound-investor-position u1)
```

* Allows individual users to trigger personal yield compounding
* Tracks blocks since last compound per investor

---

## ⚙️ Admin & Governance

```clarity
(authorize-strategy-manager 'SP...manager)
(update-performance-fee u300)
(emergency-shutdown-protocol)
(reactivate-protocol)
```

* Admin can assign trusted strategy managers
* Fee adjustable up to 10% max
* Emergency switch halts deposits/withdrawals

---

## 📈 Read-Only Functions

* `get-investor-position`: View individual strategy data
* `calculate-pending-yield`: Estimate yield yet to be claimed
* `estimate-strategy-apy`: Predict actual APY based on past performance
* `get-treasury-allocation`: Check fees earned by the protocol

---

## 📊 Protocol Metrics

```clarity
(get-protocol-metrics)
```

Returns:

* `total-value-locked`
* `protocol-performance-fee`
* `current-epoch`
* `strategy-counter`
* `auto-compound-frequency`

---

## 🧪 Getting Started

1. Deploy the contract on Stacks testnet or mainnet.
2. Assign at least one authorized strategy manager.
3. Use `create-yield-strategy` to configure APY, risk, and allocation.
4. Let users deposit and earn automatically.

---

## 🧠 Example Strategy Creation

```clarity
(create-yield-strategy 
  "STX Lending Vault" ;; name
  u2500               ;; 25% APY
  u3                  ;; Risk level 3
  u1000000000         ;; 1,000,000 STX cap
  u200                ;; 2x performance multiplier
)
---

## 🙌 Built For

The Stacks DeFi community — to empower **hands-free, high-efficiency crypto earning**.

> “Plant your STX. Harvest more. Automatically.”
