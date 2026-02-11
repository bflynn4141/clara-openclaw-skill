import { createPublicClient, http, parseAbi, formatUnits } from 'viem';
import { base } from 'viem/chains';

const BOUNTY = '0x8d7EBB4B2cfDBC264f75e100818BdaDC98c8373e';
const FACTORY = '0x639A05560Cf089187494f9eE357D7D1c69b7558e';

// Minimal bounty ABI for debugging
const bountyAbi = parseAbi([
  'function status() view returns (uint8)',
  'function amount() view returns (uint256)',
  'function token() view returns (address)',
  'function deadline() view returns (uint256)',
  'function poster() view returns (address)',
  'function claimer() view returns (address)',
  'function claimerAgentId() view returns (uint256)',
  'function workerBond() view returns (uint256)',
  'function posterBond() view returns (uint256)',
  'function submittedAt() view returns (uint256)',
  'function rejectionCount() view returns (uint8)',
]);

const factoryAbi = parseAbi([
  'function bondRate() view returns (uint256)',
  'function bountyImpl() view returns (address)',
]);

const pub = createPublicClient({ 
  chain: base, 
  transport: http('https://mainnet.base.org', { retryCount: 3 })
});

async function debug() {
  console.log('=== Clara Bounty Debug ===\n');
  console.log('Bounty Address:', BOUNTY);
  
  try {
    // Read all state at once with individual calls to avoid multicall issues
    console.log('\n--- Bounty State ---');
    const status = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'status' });
    console.log('Status:', status, '(0=Open, 1=Claimed, 2=Submitted, 3=Approved, 4=Rejected, 5=Cancelled, 6=Expired)');
    
    const amount = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'amount' });
    console.log('Amount:', formatUnits(amount, 18), 'WETH');
    
    const token = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'token' });
    console.log('Token:', token);
    
    const deadline = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'deadline' });
    const deadlineDate = new Date(Number(deadline) * 1000);
    console.log('Deadline:', deadlineDate.toISOString(), `(in ${Math.floor((Number(deadline) * 1000 - Date.now()) / 1000 / 60)} minutes)`);
    console.log('Deadline passed:', Date.now() > Number(deadline) * 1000);
    
    const poster = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'poster' });
    console.log('Poster:', poster);
    
    const claimer = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'claimer' });
    console.log('Claimer:', claimer);
    
    const claimerAgentId = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'claimerAgentId' });
    console.log('Claimer Agent ID:', claimerAgentId.toString());
    
    const workerBond = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'workerBond' });
    console.log('Worker Bond:', formatUnits(workerBond, 18), 'WETH');
    
    const posterBond = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'posterBond' });
    console.log('Poster Bond:', formatUnits(posterBond, 18), 'WETH');
    
    const submittedAt = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'submittedAt' });
    console.log('Submitted At:', submittedAt.toString());
    
    const rejectionCount = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'rejectionCount' });
    console.log('Rejection Count:', rejectionCount.toString());
    
    // Factory info
    console.log('\n--- Factory State ---');
    const bondRate = await pub.readContract({ address: FACTORY, abi: factoryAbi, functionName: 'bondRate' });
    console.log('Bond Rate:', bondRate.toString(), 'basis points (1000 = 10%)');
    
    const impl = await pub.readContract({ address: FACTORY, abi: factoryAbi, functionName: 'bountyImpl' });
    console.log('Implementation:', impl);
    
  } catch (err) {
    console.error('Error:', err.message);
    if (err.message.includes('429')) {
      console.log('\nRate limited. Try again in a moment.');
    }
  }
}

debug();
