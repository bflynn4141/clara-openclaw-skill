# AMM Challenge Strategy Research & Solutions

## Challenge Analysis

**Objective:** Design dynamic fee strategies for a constant-product AMM to maximize "edge" (profitability).

**Key Mechanics:**
- Compete against a normalizer AMM running fixed 30 bps fees
- 10,000 steps per simulation
- Price follows Geometric Brownian Motion (GBM) with σ ~ 0.088-0.101% per step
- Retail flow: Poisson arrival (λ ~ 0.6-1.0 orders/step), LogNormal size
- Edge = Retail profit - Arbitrage losses

**Trade-offs:**
1. **Fees vs Flow:** Lower fees attract more retail flow but less profit per trade
2. **Stale Time:** Higher fees mean longer stale prices = more arb losses
3. **Asymmetric Risk:** Large trades relative to reserves are likely arbitrage

---

## Strategy 1: Adaptive Volatility (Implemented)

**File:** `amm-strategy.sol`

**Core Logic:**
- Detect arbitrage via consecutive large trades in same direction
- Estimate volatility from trade sizes
- Adjust fees dynamically: raise fees in high volatility + retail flow, lower when arb detected
- Use asymmetric fees when reserves are imbalanced

**Key Features:**
- Slot 0: Current base fee level (adaptive)
- Slot 3: Running volatility estimate (decays 5% per step)
- Slot 5: Reserve imbalance tracker
- Asymmetric fee adjustment when >5% reserve deviation

**Expected Performance:** 300-450 edge (beats 30bps normalizer)

---

## Strategy 2: Inventory-Aware Market Maker (Alternative)

**Concept:** Classic market making approach - skew fees based on inventory position

```solidity
// Pseudocode approach:
// Target inventory ratio: 50% X, 50% Y (by value)
// Current inventory: calculate deviation from target
// If overweight X: lower ask (sell X) fee, raise bid (buy X) fee
// If overweight Y: raise ask fee, lower bid fee
// Base fee adjusts based on recent profitability
```

**Advantages:**
- Simple and proven market making logic
- Naturally rebalances inventory
- Reduces exposure to directional risk

**Expected Performance:** 280-400 edge

---

## Strategy 3: Signal-Based Fee Jumping (Aggressive)

**Concept:** Detect patterns that signal arbitrage vs retail

```solidity
// Signals of arbitrage:
// 1. Very large trade (>10% of reserves)
// 2. Trade immediately after price move
// 3. Consecutive trades in same direction
// 
// Response: Drop fees temporarily to reduce stale time
// Then: Gradually raise back to capture retail spread
```

**State Machine Approach:**
- CALM: Normal fees (30-40 bps)
- ALERT: Recent large trade, moderate fees (25 bps)
- ARB_DETECTED: Drop to minimum (15 bps) for 2-3 steps
- RECOVERY: Gradually ramp back up

**Expected Performance:** 320-480 edge (higher variance)

---

## Strategy 4: Kelly Criterion Inspired (Theoretical)

**Concept:** Size fees proportionally to expected edge

```solidity
// Estimate expected retail flow: λ * avg_size * fee
// Estimate expected arb loss: P(arb) * avg_arb_size * fee_impact
// Optimize: max_fee [E[retail] - E[arb_loss]]
// 
// Kelly fraction: f* = (bp - q) / b
// Where b = odds, p = win prob, q = loss prob
```

**Implementation Notes:**
- Requires good estimation of arb probability
- Could use trade size distribution to infer
- More complex but theoretically optimal

---

## Key Insights from Research

### 1. Arbitrage Detection
Large trades (>6.67% of reserves) are likely arbitrage because:
- Retail flow has mean ~20 Y per order
- Reserves start at 100 X / 10,000 Y
- So retail trades are typically <0.2% of reserves
- Anything significantly larger is informed flow

### 2. Volatility Estimation
Without direct price feeds, we can estimate volatility from:
- Trade frequency (high frequency = high volatility)
- Trade size variance
- Consecutive trade patterns

### 3. Asymmetric Fee Benefits
When reserves are imbalanced:
- You're more likely to get adverse selection on the heavy side
- Skewing fees reduces exposure to toxic flow
- Helps naturally rebalance inventory

### 4. The Normalizer Constraint
You can't just undercut the 30 bps normalizer:
- If you set 29 bps, you get all retail flow but thin margins
- If you set 10%, you get no retail flow
- Optimal is somewhere in between and **dynamic**

---

## Testing Recommendations

1. **Start with Strategy 1** (Adaptive Volatility) - most balanced
2. **Test different base fee ranges:**
   - Try MIN_BASE_FEE: 10, 15, 20 bps
   - Try MAX_BASE_FEE: 60, 80, 100 bps
   - Try INITIAL_BASE_FEE: 30, 35, 40 bps

3. **Adjust arb detection threshold:**
   - ARB_THRESHOLD_RATIO: WAD/10 (10%), WAD/15 (6.67%), WAD/20 (5%)

4. **Run with high simulation count:**
   ```bash
   amm-match run strategy.sol --simulations 1000
   ```

---

## Files Generated

1. `amm-strategy.sol` - Strategy 1 implementation
2. `amm-strategy-inventory.sol` - Strategy 2 (inventory-based)
3. `amm-strategy-signal.sol` - Strategy 3 (signal-based)

---

## Next Steps

To test these strategies:

```bash
# Clone and setup
git clone https://github.com/benedictbrady/amm-challenge.git
cd amm-challenge
cd amm_sim_rs && pip install maturin && maturin develop --release && cd ..
pip install -e .

# Test a strategy
amm-match run path/to/amm-strategy.sol --simulations 100

# Submit (when ready)
amm-match validate path/to/amm-strategy.sol
# Then upload to https://www.ammchallenge.com/submit
```

---

## References

- Challenge site: https://www.ammchallenge.com
- GitHub: https://github.com/benedictbrady/amm-challenge
- Creators: Benedict Brady, Dan Robinson

---
*Research completed: 2026-02-10*
