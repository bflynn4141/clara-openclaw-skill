import { createPublicClient, createWalletClient, http, parseEther, serializeTransaction, keccak256 } from 'viem';
import { base } from 'viem/chains';
import { readFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const PROXY_URL = 'https://clara-proxy.bflynn-me.workers.dev';
const WETH = '0x4200000000000000000000000000000000000006';
const wethAbi = [{ inputs: [], name: 'deposit', outputs: [], stateMutability: 'payable', type: 'function' }];

const SESSION_FILE = join(homedir(), '.openclaw', 'credentials', 'clara', 'session.json');
const session = JSON.parse(readFileSync(SESSION_FILE, 'utf-8'));

function createParaAccount(walletId, address) {
  return {
    address,
    type: 'local',
    async signTransaction(tx, { serializer = serializeTransaction } = {}) {
      const serialized = serializer(tx);
      const hash = keccak256(serialized);
      const res = await fetch(`${PROXY_URL}/api/v1/wallets/${walletId}/sign-raw`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Clara-Address': address },
        body: JSON.stringify({ data: hash }),
      });
      if (!res.ok) throw new Error(`Signing failed: ${await res.text()}`);
      const body = await res.json();
      const sig = body.signature || body;
      const rawSig = typeof sig === 'string' ? sig : sig.signature;
      const sigHex = rawSig.startsWith('0x') ? rawSig : `0x${rawSig}`;
      const r = `0x${sigHex.slice(2, 66)}`;
      const s = `0x${sigHex.slice(66, 130)}`;
      const vByte = parseInt(sigHex.slice(130, 132), 16);
      const yParity = vByte >= 27 ? vByte - 27 : vByte;
      return serializer(tx, { r, s, yParity });
    },
    async signMessage() { throw new Error('not implemented'); },
    async signTypedData() { throw new Error('not implemented'); },
  };
}

const account = createParaAccount(session.walletId, session.address);
const wallet = createWalletClient({ account, chain: base, transport: http('https://mainnet.base.org') });
const pub = createPublicClient({ chain: base, transport: http('https://mainnet.base.org') });

console.log('Wrapping 0.005 ETH to WETH...');
const hash = await wallet.writeContract({
  address: WETH,
  abi: wethAbi,
  functionName: 'deposit',
  value: parseEther('0.005'),
});
console.log('Tx:', hash);
console.log('Waiting...');
const receipt = await pub.waitForTransactionReceipt({ hash });
console.log('Done! Block:', receipt.blockNumber.toString());
