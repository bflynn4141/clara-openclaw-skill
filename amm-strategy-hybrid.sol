// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AMMStrategyBase} from "./AMMStrategyBase.sol";
import {IAMMStrategy, TradeInfo} from "./IAMMStrategy.sol";

/// @title Hybrid Optimal Market Maker (HOMM) Strategy
/// @notice Combines volatility estimation, inventory management, and adverse selection detection
/// @dev Key insights from market microstructure theory:
///   1. Large trades (>5% reserves) are likely informed (arbitrage)
///   2. Trade flow autocorrelation signals informed vs uninformed flow
///   3. Inventory skew should affect pricing to manage risk
///   4. Fees should respond to market conditions (volatility, competition)
contract Strategy is AMMStrategyBase {
    
    // ===== Slot Layout =====
    // State tracking
    uint256 constant SLOT_BASE_FEE = 0;           // Current base fee level
    uint256 constant SLOT_STATE = 1;              // State machine state
    uint256 constant SLOT_STATE_COUNTER = 2;      // Steps in current state
    
    // Market microstructure
    uint256 constant SLOT_LAST_TRADE_DIR = 3;     // 0=none, 1=buy, 2=sell
    uint256 constant SLOT_CONSEC_SAME_DIR = 4;    // Consecutive same-direction trades
    uint256 constant SLOT_VOLATILITY_EST = 5;     // EWMA volatility estimate
    uint256 constant SLOT_FLOW_MOMENTUM = 6;      // Buy/sell pressure (-WAD to +WAD)
    
    // Inventory management
    uint256 constant SLOT_INITIAL_X = 7;          // Starting X reserves
    uint256 constant SLOT_INITIAL_Y = 8;          // Starting Y reserves
    uint256 constant SLOT_TARGET_VALUE = 9;       // Target value per asset
    
    // Performance tracking
    uint256 constant SLOT_LAST_RESERVE_X = 10;    // For PnL estimation
    uint256 constant SLOT_LAST_RESERVE_Y = 11;
    uint256 constant SLOT_CUM_EDGE_EST = 12;      // Cumulative edge estimate
    
    // ===== Constants =====
    // State machine states
    uint256 constant STATE_NORMAL = 0;
    uint256 constant STATE_HIGH_VOL = 1;          // High volatility detected
    uint256 constant STATE_ARB_PATTERN = 2;       // Arbitrage pattern detected
    uint256 constant STATE_POST_ARB = 3;          // Recovering after arb
    
    // Fee parameters (in bps)
    uint256 constant FEE_NORMAL = 35 * BPS;
    uint256 constant FEE_HIGH_VOL = 45 * BPS;     // Charge more in vol
    uint256 constant FEE_ARB_RESPONSE = 18 * BPS; // Lower when arb detected
    uint256 constant FEE_POST_ARB = 28 * BPS;     // Slightly below normal
    uint256 constant FEE_MIN = 12 * BPS;
    uint256 constant FEE_MAX = 80 * BPS;
    
    // Thresholds
    uint256 constant LARGE_TRADE_THRESHOLD = WAD / 20;   // 5% of reserves
    uint256 constant MEDIUM_TRADE_THRESHOLD = WAD / 100; // 1% of reserves
    uint256 constant VOLATILITY_DECAY = WAD * 92 / 100;  // 8% decay per step
    uint256 constant FLOW_DECAY = WAD * 85 / 100;        // 15% decay
    uint256 constant MAX_INVENTORY_SKEW = 15 * BPS;      // Max asymmetric adjustment
    
    function afterInitialize(uint256 initialX, uint256 initialY) external override returns (uint256 bidFee, uint256 askFee) {
        // Initialize state
        slots[SLOT_BASE_FEE] = FEE_NORMAL;
        slots[SLOT_STATE] = STATE_NORMAL;
        slots[SLOT_STATE_COUNTER] = 0;
        
        // Market microstructure
        slots[SLOT_LAST_TRADE_DIR] = 0;
        slots[SLOT_CONSEC_SAME_DIR] = 0;
        slots[SLOT_VOLATILITY_EST] = 30 * BPS; // Start with moderate vol assumption
        slots[SLOT_FLOW_MOMENTUM] = 0;
        
        // Inventory
        slots[SLOT_INITIAL_X] = initialX;
        slots[SLOT_INITIAL_Y] = initialY;
        slots[SLOT_TARGET_VALUE] = initialX * 100; // Price ~100
        
        // Performance
        slots[SLOT_LAST_RESERVE_X] = initialX;
        slots[SLOT_LAST_RESERVE_Y] = initialY;
        slots[SLOT_CUM_EDGE_EST] = 0;
        
        return (FEE_NORMAL, FEE_NORMAL);
    }

    function afterSwap(TradeInfo calldata trade) external override returns (uint256 bidFee, uint256 askFee) {
        // ===== Load State =====
        uint256 baseFee = slots[SLOT_BASE_FEE];
        uint256 state = slots[SLOT_STATE];
        uint256 stateCounter = slots[SLOT_STATE_COUNTER];
        uint256 lastDir = slots[SLOT_LAST_TRADE_DIR];
        uint256 consecSameDir = slots[SLOT_CONSEC_SAME_DIR];
        uint256 volEst = slots[SLOT_VOLATILITY_EST];
        int256 flowMomentum = int256(slots[SLOT_FLOW_MOMENTUM]);
        
        // ===== Calculate Trade Characteristics =====
        uint256 tradeRatio = wdiv(trade.amountY, trade.reserveY);
        uint256 currentDir = trade.isBuy ? 1 : 2;
        bool isLargeTrade = tradeRatio > LARGE_TRADE_THRESHOLD;
        bool isMediumTrade = tradeRatio > MEDIUM_TRADE_THRESHOLD;
        
        // ===== Update Volatility Estimate (EWMA) =====
        // Large trades increase vol estimate; small trades decay it
        uint256 tradeImpact = tradeRatio > WAD / 50 ? tradeRatio * 5 : tradeRatio;
        volEst = wmul(volEst, VOLATILITY_DECAY) + tradeImpact;
        if (volEst > WAD) volEst = WAD;
        if (volEst < 5 * BPS) volEst = 5 * BPS;
        
        // ===== Update Flow Momentum =====
        // Track buy/sell pressure: positive = more buys (traders selling X)
        int256 flowDelta = trade.isBuy ? int256(WAD / 20) : -int256(WAD / 20);
        flowMomentum = (flowMomentum * int256(FLOW_DECAY)) / int256(WAD) + flowDelta;
        if (flowMomentum > int256(WAD)) flowMomentum = int256(WAD);
        if (flowMomentum < -int256(WAD)) flowMomentum = -int256(WAD);
        
        // ===== Track Consecutive Same-Direction Trades =====
        if (currentDir == lastDir && isMediumTrade) {
            consecSameDir = consecSameDir + 1;
        } else if (!isMediumTrade) {
            // Small trades don't break streak but don't extend it either
        } else {
            consecSameDir = 1;
        }
        if (consecSameDir > 10) consecSameDir = 10;
        
        // ===== State Machine Transitions =====
        bool isArbPattern = (consecSameDir >= 3 && isMediumTrade) || 
                           (isLargeTrade && consecSameDir >= 2);
        bool isHighVol = volEst > 50 * BPS;
        
        if (state == STATE_NORMAL) {
            if (isArbPattern) {
                state = STATE_ARB_PATTERN;
                stateCounter = 0;
            } else if (isHighVol) {
                state = STATE_HIGH_VOL;
                stateCounter = 0;
            }
        } 
        else if (state == STATE_HIGH_VOL) {
            stateCounter = stateCounter + 1;
            if (isArbPattern) {
                state = STATE_ARB_PATTERN;
                stateCounter = 0;
            } else if (!isHighVol && stateCounter >= 3) {
                state = STATE_NORMAL;
                stateCounter = 0;
            }
        }
        else if (state == STATE_ARB_PATTERN) {
            stateCounter = stateCounter + 1;
            if (stateCounter >= 2) {
                state = STATE_POST_ARB;
                stateCounter = 0;
            }
        }
        else if (state == STATE_POST_ARB) {
            stateCounter = stateCounter + 1;
            if (isArbPattern) {
                state = STATE_ARB_PATTERN;
                stateCounter = 0;
            } else if (stateCounter >= 4) {
                state = STATE_NORMAL;
                stateCounter = 0;
            }
        }
        
        // ===== Calculate Base Fee Based on State =====
        if (state == STATE_NORMAL) {
            // In normal state, adjust based on volatility
            if (volEst > 40 * BPS) {
                baseFee = FEE_NORMAL + 5 * BPS;
            } else if (volEst < 15 * BPS) {
                baseFee = FEE_NORMAL - 5 * BPS;
            } else {
                baseFee = FEE_NORMAL;
            }
        } 
        else if (state == STATE_HIGH_VOL) {
            baseFee = FEE_HIGH_VOL;
        }
        else if (state == STATE_ARB_PATTERN) {
            baseFee = FEE_ARB_RESPONSE;
        }
        else if (state == STATE_POST_ARB) {
            // Gradual ramp from post-arb to normal
            uint256 rampProgress = (stateCounter * BPS * 2);
            baseFee = FEE_POST_ARB + rampProgress;
            if (baseFee > FEE_NORMAL) baseFee = FEE_NORMAL;
        }
        
        // ===== Calculate Inventory Skew =====
        // Estimate current price and inventory values
        uint256 currentPrice = wdiv(trade.reserveY, trade.reserveX);
        uint256 valueX = wmul(trade.reserveX, currentPrice);
        uint256 valueY = trade.reserveY;
        uint256 totalValue = valueX + valueY;
        
        // Target is 50/50 by value
        int256 inventorySkew; // Positive = overweight X, Negative = overweight Y
        if (totalValue > 0) {
            uint256 targetValue = totalValue / 2;
            inventorySkew = (int256(valueX) - int256(targetValue)) * int256(WAD) / int256(targetValue);
        }
        
        // ===== Calculate Asymmetric Fee Adjustments =====
        // Combine inventory skew and flow momentum for asymmetric fees
        int256 askAdjustment = 0;  // Fee when AMM sells X
        int256 bidAdjustment = 0;  // Fee when AMM buys X
        
        // Inventory-based adjustment
        // If overweight X, we want to sell X (lower ask) and discourage buying X (higher bid)
        if (inventorySkew > int256(WAD / 10)) { // >10% overweight X
            askAdjustment -= int256(MAX_INVENTORY_SKEW * 2 / 3); // Lower ask
            bidAdjustment += int256(MAX_INVENTORY_SKEW / 3);     // Raise bid
        } else if (inventorySkew < -int256(WAD / 10)) { // >10% overweight Y
            askAdjustment += int256(MAX_INVENTORY_SKEW / 3);     // Raise ask
            bidAdjustment -= int256(MAX_INVENTORY_SKEW * 2 / 3); // Lower bid
        }
        
        // Flow-based adjustment
        // Positive flowMomentum = traders have been selling X to us
        // We should make it cheaper to sell X (lower ask) and more expensive to buy X
        if (flowMomentum > int256(WAD / 5)) { // Strong sell pressure
            askAdjustment -= int256(MAX_INVENTORY_SKEW / 2);
            bidAdjustment += int256(MAX_INVENTORY_SKEW / 4);
        } else if (flowMomentum < -int256(WAD / 5)) { // Strong buy pressure
            askAdjustment += int256(MAX_INVENTORY_SKEW / 4);
            bidAdjustment -= int256(MAX_INVENTORY_SKEW / 2);
        }
        
        // Consecutive same-direction adjustment
        // If many consecutive buys, expect more buys (arb pattern)
        if (consecSameDir >= 3) {
            if (trade.isBuy) {
                // Many buys = likely arb selling X, make it cheaper to sell
                askAdjustment -= int256(5 * BPS);
            } else {
                // Many sells = likely arb buying X, make it cheaper to buy
                bidAdjustment -= int256(5 * BPS);
            }
        }
        
        // ===== Calculate Final Fees =====
        int256 finalAsk = int256(baseFee) + askAdjustment;
        int256 finalBid = int256(baseFee) + bidAdjustment;
        
        // Clamp to valid range
        if (finalAsk < int256(FEE_MIN)) finalAsk = int256(FEE_MIN);
        if (finalAsk > int256(FEE_MAX)) finalAsk = int256(FEE_MAX);
        if (finalBid < int256(FEE_MIN)) finalBid = int256(FEE_MIN);
        if (finalBid > int256(FEE_MAX)) finalBid = int256(FEE_MAX);
        
        // ===== Save State =====
        slots[SLOT_BASE_FEE] = baseFee;
        slots[SLOT_STATE] = state;
        slots[SLOT_STATE_COUNTER] = stateCounter;
        slots[SLOT_LAST_TRADE_DIR] = currentDir;
        slots[SLOT_CONSEC_SAME_DIR] = consecSameDir;
        slots[SLOT_VOLATILITY_EST] = volEst;
        slots[SLOT_FLOW_MOMENTUM] = uint256(flowMomentum);
        slots[SLOT_LAST_RESERVE_X] = trade.reserveX;
        slots[SLOT_LAST_RESERVE_Y] = trade.reserveY;
        
        return (uint256(finalBid), uint256(finalAsk));
    }

    function getName() external pure override returns (string memory) {
        return "HybridOptimal_v1";
    }
}
