import { createPublicClient, http, parseAbi, formatUnits } from 'viem';
import { base } from 'viem/chains';

const BOUNTY = '0x8d7EBB4B2cfDBC264f75e100818BdaDC98c8373e';

const bountyAbi = parseAbi([
  'function status() view returns (uint8)',
  'function claimer() view returns (address)',
  'function claimerAgentId() view returns (uint256)',
  'function proofURI() view returns (string)',
]);

const pub = createPublicClient({ 
  chain: base, 
  transport: http('https://mainnet.base.org', { retryCount: 5 })
});

async function check() {
  console.log('=== Who Claimed the Bounty? ===\n');
  
  try {
    // Add delay to avoid rate limits
    await new Promise(r => setTimeout(r, 1000));
    
    const status = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'status' });
    console.log('Status:', status);
    
    await new Promise(r => setTimeout(r, 1000));
    const claimer = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'claimer' });
    console.log('Claimer:', claimer);
    
    await new Promise(r => setTimeout(r, 1000));
    const agentId = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'claimerAgentId' });
    console.log('Claimer Agent ID:', agentId.toString());
    
    await new Promise(r => setTimeout(r, 1000));
    const proof = await pub.readContract({ address: BOUNTY, abi: bountyAbi, functionName: 'proofURI' });
    console.log('\nProof URI:', proof);
    
    // Try to decode proof
    if (proof && proof.startsWith('data:')) {
      try {
        const b64 = proof.split(',')[1];
        const decoded = JSON.parse(Buffer.from(b64, 'base64').toString('utf-8'));
        console.log('\nDecoded Proof:', JSON.stringify(decoded, null, 2));
      } catch (e) {
        console.log('Could not decode proof:', e.message);
      }
    }
    
  } catch (err) {
    console.error('Error:', err.message);
  }
}

check();
