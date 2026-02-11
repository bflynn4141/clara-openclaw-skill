// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AMMStrategyBase} from "./AMMStrategyBase.sol";
import {IAMMStrategy, TradeInfo} from "./IAMMStrategy.sol";

/// @title Microstructure-Aware Strategy
/// @notice Based on market microstructure theory:
///   - Trade size correlates with information content
///   - Time between trades contains information
///   - Order flow toxicity can be estimated from patterns
/// @dev This strategy focuses on detecting informed vs uninformed flow
contract Strategy is AMMStrategyBase {
    
    // Slots
    uint256 constant SLOT_BASE_FEE = 0;
    uint256 constant SLOT_TRADE_COUNT = 1;
    uint256 constant SLOT_LAST_TIMESTAMP = 2;
    uint256 constant SLOT_CUM_TRADE_SIZE = 3;
    uint256 constant SLOT_SQUARED_SIZE = 4;  // For variance estimation
    uint256 constant SLOT_PRICE_EST = 5;     // Implicit price estimate
    uint256 constant SLOT_INVENTORY_X = 6;
    uint256 constant SLOT_INVENTORY_Y = 7;
    
    // Parameters
    uint256 constant INITIAL_FEE = 32 * BPS;
    uint256 constant MIN_FEE = 10 * BPS;
    uint256 constant MAX_FEE = 90 * BPS;
    
    function afterInitialize(uint256 initialX, uint256 initialY) external override returns (uint256 bidFee, uint256 askFee) {
        slots[SLOT_BASE_FEE] = INITIAL_FEE;
        slots[SLOT_TRADE_COUNT] = 0;
        slots[SLOT_LAST_TIMESTAMP] = 0;
        slots[SLOT_CUM_TRADE_SIZE] = 0;
        slots[SLOT_SQUARED_SIZE] = 0;
        slots[SLOT_PRICE_EST] = 100 * WAD; // Initial price estimate
        slots[SLOT_INVENTORY_X] = initialX;
        slots[SLOT_INVENTORY_Y] = initialY;
        
        return (INITIAL_FEE, INITIAL_FEE);
    }

    function afterSwap(TradeInfo calldata trade) external override returns (uint256 bidFee, uint256 askFee) {
        uint256 baseFee = slots[SLOT_BASE_FEE];
        uint256 tradeCount = slots[SLOT_TRADE_COUNT];
        uint256 cumSize = slots[SLOT_CUM_TRADE_SIZE];
        uint256 squaredSize = slots[SLOT_SQUARED_SIZE];
        uint256 priceEst = slots[SLOT_PRICE_EST];
        
        // Calculate trade metrics
        uint256 tradeRatio = wdiv(trade.amountY, trade.reserveY);
        uint256 tradeValue = trade.amountY;
        
        // Update statistics with decay
        uint256 decay = WAD * 95 / 100;
        cumSize = wmul(cumSize, decay) + tradeValue;
        squaredSize = wmul(squaredSize, decay) + wmul(tradeValue, tradeValue);
        tradeCount = tradeCount + 1;
        
        // Estimate trade size variance (proxy for volatility)
        uint256 meanSize = tradeCount > 0 ? cumSize / tradeCount : tradeValue;
        uint256 sizeVariance = squaredSize / (tradeCount + 1);
        
        // Update implicit price estimate (weighted average)
        uint256 tradePrice = wdiv(trade.amountY, trade.amountX);
        uint256 priceWeight = tradeRatio > WAD / 50 ? WAD / 4 : WAD / 10;
        priceEst = wmul(priceEst, WAD - priceWeight) + wmul(tradePrice, priceWeight);
        
        // Detect large trade (potential informed order)
        bool isInformed = tradeRatio > WAD / 15; // >6.67%
        bool isVeryLarge = tradeRatio > WAD / 8;  // >12.5%
        
        // Calculate time since last trade (if we had real timestamps)
        // For now, use trade count as proxy
        
        // Information-based fee adjustment
        if (isVeryLarge) {
            // Very large trades are almost certainly informed
            // Drop fees to minimize adverse selection losses
            baseFee = MIN_FEE + 5 * BPS;
        } else if (isInformed) {
            // Large trades likely informed - be competitive
            baseFee = MIN_FEE + 10 * BPS;
        } else if (tradeRatio < WAD / 200) {
            // Very small trades likely retail - can charge more
            uint256 retailPremium = 5 * BPS;
            baseFee = baseFee + retailPremium;
        }
        
        // Adjust based on recent volatility (variance in trade sizes)
        uint256 volFactor = wdiv(sizeVariance, meanSize * meanSize + 1);
        if (volFactor > WAD / 5) { // High variance
            baseFee = baseFee + 3 * BPS;
        }
        
        // Inventory-based asymmetric fees
        uint256 inventoryRatio = wdiv(trade.reserveX * WAD, trade.reserveY);
        uint256 initialRatio = wdiv(slots[SLOT_INVENTORY_X] * WAD, slots[SLOT_INVENTORY_Y]);
        
        int256 skew = 0;
        if (inventoryRatio > initialRatio) {
            skew = int256(wdiv(inventoryRatio - initialRatio, initialRatio));
        } else {
            skew = -int256(wdiv(initialRatio - inventoryRatio, initialRatio));
        }
        
        int256 askAdj = 0;
        int256 bidAdj = 0;
        
        if (skew > int256(WAD / 10)) { // Heavy X
            askAdj = -int256(8 * BPS); // Lower ask to sell X
            bidAdj = int256(8 * BPS);  // Raise bid to discourage buying X
        } else if (skew < -int256(WAD / 10)) { // Heavy Y
            askAdj = int256(8 * BPS);
            bidAdj = -int256(8 * BPS);
        }
        
        // Apply adjustments
        int256 finalAsk = int256(baseFee) + askAdj;
        int256 finalBid = int256(baseFee) + bidAdj;
        
        // Clamp
        if (finalAsk < int256(MIN_FEE)) finalAsk = int256(MIN_FEE);
        if (finalAsk > int256(MAX_FEE)) finalAsk = int256(MAX_FEE);
        if (finalBid < int256(MIN_FEE)) finalBid = int256(MIN_FEE);
        if (finalBid > int256(MAX_FEE)) finalBid = int256(MAX_FEE);
        
        // Save state
        slots[SLOT_BASE_FEE] = baseFee;
        slots[SLOT_TRADE_COUNT] = tradeCount;
        slots[SLOT_CUM_TRADE_SIZE] = cumSize;
        slots[SLOT_SQUARED_SIZE] = squaredSize;
        slots[SLOT_PRICE_EST] = priceEst;
        
        return (uint256(finalBid), uint256(finalAsk));
    }

    function getName() external pure override returns (string memory) {
        return "MicrostructureAware_v1";
    }
}
