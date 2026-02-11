// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AMMStrategyBase} from "./AMMStrategyBase.sol";
import {IAMMStrategy, TradeInfo} from "./IAMMStrategy.sol";

/// @title Dynamic Competitive Strategy
/// @notice Aggressively responds to market conditions with focus on:
///   1. Staying competitive vs the 30bps normalizer
///   2. Capturing retail flow while minimizing arb losses
///   3. Rapid fee adjustments based on recent trade patterns
contract Strategy is AMMStrategyBase {
    
    // Slots
    uint256 constant SLOT_CURRENT_FEE = 0;
    uint256 constant SLOT_LAST_TRADE_SIZE = 1;
    uint256 constant SLOT_CONSEC_COUNT = 2;
    uint256 constant SLOT_ARB_DETECTED = 3;
    uint256 constant SLOT_COOLDOWN = 4;
    uint256 constant SLOT_PROFIT_EST = 5;
    
    // Constants
    uint256 constant NORMALIZER_FEE = 30 * BPS;
    uint256 constant BASE_FEE = 28 * BPS;      // Slightly under normalizer
    uint256 constant MIN_FEE = 10 * BPS;
    uint256 constant MAX_FEE = 100 * BPS;
    uint256 constant ARB_FEE = 15 * BPS;       // Fee when arb detected
    
    function afterInitialize(uint256, uint256) external override returns (uint256 bidFee, uint256 askFee) {
        slots[SLOT_CURRENT_FEE] = BASE_FEE;
        slots[SLOT_LAST_TRADE_SIZE] = 0;
        slots[SLOT_CONSEC_COUNT] = 0;
        slots[SLOT_ARB_DETECTED] = 0;
        slots[SLOT_COOLDOWN] = 0;
        slots[SLOT_PROFIT_EST] = 0;
        
        return (BASE_FEE, BASE_FEE);
    }

    function afterSwap(TradeInfo calldata trade) external override returns (uint256 bidFee, uint256 askFee) {
        uint256 currentFee = slots[SLOT_CURRENT_FEE];
        uint256 lastSize = slots[SLOT_LAST_TRADE_SIZE];
        uint256 consecCount = slots[SLOT_CONSEC_COUNT];
        uint256 arbDetected = slots[SLOT_ARB_DETECTED];
        uint256 cooldown = slots[SLOT_COOLDOWN];
        
        uint256 tradeRatio = wdiv(trade.amountY, trade.reserveY);
        
        // Cooldown management
        if (cooldown > 0) {
            cooldown = cooldown - 1;
        }
        
        // Detect consecutive similar-sized trades (arb pattern)
        if (absDiff(tradeRatio, lastSize) < WAD / 50 && tradeRatio > WAD / 100) {
            consecCount = consecCount + 1;
        } else {
            consecCount = 0;
        }
        
        // Detect arbitrage patterns
        bool isLarge = tradeRatio > WAD / 15; // >6.67%
        bool isConsecutiveLarge = consecCount >= 2 && tradeRatio > WAD / 50;
        
        if (isLarge || isConsecutiveLarge) {
            arbDetected = 3; // 3-step arb response
            cooldown = 5;
        }
        
        // Fee calculation based on state
        if (arbDetected > 0) {
            // Arb mode: stay competitive
            currentFee = ARB_FEE;
            arbDetected = arbDetected - 1;
        } else if (cooldown > 0) {
            // Recovery: gradually raise fees
            uint256 recoveryStep = (BASE_FEE - ARB_FEE) / 5;
            currentFee = ARB_FEE + (recoveryStep * (5 - cooldown));
        } else {
            // Normal operation
            if (tradeRatio < WAD / 200) {
                // Small retail trade: can charge more
                currentFee = BASE_FEE + 5 * BPS;
            } else if (tradeRatio > WAD / 20) {
                // Medium trade: be competitive
                currentFee = BASE_FEE - 3 * BPS;
            } else {
                currentFee = BASE_FEE;
            }
        }
        
        // Clamp
        if (currentFee < MIN_FEE) currentFee = MIN_FEE;
        if (currentFee > MAX_FEE) currentFee = MAX_FEE;
        
        // Simple asymmetric: if many consecutive same direction, skew fees
        uint256 askFee = currentFee;
        uint256 bidFee = currentFee;
        
        if (consecCount >= 3) {
            // Expect continuation - make that side more expensive
            if (trade.isBuy) {
                // Many buys, expect more sells
                askFee = currentFee - 2 * BPS;
                bidFee = currentFee + 3 * BPS;
            } else {
                bidFee = currentFee - 2 * BPS;
                askFee = currentFee + 3 * BPS;
            }
        }
        
        // Save state
        slots[SLOT_CURRENT_FEE] = currentFee;
        slots[SLOT_LAST_TRADE_SIZE] = tradeRatio;
        slots[SLOT_CONSEC_COUNT] = consecCount;
        slots[SLOT_ARB_DETECTED] = arbDetected;
        slots[SLOT_COOLDOWN] = cooldown;
        
        return (bidFee, askFee);
    }

    function getName() external pure override returns (string memory) {
        return "DynamicCompetitive_v1";
    }
}
