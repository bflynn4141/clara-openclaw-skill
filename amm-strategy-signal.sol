// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AMMStrategyBase} from "./AMMStrategyBase.sol";
import {IAMMStrategy, TradeInfo} from "./IAMMStrategy.sol";

/// @title Signal-Based Fee Jumping Strategy
/// @notice Detects arbitrage signals and rapidly adjusts fees
/// @dev State Machine:
///   CALM (0): Normal operation, 30-40 bps fees
///   ALERT (1): Recent large trade detected, 25 bps
///   ARB_DETECTED (2): Multiple signals - drop to minimum (15 bps)
///   RECOVERY (3): Gradually ramp back to normal
contract Strategy is AMMStrategyBase {
    
    // State machine states
    uint256 constant STATE_CALM = 0;
    uint256 constant STATE_ALERT = 1;
    uint256 constant STATE_ARB_DETECTED = 2;
    uint256 constant STATE_RECOVERY = 3;
    
    // Slot indices
    uint256 constant SLOT_STATE = 0;              // Current state
    uint256 constant SLOT_STATE_COUNTER = 1;      // Steps in current state
    uint256 constant SLOT_LAST_TRADE_DIR = 2;     // Direction of last trade
    uint256 constant SLOT_LAST_TRADE_SIZE = 3;    // Size of last trade
    uint256 constant SLOT_CONSEC_SAME_DIR = 4;    // Consecutive same-direction trades
    uint256 constant SLOT_CURRENT_FEE = 5;        // Current fee level
    uint256 constant SLOT_VOLATILITY_SCORE = 6;   // Running volatility estimate
    
    // Fee levels by state
    uint256 constant FEE_CALM = 35 * BPS;
    uint256 constant FEE_ALERT = 25 * BPS;
    uint256 constant FEE_ARB = 15 * BPS;          // Minimum competitive fee
    uint256 constant FEE_RECOVERY_START = 20 * BPS;
    
    // Thresholds
    uint256 constant LARGE_TRADE_THRESHOLD = WAD / 12;  // ~8.3% of reserves
    uint256 constant MEDIUM_TRADE_THRESHOLD = WAD / 50; // 2% of reserves
    uint256 constant MAX_CONSEC_ALERT = 3;              // Steps before dropping to ARB mode
    uint256 constant RECOVERY_STEPS = 5;                // Steps to ramp up
    
    function afterInitialize(uint256, uint256) external override returns (uint256 bidFee, uint256 askFee) {
        slots[SLOT_STATE] = STATE_CALM;
        slots[SLOT_STATE_COUNTER] = 0;
        slots[SLOT_LAST_TRADE_DIR] = 0; // 0 = none, 1 = buy, 2 = sell
        slots[SLOT_LAST_TRADE_SIZE] = 0;
        slots[SLOT_CONSEC_SAME_DIR] = 0;
        slots[SLOT_CURRENT_FEE] = FEE_CALM;
        slots[SLOT_VOLATILITY_SCORE] = 0;
        
        return (FEE_CALM, FEE_CALM);
    }

    function afterSwap(TradeInfo calldata trade) external override returns (uint256 bidFee, uint256 askFee) {
        uint256 state = slots[SLOT_STATE];
        uint256 counter = slots[SLOT_STATE_COUNTER];
        uint256 lastDir = slots[SLOT_LAST_TRADE_DIR];
        uint256 consecSameDir = slots[SLOT_CONSEC_SAME_DIR];
        uint256 currentFee = slots[SLOT_CURRENT_FEE];
        uint256 volScore = slots[SLOT_VOLATILITY_SCORE];
        
        // Calculate trade size ratio
        uint256 tradeRatio = wdiv(trade.amountY, trade.reserveY);
        uint256 currentDir = trade.isBuy ? 1 : 2;
        
        // Update volatility score
        if (tradeRatio > MEDIUM_TRADE_THRESHOLD) {
            volScore = volScore + WAD / 10; // Increase on medium+ trades
        } else {
            volScore = wmul(volScore, WAD * 95 / 100); // Decay 5%
        }
        if (volScore > WAD) volScore = WAD;
        
        // Track consecutive same-direction trades
        if (currentDir == lastDir && tradeRatio > WAD / 100) {
            consecSameDir = consecSameDir + 1;
        } else {
            consecSameDir = 0;
        }
        
        // State machine transitions
        bool isLargeTrade = tradeRatio > LARGE_TRADE_THRESHOLD;
        bool isConsecutiveLarge = consecSameDir >= 2 && tradeRatio > MEDIUM_TRADE_THRESHOLD;
        
        if (state == STATE_CALM) {
            if (isLargeTrade || isConsecutiveLarge) {
                // Jump to ALERT on large trade or consecutive pattern
                state = STATE_ALERT;
                counter = 0;
                currentFee = FEE_ALERT;
            } else if (volScore > WAD / 2) {
                // Moderate volatility - slight reduction
                currentFee = FEE_ALERT + 5 * BPS;
            } else {
                // Stay calm but adjust slightly based on trade size
                if (tradeRatio > WAD / 20) {
                    currentFee = FEE_CALM - 5 * BPS; // Competitive on medium trades
                } else {
                    currentFee = FEE_CALM;
                }
            }
        }
        else if (state == STATE_ALERT) {
            counter = counter + 1;
            
            if (isConsecutiveLarge || counter >= MAX_CONSEC_ALERT) {
                // Multiple signals - drop to minimum
                state = STATE_ARB_DETECTED;
                counter = 0;
                currentFee = FEE_ARB;
            } else if (!isLargeTrade && counter >= 2) {
                // Calm down if no more large trades
                state = STATE_CALM;
                counter = 0;
                currentFee = FEE_CALM;
            } else {
                // Stay alert
                currentFee = FEE_ALERT;
            }
        }
        else if (state == STATE_ARB_DETECTED) {
            counter = counter + 1;
            
            if (counter >= 2) {
                // Start recovery after 2 steps of low fees
                state = STATE_RECOVERY;
                counter = 0;
                currentFee = FEE_RECOVERY_START;
            } else {
                currentFee = FEE_ARB;
            }
        }
        else if (state == STATE_RECOVERY) {
            counter = counter + 1;
            
            // Gradually ramp up fees
            uint256 feeStep = (FEE_CALM - FEE_RECOVERY_START) / RECOVERY_STEPS;
            currentFee = FEE_RECOVERY_START + (feeStep * counter);
            
            if (counter >= RECOVERY_STEPS || currentFee >= FEE_CALM) {
                // Back to calm
                state = STATE_CALM;
                counter = 0;
                currentFee = FEE_CALM;
            }
            
            // Reset to alert if another large trade comes
            if (isLargeTrade) {
                state = STATE_ALERT;
                counter = 0;
                currentFee = FEE_ALERT;
            }
        }
        
        // Asymmetric adjustment based on trade direction
        // After a buy (AMM bought X), we're more likely to get more sells
        // So adjust fees to encourage rebalancing
        uint256 askFee = currentFee;
        uint256 bidFee = currentFee;
        
        if (state == STATE_CALM) {
            // Minor asymmetric adjustments in calm state
            if (consecSameDir >= 2) {
                if (trade.isBuy) {
                    // Consecutive buys - lower ask fee to sell X
                    askFee = currentFee - 5 * BPS;
                    bidFee = currentFee + 5 * BPS;
                } else {
                    // Consecutive sells - lower bid fee to buy X
                    askFee = currentFee + 5 * BPS;
                    bidFee = currentFee - 5 * BPS;
                }
            }
        }
        
        // Clamp fees
        if (askFee < FEE_ARB) askFee = FEE_ARB;
        if (bidFee < FEE_ARB) bidFee = FEE_ARB;
        if (askFee > 100 * BPS) askFee = 100 * BPS;
        if (bidFee > 100 * BPS) bidFee = 100 * BPS;
        
        // Save state
        slots[SLOT_STATE] = state;
        slots[SLOT_STATE_COUNTER] = counter;
        slots[SLOT_LAST_TRADE_DIR] = currentDir;
        slots[SLOT_LAST_TRADE_SIZE] = tradeRatio;
        slots[SLOT_CONSEC_SAME_DIR] = consecSameDir;
        slots[SLOT_CURRENT_FEE] = currentFee;
        slots[SLOT_VOLATILITY_SCORE] = volScore;
        
        return (bidFee, askFee);
    }

    function getName() external pure override returns (string memory) {
        return "SignalBased_v1";
    }
}
