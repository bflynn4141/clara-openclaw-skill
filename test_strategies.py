#!/usr/bin/env python3
"""
AMM Strategy Test Runner
Runs local simulations to validate strategies before submission.
Requires: amm-challenge repository with Rust simulation engine
"""

import subprocess
import sys
import os
import json
from pathlib import Path

# Strategy files to test
STRATEGIES = [
    ("amm-strategy.sol", "Adaptive Volatility"),
    ("amm-strategy-inventory.sol", "Inventory-Aware"),
    ("amm-strategy-signal.sol", "Signal-Based"),
    ("amm-strategy-hybrid.sol", "Hybrid Optimal ⭐"),
    ("amm-strategy-microstructure.sol", "Microstructure-Aware"),
    ("amm-strategy-competitive.sol", "Dynamic Competitive"),
]

def check_environment():
    """Check if the simulation environment is set up."""
    challenge_dir = Path("/Users/gia/.openclaw/workspace/amm-challenge")
    if not challenge_dir.exists():
        print("❌ amm-challenge directory not found!")
        print("   Run: git clone https://github.com/benedictbrady/amm-challenge.git")
        return False
    
    # Check for amm-match command
    result = subprocess.run(["which", "amm-match"], capture_output=True, text=True)
    if result.returncode != 0:
        print("⚠️  amm-match not found in PATH")
        print("   Make sure to: pip install -e /path/to/amm-challenge")
        return False
    
    print("✅ Environment check passed")
    return True

def test_strategy(strategy_file, name, simulations=100):
    """Test a single strategy."""
    strategy_path = f"/Users/gia/.openclaw/workspace/{strategy_file}"
    
    if not os.path.exists(strategy_path):
        print(f"❌ Strategy file not found: {strategy_file}")
        return None
    
    print(f"\n🧪 Testing {name} ({strategy_file})")
    print(f"   Running {simulations} simulations...")
    
    try:
        result = subprocess.run(
            ["amm-match", "run", strategy_path, "--simulations", str(simulations)],
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout
        )
        
        if result.returncode != 0:
            print(f"❌ Test failed: {result.stderr}")
            return None
        
        # Parse output for edge results
        output = result.stdout
        print(f"✅ Test completed")
        
        # Try to extract edge from output
        # Expected format varies, but typically includes "edge" or similar
        return {
            "strategy": name,
            "file": strategy_file,
            "output": output,
            "success": True
        }
        
    except subprocess.TimeoutExpired:
        print(f"❌ Test timed out after 5 minutes")
        return None
    except Exception as e:
        print(f"❌ Test error: {e}")
        return None

def validate_strategy(strategy_file, name):
    """Validate a strategy for submission."""
    strategy_path = f"/Users/gia/.openclaw/workspace/{strategy_file}"
    
    print(f"\n🔍 Validating {name} for submission...")
    
    try:
        result = subprocess.run(
            ["amm-match", "validate", strategy_path],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode == 0:
            print(f"✅ {name} is valid for submission!")
            return True
        else:
            print(f"❌ Validation failed: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Validation error: {e}")
        return False

def main():
    """Main test runner."""
    print("=" * 60)
    print("AMM Challenge Strategy Test Runner")
    print("=" * 60)
    
    # Check environment
    if not check_environment():
        print("\n⚠️  Environment not fully set up.")
        print("To set up:")
        print("  1. git clone https://github.com/benedictbrady/amm-challenge.git")
        print("  2. cd amm-challenge/amm_sim_rs && pip install maturin && maturin develop --release")
        print("  3. cd .. && pip install -e .")
        return 1
    
    # Parse arguments
    simulations = 100
    if len(sys.argv) > 1:
        try:
            simulations = int(sys.argv[1])
        except ValueError:
            pass
    
    print(f"\n📊 Running with {simulations} simulations per strategy")
    
    # Test all strategies
    results = []
    for strategy_file, name in STRATEGIES:
        result = test_strategy(strategy_file, name, simulations)
        if result:
            results.append(result)
    
    # Summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)
    
    if results:
        print(f"\n✅ {len(results)}/{len(STRATEGIES)} strategies tested successfully")
        for r in results:
            print(f"  • {r['strategy']}")
    else:
        print("\n❌ No strategies tested successfully")
    
    print("\n" + "=" * 60)
    print("RECOMMENDED FOR SUBMISSION")
    print("=" * 60)
    print("  1. amm-strategy-hybrid.sol (Hybrid Optimal)")
    print("  2. amm-strategy-signal.sol (Signal-Based)")
    print("  3. amm-strategy.sol (Adaptive Volatility)")
    
    print("\n" + "=" * 60)
    print("SUBMISSION INSTRUCTIONS")
    print("=" * 60)
    print("Visit: https://www.ammchallenge.com/submit")
    print("Upload your .sol strategy file")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
