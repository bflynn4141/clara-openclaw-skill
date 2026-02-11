// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AMMStrategyBase} from "./AMMStrategyBase.sol";
import {IAMMStrategy, TradeInfo} from "./IAMMStrategy.sol";

/// @title Adaptive Volatility Strategy
/// @notice Dynamically adjusts fees based on trade patterns and estimated volatility
/// @dev Strategy: 
///   1. Detect arbitrage vs retail flow using trade size patterns
///   2. Adjust fees based on recent trade history (volatility estimation)
///   3. Use asymmetric fees when reserves are imbalanced
///   4. Decay fees toward base after periods of calm
contract Strategy is AMMStrategyBase {
    
    // Slot indices for state
    uint256 constant SLOT_BASE_FEE = 0;           // Current base fee level
    uint256 constant SLOT_LAST_TRADE_SIZE = 1;    // Previous trade size for pattern detection
    uint256 constant SLOT_CONSEC_ARB_SIGNS = 2;   // Count of same-direction large trades (arb detection)
    uint256 constant SLOT_VOLATILITY_EST = 3;     // Running volatility estimate
    uint256 constant SLOT_LAST_TIMESTAMP = 4;     // Last trade timestamp for decay
    uint256 constant SLOT_RESERVE_IMBALANCE = 5;  // Track X/Y ratio vs initial
    uint256 constant SLOT_PROFIT_MOMENTUM = 6;    // Recent edge tracking
    
    // Constants
    uint256 constant INITIAL_BASE_FEE = 35 * BPS;  // Start slightly above normalizer
    uint256 constant MIN_BASE_FEE = 15 * BPS;      // Floor to remain competitive
    uint256 constant MAX_BASE_FEE = 80 * BPS;      // Ceiling before retail flow dies
    uint256 constant ARB_THRESHOLD_RATIO = WAD / 15; // >6.67% of reserves = likely arb
    uint256 constant VOLATILITY_DECAY = WAD * 95 / 100; // 5% decay per step
    uint256 constant FEE_ADJUSTMENT_STEP = 3 * BPS; // How fast we adjust
    
    function afterInitialize(uint256 initialX, uint256 initialY) external override returns (uint256 bidFee, uint256 askFee) {
        slots[SLOT_BASE_FEE] = INITIAL_BASE_FEE;
        slots[SLOT_LAST_TRADE_SIZE] = 0;
        slots[SLOT_CONSEC_ARB_SIGNS] = 0;
        slots[SLOT_VOLATILITY_EST] = 30 * BPS; // Start with moderate volatility estimate
        slots[SLOT_LAST_TIMESTAMP] = 0;
        slots[SLOT_RESERVE_IMBALANCE] = wdiv(initialX * WAD, initialY); // Store initial X/Y ratio
        slots[SLOT_PROFIT_MOMENTUM] = 0;
        
        return (INITIAL_BASE_FEE, INITIAL_BASE_FEE);
    }

    function afterSwap(TradeInfo calldata trade) external override returns (uint256 bidFee, uint256 askFee) {
        // Load state
        uint256 baseFee = slots[SLOT_BASE_FEE];
        uint256 lastSize = slots[SLOT_LAST_TRADE_SIZE];
        uint256 consecArb = slots[SLOT_CONSEC_ARB_SIGNS];
        uint256 volEst = slots[SLOT_VOLATILITY_EST];
        uint256 lastTime = slots[SLOT_LAST_TIMESTAMP];
        uint256 initialRatio = slots[SLOT_RESERVE_IMBALANCE];
        uint256 profitMomentum = slots[SLOT_PROFIT_MOMENTUM];
        
        uint256 currentTime = trade.timestamp;
        
        // Calculate trade size relative to reserves
        uint256 tradeRatio = wdiv(trade.amountY, trade.reserveY);
        
        // Detect if this was likely arbitrage (large trade relative to reserves)
        bool isLargeTrade = tradeRatio > ARB_THRESHOLD_RATIO;
        
        // Detect trade direction pattern (same direction = more likely arb)
        bool isBuy = trade.isBuy; // true if AMM bought X (trader sold X)
        
        // Update volatility estimate: high trade ratio = high volatility period
        if (tradeRatio > WAD / 50) { // >2% of reserves
            // Large trade - increase volatility estimate
            volEst = wmul(volEst, WAD + BPS * 50) + tradeRatio / 10;
        } else {
            // Small trade - decay volatility estimate
            volEst = wmul(volEst, VOLATILITY_DECAY);
        }
        
        // Clamp volatility estimate
        if (volEst > 100 * BPS) volEst = 100 * BPS;
        if (volEst < 10 * BPS) volEst = 10 * BPS;
        
        // Track consecutive large trades in same direction (arbitrage signature)
        if (isLargeTrade) {
            if (lastSize > 0) {
                // Check if same direction as previous large trade
                bool lastWasBuy = slots[SLOT_LAST_TRADE_SIZE] > WAD / 2; // heuristic
                if (isBuy == lastWasBuy) {
                    consecArb = consecArb + 1;
                } else {
                    consecArb = 0; // Reset on direction change
                }
            }
        } else {
            // Small trades gradually reset arb counter
            if (consecArb > 0) consecArb = consecArb - 1;
        }
        
        // Adjust base fee based on market conditions
        if (consecArb >= 2) {
            // Likely arbitrage sequence - lower fees to reduce stale time
            baseFee = baseFee > FEE_ADJUSTMENT_STEP ? baseFee - FEE_ADJUSTMENT_STEP : baseFee;
        } else if (volEst > 50 * BPS && !isLargeTrade) {
            // High volatility but retail-sized trades - can raise fees
            baseFee = baseFee + FEE_ADJUSTMENT_STEP;
        } else if (volEst < 20 * BPS && tradeRatio < WAD / 100) {
            // Low volatility, small trades - competitive pricing
            baseFee = baseFee > FEE_ADJUSTMENT_STEP ? baseFee - FEE_ADJUSTMENT_STEP : baseFee;
        }
        
        // Clamp base fee to valid range
        if (baseFee > MAX_BASE_FEE) baseFee = MAX_BASE_FEE;
        if (baseFee < MIN_BASE_FEE) baseFee = MIN_BASE_FEE;
        
        // Calculate reserve imbalance for asymmetric fees
        uint256 currentRatio = wdiv(trade.reserveX * WAD, trade.reserveY);
        uint256 ratioDeviation;
        if (currentRatio > initialRatio) {
            ratioDeviation = wdiv(currentRatio - initialRatio, initialRatio);
        } else {
            ratioDeviation = wdiv(initialRatio - currentRatio, initialRatio);
        }
        
        // Asymmetric fees: charge more on the side where we're imbalanced
        uint256 askAdjustment = 0; // Fee when AMM sells X
        uint256 bidAdjustment = 0;  // Fee when AMM buys X
        
        if (ratioDeviation > WAD / 20) { // >5% deviation from initial ratio
            if (trade.reserveX > trade.reserveY) {
                // Heavy in X, want to sell X - increase ask (sell fee)
                askAdjustment = FEE_ADJUSTMENT_STEP * 2;
                bidAdjustment = 0; // Keep buy fee attractive
            } else {
                // Heavy in Y, want to buy X - increase bid (buy fee)
                bidAdjustment = FEE_ADJUSTMENT_STEP * 2;
                askAdjustment = 0; // Keep sell fee attractive
            }
        }
        
        // Calculate final fees
        uint256 finalAskFee = clampFee(baseFee + askAdjustment);
        uint256 finalBidFee = clampFee(baseFee + bidAdjustment);
        
        // Save state
        slots[SLOT_BASE_FEE] = baseFee;
        slots[SLOT_LAST_TRADE_SIZE] = isBuy ? WAD : 0; // Simple direction marker
        slots[SLOT_CONSEC_ARB_SIGNS] = consecArb;
        slots[SLOT_VOLATILITY_EST] = volEst;
        slots[SLOT_LAST_TIMESTAMP] = currentTime;
        slots[SLOT_PROFIT_MOMENTUM] = profitMomentum;
        
        // Return asymmetric fees
        return (finalBidFee, finalAskFee);
    }

    function getName() external pure override returns (string memory) {
        return "AdaptiveVolatility_v1";
    }
}
