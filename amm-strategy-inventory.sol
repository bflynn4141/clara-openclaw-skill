// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AMMStrategyBase} from "./AMMStrategyBase.sol";
import {IAMMStrategy, TradeInfo} from "./IAMMStrategy.sol";

/// @title Inventory-Aware Market Maker Strategy
/// @notice Classic market making approach - skew fees based on inventory position
/// @dev Logic:
///   1. Track target inventory ratio (50% X, 50% Y by value)
///   2. When overweight X: lower ask fee (sell X), raise bid fee (buy X)
///   3. When overweight Y: raise ask fee, lower bid fee
///   4. Base fee adjusts based on recent trade flow
contract Strategy is AMMStrategyBase {
    
    // Slot indices
    uint256 constant SLOT_INITIAL_X = 0;       // Initial X reserves
    uint256 constant SLOT_INITIAL_Y = 1;       // Initial Y reserves
    uint256 constant SLOT_TARGET_VALUE = 2;    // Target value per side
    uint256 constant SLOT_RECENT_FLOW = 3;     // Recent buy/sell pressure
    uint256 constant SLOT_BASE_FEE = 4;        // Current base fee
    uint256 constant SLOT_LAST_PRICE = 5;      // Last estimated price
    
    // Parameters
    uint256 constant INITIAL_FEE = 35 * BPS;
    uint256 constant MIN_FEE = 15 * BPS;
    uint256 constant MAX_FEE = 70 * BPS;
    uint256 constant MAX_SKEW = 20 * BPS;      // Max asymmetric adjustment
    uint256 constant FLOW_DECAY = WAD * 90 / 100; // 10% decay per trade
    
    function afterInitialize(uint256 initialX, uint256 initialY) external override returns (uint256 bidFee, uint256 askFee) {
        slots[SLOT_INITIAL_X] = initialX;
        slots[SLOT_INITIAL_Y] = initialY;
        // Target value = 50% of initial total value
        // Price starts at 100 (Y per X), so value X = X * 100
        slots[SLOT_TARGET_VALUE] = initialX * 100; // ~10,000
        slots[SLOT_RECENT_FLOW] = 0;
        slots[SLOT_BASE_FEE] = INITIAL_FEE;
        slots[SLOT_LAST_PRICE] = 100 * WAD; // Initial price
        
        return (INITIAL_FEE, INITIAL_FEE);
    }

    function afterSwap(TradeInfo calldata trade) external override returns (uint256 bidFee, uint256 askFee) {
        // Load state
        uint256 initialX = slots[SLOT_INITIAL_X];
        uint256 targetValue = slots[SLOT_TARGET_VALUE];
        uint256 recentFlow = slots[SLOT_RECENT_FLOW];
        uint256 baseFee = slots[SLOT_BASE_FEE];
        
        // Estimate current price from reserves
        uint256 currentPrice = wdiv(trade.reserveY, trade.reserveX);
        slots[SLOT_LAST_PRICE] = currentPrice;
        
        // Calculate current inventory values
        uint256 valueX = wmul(trade.reserveX, currentPrice);
        uint256 valueY = trade.reserveY;
        
        // Calculate deviation from target
        int256 deviationX = int256(valueX) - int256(targetValue);
        int256 deviationY = int256(valueY) - int256(targetValue);
        
        // Calculate skew factor (-1 to +1)
        // Positive = overweight X, Negative = overweight Y
        int256 totalValue = int256(valueX + valueY);
        int256 skew = 0;
        if (totalValue > 0) {
            skew = (deviationX * int256(WAD)) / (totalValue / 2);
        }
        
        // Adjust base fee based on trade size (larger trades = more competition)
        uint256 tradeValue = trade.isBuy ? trade.amountY : wmul(trade.amountX, currentPrice);
        uint256 reserveValue = valueX + valueY;
        uint256 tradeRatio = wdiv(tradeValue, reserveValue);
        
        if (tradeRatio > WAD / 20) { // >5% trade
            // Large trade - likely competitive period, lower fees
            baseFee = baseFee > 5 * BPS ? baseFee - 5 * BPS : baseFee;
        } else if (tradeRatio < WAD / 200) { // <0.5% trade
            // Small trade - less competition, can raise fees slightly
            baseFee = baseFee + BPS;
        }
        
        // Clamp base fee
        if (baseFee > MAX_FEE) baseFee = MAX_FEE;
        if (baseFee < MIN_FEE) baseFee = MIN_FEE;
        
        // Calculate asymmetric adjustments based on inventory skew
        // Positive skew = overweight X = want to sell X more (lower ask)
        int256 askAdjustment = 0;
        int256 bidAdjustment = 0;
        
        if (skew > int256(WAD / 20)) { // >5% overweight X
            // Lower ask (sell X) fee, raise bid (buy X) fee
            askAdjustment = -int256(MAX_SKEW / 2);
            bidAdjustment = int256(MAX_SKEW / 2);
        } else if (skew < -int256(WAD / 20)) { // >5% overweight Y
            // Raise ask fee, lower bid fee
            askAdjustment = int256(MAX_SKEW / 2);
            bidAdjustment = -int256(MAX_SKEW / 2);
        }
        
        // Apply flow-based adjustments (momentum)
        // Recent buy pressure (isBuy = AMM bought X = trader sold X)
        // More trader sells = we want to lower ask to sell X faster
        if (trade.isBuy) {
            recentFlow = wmul(recentFlow, FLOW_DECAY) + WAD / 10; // Shift toward sell pressure
        } else {
            recentFlow = wmul(recentFlow, FLOW_DECAY) - int256(WAD / 10); // Shift toward buy pressure
        }
        
        // Flow adjustment affects bid/ask asymmetrically
        // Positive recentFlow = traders have been selling X to us = we're heavy X
        // So we want to encourage selling X (lower ask)
        int256 flowAdjustment = recentFlow / 10; // ±10% max
        askAdjustment = askAdjustment - flowAdjustment;
        bidAdjustment = bidAdjustment + flowAdjustment;
        
        // Calculate final fees
        int256 finalAsk = int256(baseFee) + askAdjustment;
        int256 finalBid = int256(baseFee) + bidAdjustment;
        
        // Clamp to valid range
        if (finalAsk < int256(MIN_FEE)) finalAsk = int256(MIN_FEE);
        if (finalAsk > int256(MAX_FEE)) finalAsk = int256(MAX_FEE);
        if (finalBid < int256(MIN_FEE)) finalBid = int256(MIN_FEE);
        if (finalBid > int256(MAX_FEE)) finalBid = int256(MAX_FEE);
        
        // Save state
        slots[SLOT_BASE_FEE] = baseFee;
        slots[SLOT_RECENT_FLOW] = recentFlow;
        
        return (uint256(finalBid), uint256(finalAsk));
    }

    function getName() external pure override returns (string memory) {
        return "InventoryAware_v1";
    }
}
