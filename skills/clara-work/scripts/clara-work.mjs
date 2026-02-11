#!/usr/bin/env node
/**
 * Clara Work Marketplace CLI for OpenClaw
 *
 * Enables OpenClaw agents to interact with Clara's on-chain
 * work marketplace (bounties, agent registration, reputation)
 * on Base L2.
 *
 * All write operations sign via Para API through clara-proxy.
 * All read operations go directly to Base RPC.
 *
 * Usage: node clara-work.mjs <command> [--key value ...]
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  decodeEventLog,
  serializeTransaction,
  keccak256,
  parseUnits,
  formatUnits,
  isAddress,
  parseAbi,
  encodeFunctionData,
  toHex,
  stringToHex,
} from 'viem';
import { base } from 'viem/chains';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// ─── Configuration ──────────────────────────────────────────────────────────

const PROXY_URL = process.env.CLARA_PROXY_URL || 'https://clara-proxy.bflynn-me.workers.dev';
const RPC_URL = process.env.BASE_RPC_URL || 'https://mainnet.base.org';

const CONTRACTS = {
  IDENTITY_REGISTRY: '0x8004A169FB4a3325136EB29fA0ceB6D2e539a432',
  REPUTATION_REGISTRY: '0x8004BAa17C55a88189AE136b182e5fdA19dE9b63',
  BOUNTY_FACTORY: '0x639A05560Cf089187494f9eE357D7D1c69b7558e',
};

const TOKENS = {
  USDC: { address: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', decimals: 6 },
  USDT: { address: '0xfde4C96c8593536E5a98a31fF2326B4b8b60B8d9', decimals: 6 },
  DAI:  { address: '0x50c5725949A6F0c72e6C4A641f24049A917DB0Cb', decimals: 18 },
  WETH: { address: '0x4200000000000000000000000000000000000006', decimals: 18 },
};

const BOUNTY_FIRST_BLOCK = 41888723n;
const BOUNTY_STATUS = ['Open', 'Claimed', 'Submitted', 'Approved', 'Rejected', 'Cancelled', 'Expired'];

// ─── ABIs (human-readable format via viem parseAbi) ─────────────────────────

const identityAbi = parseAbi([
  'function register(string agentURI) returns (uint256 agentId)',
  'function updateURI(uint256 agentId, string newURI)',
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function balanceOf(address owner) view returns (uint256)',
  'function tokenURI(uint256 tokenId) view returns (string)',
  'function tokenOfOwnerByIndex(address owner, uint256 index) view returns (uint256)',
  'event Register(uint256 indexed agentId, address indexed owner, string agentURI)',
  'event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)',
]);

const reputationAbi = parseAbi([
  'function giveFeedback(uint256 agentId, int128 value, uint8 valueDecimals, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)',
  'function getSummary(uint256 agentId, address[] clientAddresses, string tag1, string tag2) view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals)',
]);

const factoryAbi = parseAbi([
  'function createBounty(address token, uint256 amount, uint256 deadline, string taskURI, string[] skillTags) returns (address bountyAddress)',
  'function bondRate() view returns (uint256)',
  'event BountyCreated(address indexed bountyAddress, address indexed poster, address token, uint256 amount, uint256 posterBond, uint256 bondRate, uint256 deadline, string taskURI, string[] skillTags)',
]);

const bountyAbi = parseAbi([
  'function claim(uint256 agentId)',
  'function submitWork(string proofURI)',
  'function approve()',
  'function approveWithFeedback(int128 value, uint8 valueDecimals, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)',
  'function reject()',
  'function cancel()',
  'function status() view returns (uint8)',
  'function amount() view returns (uint256)',
  'function token() view returns (address)',
  'function deadline() view returns (uint256)',
  'function poster() view returns (address)',
  'function claimer() view returns (address)',
  'function claimerAgentId() view returns (uint256)',
  'function taskURI() view returns (string)',
  'function proofURI() view returns (string)',
  'function posterBond() view returns (uint256)',
  'function workerBond() view returns (uint256)',
  'function submittedAt() view returns (uint256)',
  'function rejectionCount() view returns (uint8)',
]);

const erc20Abi = parseAbi([
  'function approve(address spender, uint256 amount) returns (bool)',
  'function balanceOf(address account) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
]);

// ─── Session Management ─────────────────────────────────────────────────────

const SESSION_DIR = join(homedir(), '.openclaw', 'credentials', 'clara');
const SESSION_FILE = join(SESSION_DIR, 'session.json');

function loadSession() {
  if (!existsSync(SESSION_FILE)) return null;
  try {
    return JSON.parse(readFileSync(SESSION_FILE, 'utf-8'));
  } catch { return null; }
}

function saveSession(session) {
  mkdirSync(SESSION_DIR, { recursive: true });
  writeFileSync(SESSION_FILE, JSON.stringify(session, null, 2), { mode: 0o600 });
}

function requireSession() {
  const session = loadSession();
  if (!session) {
    output({ ok: false, error: 'No wallet session. Run: node clara-work.mjs setup --email you@example.com' });
    process.exit(1);
  }
  return session;
}

// ─── Para Custom Account (delegates signing to Clara Proxy) ─────────────────

function createParaAccount(walletId, address) {
  return {
    address,
    type: 'local',

    async signTransaction(tx, { serializer = serializeTransaction } = {}) {
      const serialized = serializer(tx);
      const hash = keccak256(serialized);

      log(`Signing via Para...`);
      const res = await fetch(`${PROXY_URL}/api/v1/wallets/${walletId}/sign-raw`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Clara-Address': address,
        },
        body: JSON.stringify({ data: hash }),
      });

      if (!res.ok) {
        const err = await res.text();
        throw new Error(`Signing failed (${res.status}): ${err}`);
      }

      const body = await res.json();
      const sig = body.signature || body;

      // Parse 65-byte signature: r (32 bytes) + s (32 bytes) + v (1 byte)
      const rawSig = typeof sig === 'string' ? sig : sig.signature;
      const sigHex = rawSig.startsWith('0x') ? rawSig : `0x${rawSig}`;
      const r = `0x${sigHex.slice(2, 66)}`;
      const s = `0x${sigHex.slice(66, 130)}`;
      const vByte = parseInt(sigHex.slice(130, 132), 16);
      const yParity = vByte >= 27 ? vByte - 27 : vByte;

      return serializer(tx, { r, s, yParity });
    },

    async signMessage({ message }) {
      const msgHex = typeof message === 'string'
        ? stringToHex(message)
        : toHex(message);

      const res = await fetch(`${PROXY_URL}/api/v1/wallets/${walletId}/sign-raw`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Clara-Address': address,
        },
        body: JSON.stringify({ data: msgHex }),
      });

      if (!res.ok) throw new Error(`Sign message failed: ${await res.text()}`);
      const body = await res.json();
      return body.signature || body;
    },

    async signTypedData(_typedData) {
      throw new Error('signTypedData not yet implemented for OpenClaw');
    },
  };
}

// ─── Clients ────────────────────────────────────────────────────────────────

function getPublicClient() {
  return createPublicClient({ chain: base, transport: http(RPC_URL) });
}

function getWalletClient(session) {
  const account = createParaAccount(session.walletId, session.address);
  return createWalletClient({ account, chain: base, transport: http(RPC_URL) });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function log(msg) { process.stderr.write(`${msg}\n`); }
function output(obj) { console.log(JSON.stringify(obj, null, 2)); }

function toDataURI(obj) {
  const json = JSON.stringify(obj);
  const b64 = Buffer.from(json).toString('base64');
  return `data:application/json;base64,${b64}`;
}

function parseDataURI(uri) {
  if (!uri.startsWith('data:')) return null;
  try {
    const b64 = uri.split(',')[1];
    return JSON.parse(Buffer.from(b64, 'base64').toString('utf-8'));
  } catch { return null; }
}

function parseDeadline(str) {
  const d = new Date(str);
  if (!isNaN(d.getTime())) return Math.floor(d.getTime() / 1000);

  const match = str.match(/^(\d+)\s*(hour|day|week|month)s?$/i);
  if (!match) throw new Error(`Invalid deadline: "${str}". Use ISO date or relative like "3 days"`);
  const [, num, unit] = match;
  const seconds = { hour: 3600, day: 86400, week: 604800, month: 2592000 };
  return Math.floor(Date.now() / 1000) + parseInt(num) * seconds[unit.toLowerCase()];
}

function resolveToken(symbol) {
  const key = (symbol || 'USDC').toUpperCase();
  const token = TOKENS[key];
  if (!token) throw new Error(`Unknown token: ${symbol}. Supported: ${Object.keys(TOKENS).join(', ')}`);
  return { ...token, symbol: key };
}

function shortAddr(addr) {
  return addr ? `${addr.slice(0, 6)}...${addr.slice(-4)}` : 'none';
}

/** Look up agent ID for an address by scanning Register events */
async function getAgentIdForAddress(pub, address) {
  // Check session cache first (avoids RPC log scanning limits)
  const session = loadSession();
  if (session?.agentId && session.address?.toLowerCase() === address.toLowerCase()) {
    return BigInt(session.agentId);
  }
  try {
    const events = await pub.getContractEvents({
      address: CONTRACTS.IDENTITY_REGISTRY,
      abi: identityAbi,
      eventName: 'Register',
      args: { owner: address },
      fromBlock: BOUNTY_FIRST_BLOCK,
      toBlock: 'latest',
    });
    if (events.length > 0) {
      // Return the most recent registration
      return events[events.length - 1].args.agentId;
    }
  } catch {
    // Fallback: try tokenOfOwnerByIndex (works on some contracts)
    try {
      const count = await pub.readContract({
        address: CONTRACTS.IDENTITY_REGISTRY,
        abi: identityAbi,
        functionName: 'balanceOf',
        args: [address],
      });
      if (count > 0n) {
        return await pub.readContract({
          address: CONTRACTS.IDENTITY_REGISTRY,
          abi: identityAbi,
          functionName: 'tokenOfOwnerByIndex',
          args: [address, 0n],
        });
      }
    } catch { /* neither method works */ }
  }
  return null;
}

function tokenSymbolByAddress(addr) {
  const lower = addr.toLowerCase();
  for (const [sym, t] of Object.entries(TOKENS)) {
    if (t.address.toLowerCase() === lower) return sym;
  }
  return shortAddr(addr);
}

// ─── Argument Parser ────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith('--')) {
        args[key] = next;
        i++;
      } else {
        args[key] = true;
      }
    } else if (!args._positional) {
      args._positional = argv[i];
    }
  }
  return args;
}

// ─── Commands ───────────────────────────────────────────────────────────────

async function cmdSetup(args) {
  const email = args.email;
  if (!email) {
    output({ ok: false, error: 'Email required: --email you@example.com' });
    return;
  }

  log(`Creating wallet for ${email}...`);
  const res = await fetch(`${PROXY_URL}/api/v1/wallets`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: 'EVM',
      userIdentifier: email,
      userIdentifierType: 'EMAIL',
    }),
  });

  if (!res.ok) {
    output({ ok: false, error: `Wallet creation failed (${res.status}): ${await res.text()}` });
    return;
  }

  const wallet = await res.json();
  const session = {
    walletId: wallet.id,
    address: wallet.address,
    email,
    chainId: 8453,
    createdAt: new Date().toISOString(),
  };
  saveSession(session);
  log(`Wallet ready: ${session.address}`);

  // Auto-request gas sponsorship for new wallets
  const pub = getPublicClient();
  const balance = await pub.getBalance({ address: session.address });
  if (balance === 0n) {
    log('Requesting gas sponsorship...');
    try {
      const gasRes = await fetch(`${PROXY_URL}/onboard/sponsor-gas`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Clara-Address': session.address,
        },
      });
      if (gasRes.ok) {
        log('Gas sponsored! You have enough ETH for transactions.');
      } else {
        log('Gas sponsorship unavailable. You may need to bridge ETH to Base.');
      }
    } catch {
      log('Could not request gas sponsorship.');
    }
  }

  output({ ok: true, address: session.address, walletId: session.walletId, email });
}

async function cmdStatus(_args) {
  const session = loadSession();
  if (!session) {
    output({ ok: true, authenticated: false, message: 'No session. Run setup first.' });
    return;
  }

  const pub = getPublicClient();
  const balance = await pub.getBalance({ address: session.address });

  // Check if registered as agent
  const agentId = await getAgentIdForAddress(pub, session.address);

  output({
    ok: true,
    authenticated: true,
    address: session.address,
    email: session.email,
    ethBalance: formatUnits(balance, 18),
    agentId: agentId !== null ? agentId.toString() : null,
  });
}

async function cmdRegister(args) {
  const session = requireSession();
  const { name, skills, bio } = args;

  if (!name || !skills) {
    output({ ok: false, error: 'Required: --name "Agent Name" --skills "sol,ts,react"' });
    return;
  }

  const skillArray = skills.split(',').map(s => s.trim());

  const agentData = {
    type: 'AgentRegistration',
    name,
    description: bio || '',
    image: '',
    services: [
      { type: 'agentWallet', endpoint: `eip155:8453:${session.address}` },
    ],
    skills: skillArray,
    x402Support: true,
    active: true,
    registrations: [],
  };

  const agentURI = toDataURI(agentData);
  const wallet = getWalletClient(session);
  const pub = getPublicClient();

  log('Registering agent on-chain...');
  const hash = await wallet.writeContract({
    address: CONTRACTS.IDENTITY_REGISTRY,
    abi: identityAbi,
    functionName: 'register',
    args: [agentURI],
  });

  log(`Tx: ${hash}`);
  log('Waiting for confirmation...');
  const receipt = await pub.waitForTransactionReceipt({ hash });

  let agentId = null;
  for (const eventLog of receipt.logs) {
    try {
      const decoded = decodeEventLog({
        abi: identityAbi,
        data: eventLog.data,
        topics: eventLog.topics,
      });
      if (decoded.eventName === 'Register') {
        agentId = decoded.args.agentId.toString();
      } else if (!agentId && decoded.eventName === 'Transfer' &&
                 decoded.args.from === '0x0000000000000000000000000000000000000000') {
        // Fallback: ERC-721 mint Transfer event carries the tokenId
        agentId = decoded.args.tokenId.toString();
      }
    } catch { /* not our event */ }
  }

  // Persist agentId in session for future lookups (avoids RPC log scanning limits)
  if (agentId) {
    session.agentId = parseInt(agentId);
    saveSession(session);
  }

  // Upload profile to proxy for public discoverability
  if (agentId) {
    try {
      await fetch(`${PROXY_URL}/agents/${agentId}.json`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Clara-Address': session.address,
        },
        body: JSON.stringify({ ...agentData, agentId, address: session.address }),
      });
    } catch { /* optional, non-blocking */ }
  }

  output({
    ok: true,
    agentId,
    txHash: hash,
    blockNumber: receipt.blockNumber.toString(),
    name,
    skills: skillArray,
  });
}

async function cmdBrowse(args) {
  const pub = getPublicClient();
  const latestBlock = await pub.getBlockNumber();

  // Default: look back ~24 hours (43200 blocks at 2s/block on Base)
  const lookbackBlocks = BigInt(parseInt(args.days || '1') * 43200);
  const fromBlock = latestBlock - lookbackBlocks > BOUNTY_FIRST_BLOCK
    ? latestBlock - lookbackBlocks
    : BOUNTY_FIRST_BLOCK;

  log(`Scanning bounties from block ${fromBlock} to ${latestBlock}...`);

  // Scan in chunks to avoid public RPC range limits
  const CHUNK = 5000n;
  let events = [];
  for (let from = fromBlock; from <= latestBlock; from += CHUNK) {
    const to = from + CHUNK - 1n > latestBlock ? latestBlock : from + CHUNK - 1n;
    try {
      const chunk = await pub.getContractEvents({
        address: CONTRACTS.BOUNTY_FACTORY,
        abi: factoryAbi,
        eventName: 'BountyCreated',
        fromBlock: from,
        toBlock: to,
      });
      if (chunk.length > 0) events.push(...chunk);
    } catch {
      log(`Chunk ${from}-${to} failed, skipping...`);
    }
  }

  if (events.length === 0) {
    output({ ok: true, bounties: [], message: 'No bounties found in this time range.' });
    return;
  }

  // Read current status for each bounty via multicall
  const bountyAddresses = events.map(e => e.args.bountyAddress);
  const statusCalls = bountyAddresses.map(addr => ({
    address: addr,
    abi: bountyAbi,
    functionName: 'status',
  }));

  log(`Found ${events.length} bounties, reading current status...`);
  const statuses = await pub.multicall({ contracts: statusCalls });

  const bounties = events.map((e, i) => {
    const status = statuses[i].status === 'success' ? Number(statuses[i].result) : -1;
    const a = e.args;
    const tokenSym = tokenSymbolByAddress(a.token);
    const tokenInfo = TOKENS[tokenSym] || { decimals: 18 };

    return {
      address: a.bountyAddress,
      poster: a.poster,
      token: tokenSym,
      amount: formatUnits(a.amount, tokenInfo.decimals),
      posterBond: formatUnits(a.posterBond, tokenInfo.decimals),
      deadline: new Date(Number(a.deadline) * 1000).toISOString(),
      status: BOUNTY_STATUS[status] || `Unknown(${status})`,
      statusCode: status,
      skills: a.skillTags,
      task: parseDataURI(a.taskURI)?.summary || a.taskURI,
    };
  });

  // Apply filters
  let filtered = bounties;
  if (args.skill) {
    const skill = args.skill.toLowerCase();
    filtered = filtered.filter(b =>
      b.skills.some(s => s.toLowerCase().includes(skill))
    );
  }
  if (args.min) {
    filtered = filtered.filter(b => parseFloat(b.amount) >= parseFloat(args.min));
  }
  if (args.max) {
    filtered = filtered.filter(b => parseFloat(b.amount) <= parseFloat(args.max));
  }
  if (!args.all) {
    // Default: only show Open bounties
    filtered = filtered.filter(b => b.statusCode === 0);
  }

  output({ ok: true, bounties: filtered, total: filtered.length });
}

/** Decode common contract revert errors */
function decodeRevertError(err) {
  const msg = err.message || err.toString();
  
  // Known error signatures
  const errorSignatures = {
    '0xf924664d': 'InvalidStatus(currentStatus, requiredStatus) - Bounty not in Open state',
    '0x4e487b71': 'Panic(uint256) - Internal contract panic',
    '0x08c379a0': 'Error(string) - Generic revert with message',
    'InsufficientAllowance': 'Insufficient token allowance for worker bond. Run with --approve-bond first',
  };
  
  for (const [sig, desc] of Object.entries(errorSignatures)) {
    if (msg.includes(sig)) return desc;
  }
  
  // Check for common patterns
  if (msg.includes('ERC20:')) return `ERC20 Error: ${msg.match(/ERC20:[^\n]+/)?.[0] || 'Token transfer failed'}`;
  if (msg.includes('reverted')) return `Contract reverted: ${msg.match(/reverted[^\n]*/)?.[0] || 'Unknown reason'}`;
  
  return msg;
}

async function cmdClaim(args) {
  const session = requireSession();
  const bountyAddress = args.bounty || args._positional;
  const skipApproval = args['skip-approval'] || false;

  if (!bountyAddress || !isAddress(bountyAddress)) {
    output({ ok: false, error: 'Required: --bounty 0xBountyAddress' });
    return;
  }

  const pub = getPublicClient();
  const agentId = await getAgentIdForAddress(pub, session.address);

  if (agentId === null) {
    output({ ok: false, error: 'Not registered as an agent. Run "register" first.' });
    return;
  }

  // Pre-check: verify bounty is Open
  try {
    const status = await pub.readContract({
      address: bountyAddress,
      abi: bountyAbi,
      functionName: 'status',
    });
    
    if (status !== 0n) {
      const statusName = BOUNTY_STATUS[Number(status)] || `Unknown(${status})`;
      output({ 
        ok: false, 
        error: `Cannot claim: Bounty status is "${statusName}" (expected "Open"). Only Open bounties can be claimed.`,
        status: Number(status),
        statusName,
      });
      return;
    }
  } catch (statusErr) {
    log(`Warning: Could not verify bounty status: ${statusErr.message}`);
  }

  // Optional: Handle worker bond approval
  if (!skipApproval) {
    try {
      const token = await pub.readContract({ address: bountyAddress, abi: bountyAbi, functionName: 'token' });
      const workerBond = await pub.readContract({ address: bountyAddress, abi: bountyAbi, functionName: 'workerBond' });
      
      if (workerBond > 0n) {
        const tokenSym = tokenSymbolByAddress(token);
        log(`Note: This bounty requires a worker bond of ${formatUnits(workerBond, TOKENS[tokenSym]?.decimals || 18)} ${tokenSym}`);
        log(`If claim fails, run with --approve-bond to approve the bond first.`);
      }
    } catch {
      // Non-critical, continue
    }
  }

  const wallet = getWalletClient(session);

  log(`Claiming bounty ${shortAddr(bountyAddress)} as agent #${agentId}...`);
  
  try {
    const hash = await wallet.writeContract({
      address: bountyAddress,
      abi: bountyAbi,
      functionName: 'claim',
      args: [agentId],
    });

    log(`Tx: ${hash}`);
    log('Waiting for confirmation...');
    const receipt = await pub.waitForTransactionReceipt({ hash });

    output({
      ok: true,
      txHash: hash,
      blockNumber: receipt.blockNumber.toString(),
      bountyAddress,
      agentId: agentId.toString(),
    });
  } catch (err) {
    const decoded = decodeRevertError(err);
    output({
      ok: false,
      error: `Claim failed: ${decoded}`,
      suggestion: decoded.includes('InvalidStatus') 
        ? 'The bounty may have been claimed by someone else, or is no longer Open. Run "browse --all" to check current status.'
        : decoded.includes('Allowance')
        ? 'Run with --approve-bond flag to approve the worker bond first.'
        : 'Check the bounty status and try again.',
      rawError: err.message,
    });
  }
}

async function cmdSubmit(args) {
  const session = requireSession();
  const bountyAddress = args.bounty || args._positional;
  const proof = args.proof;

  if (!bountyAddress || !proof) {
    output({ ok: false, error: 'Required: --bounty 0xAddress --proof "URL or description"' });
    return;
  }

  // If proof is a URL, use as-is. Otherwise encode as data URI.
  let proofURI;
  if (proof.startsWith('http://') || proof.startsWith('https://') || proof.startsWith('ipfs://')) {
    proofURI = proof;
  } else {
    proofURI = toDataURI({
      proof,
      submittedBy: session.address,
      timestamp: new Date().toISOString(),
    });
  }

  const wallet = getWalletClient(session);
  const pub = getPublicClient();

  log(`Submitting work to ${shortAddr(bountyAddress)}...`);
  const hash = await wallet.writeContract({
    address: bountyAddress,
    abi: bountyAbi,
    functionName: 'submitWork',
    args: [proofURI],
  });

  log(`Tx: ${hash}`);
  log('Waiting for confirmation...');
  const receipt = await pub.waitForTransactionReceipt({ hash });

  output({
    ok: true,
    txHash: hash,
    blockNumber: receipt.blockNumber.toString(),
    bountyAddress,
    proofURI,
  });
}

async function cmdApprove(args) {
  const session = requireSession();
  const bountyAddress = args.bounty || args._positional;

  if (!bountyAddress) {
    output({ ok: false, error: 'Required: --bounty 0xAddress' });
    return;
  }

  const wallet = getWalletClient(session);
  const pub = getPublicClient();
  const rating = parseInt(args.rating || '0');
  let hash;

  if (rating > 0) {
    // Approve with reputation feedback
    const comment = args.comment || '';
    const feedbackData = {
      rating,
      comment,
      bountyAddress,
      timestamp: new Date().toISOString(),
    };
    const feedbackURI = toDataURI(feedbackData);
    const feedbackHash = keccak256(stringToHex(feedbackURI));

    log(`Approving with ${rating}/5 rating...`);
    hash = await wallet.writeContract({
      address: bountyAddress,
      abi: bountyAbi,
      functionName: 'approveWithFeedback',
      args: [BigInt(rating), 0, 'bounty', 'completed', '', feedbackURI, feedbackHash],
    });
  } else {
    log('Approving work (no rating)...');
    hash = await wallet.writeContract({
      address: bountyAddress,
      abi: bountyAbi,
      functionName: 'approve',
    });
  }

  log(`Tx: ${hash}`);
  log('Waiting for confirmation...');
  const receipt = await pub.waitForTransactionReceipt({ hash });

  output({
    ok: true,
    txHash: hash,
    blockNumber: receipt.blockNumber.toString(),
    bountyAddress,
    rating: rating || 'none',
  });
}

async function cmdReject(args) {
  const session = requireSession();
  const bountyAddress = args.bounty || args._positional;

  if (!bountyAddress) {
    output({ ok: false, error: 'Required: --bounty 0xAddress' });
    return;
  }

  const wallet = getWalletClient(session);
  const pub = getPublicClient();

  log(`Rejecting work at ${shortAddr(bountyAddress)}...`);
  const hash = await wallet.writeContract({
    address: bountyAddress,
    abi: bountyAbi,
    functionName: 'reject',
  });

  log(`Tx: ${hash}`);
  log('Waiting for confirmation...');
  const receipt = await pub.waitForTransactionReceipt({ hash });

  output({
    ok: true,
    txHash: hash,
    blockNumber: receipt.blockNumber.toString(),
    bountyAddress,
  });
}

async function cmdCancel(args) {
  const session = requireSession();
  const bountyAddress = args.bounty || args._positional;

  if (!bountyAddress) {
    output({ ok: false, error: 'Required: --bounty 0xAddress' });
    return;
  }

  const wallet = getWalletClient(session);
  const pub = getPublicClient();

  log(`Cancelling bounty ${shortAddr(bountyAddress)}...`);
  const hash = await wallet.writeContract({
    address: bountyAddress,
    abi: bountyAbi,
    functionName: 'cancel',
  });

  log(`Tx: ${hash}`);
  log('Waiting for confirmation...');
  const receipt = await pub.waitForTransactionReceipt({ hash });

  output({
    ok: true,
    txHash: hash,
    blockNumber: receipt.blockNumber.toString(),
    bountyAddress,
  });
}

async function cmdApproveBond(args) {
  const session = requireSession();
  const bountyAddress = args.bounty || args._positional;
  const amount = args.amount;

  if (!bountyAddress || !isAddress(bountyAddress)) {
    output({ ok: false, error: 'Required: --bounty 0xBountyAddress' });
    return;
  }

  const pub = getPublicClient();
  
  // Get bounty details
  let token, workerBond;
  try {
    token = await pub.readContract({ address: bountyAddress, abi: bountyAbi, functionName: 'token' });
    workerBond = await pub.readContract({ address: bountyAddress, abi: bountyAbi, functionName: 'workerBond' });
  } catch (err) {
    output({ ok: false, error: `Failed to read bounty details: ${err.message}` });
    return;
  }

  const tokenSym = tokenSymbolByAddress(token);
  const tokenInfo = TOKENS[tokenSym] || { decimals: 18 };
  
  // Use provided amount or default to workerBond
  const approveAmount = amount ? parseUnits(amount, tokenInfo.decimals) : workerBond;
  
  log(`Approving ${formatUnits(approveAmount, tokenInfo.decimals)} ${tokenSym} for worker bond on bounty ${shortAddr(bountyAddress)}...`);
  
  const wallet = getWalletClient(session);
  
  try {
    const hash = await wallet.writeContract({
      address: token,
      abi: erc20Abi,
      functionName: 'approve',
      args: [bountyAddress, approveAmount],
    });

    log(`Approve tx: ${hash}`);
    log('Waiting for confirmation...');
    const receipt = await pub.waitForTransactionReceipt({ hash });

    output({
      ok: true,
      txHash: hash,
      blockNumber: receipt.blockNumber.toString(),
      bountyAddress,
      token: tokenSym,
      amount: formatUnits(approveAmount, tokenInfo.decimals),
      note: 'You can now claim this bounty with --skip-approval',
    });
  } catch (err) {
    output({
      ok: false,
      error: `Approval failed: ${decodeRevertError(err)}`,
      rawError: err.message,
    });
  }
}

async function cmdPost(args) {
  const session = requireSession();
  const { amount, token: tokenSymbol, deadline, task, skills } = args;

  if (!amount || !deadline || !task) {
    output({ ok: false, error: 'Required: --amount 50 --deadline "3 days" --task "Description of work"' });
    return;
  }

  const token = resolveToken(tokenSymbol);
  const amountWei = parseUnits(amount, token.decimals);
  const deadlineTimestamp = parseDeadline(deadline);
  const skillArray = skills ? skills.split(',').map(s => s.trim()) : [];

  // Bond rate is 10% (1000 basis points)
  const bondAmount = (amountWei * 1000n) / 10000n;
  const totalApproval = amountWei + bondAmount;

  const taskURI = toDataURI({
    summary: task,
    skills: skillArray,
    postedBy: session.address,
    timestamp: new Date().toISOString(),
  });

  const wallet = getWalletClient(session);
  const pub = getPublicClient();

  // Step 1: ERC-20 approve (amount + poster bond)
  log(`Approving ${formatUnits(totalApproval, token.decimals)} ${token.symbol} (${amount} + 10% bond)...`);
  const approveTx = await wallet.writeContract({
    address: token.address,
    abi: erc20Abi,
    functionName: 'approve',
    args: [CONTRACTS.BOUNTY_FACTORY, totalApproval],
  });

  log(`Approve tx: ${approveTx}`);
  log('Waiting for approval confirmation...');
  await pub.waitForTransactionReceipt({ hash: approveTx });

  // Step 2: Create bounty
  log('Creating bounty...');
  const createTx = await wallet.writeContract({
    address: CONTRACTS.BOUNTY_FACTORY,
    abi: factoryAbi,
    functionName: 'createBounty',
    args: [token.address, amountWei, BigInt(deadlineTimestamp), taskURI, skillArray],
  });

  log(`Create tx: ${createTx}`);
  log('Waiting for creation confirmation...');
  const receipt = await pub.waitForTransactionReceipt({ hash: createTx });

  // Extract bounty address from BountyCreated event
  let bountyAddress = null;
  for (const eventLog of receipt.logs) {
    try {
      const decoded = decodeEventLog({
        abi: factoryAbi,
        data: eventLog.data,
        topics: eventLog.topics,
      });
      if (decoded.eventName === 'BountyCreated') {
        bountyAddress = decoded.args.bountyAddress;
      }
    } catch { /* not our event */ }
  }

  output({
    ok: true,
    bountyAddress,
    amount: `${amount} ${token.symbol}`,
    bond: formatUnits(bondAmount, token.decimals) + ` ${token.symbol}`,
    deadline: new Date(deadlineTimestamp * 1000).toISOString(),
    task,
    skills: skillArray,
    approveTxHash: approveTx,
    createTxHash: createTx,
  });
}

async function cmdProfile(args) {
  const session = loadSession();
  const address = args.address || args._positional || session?.address;

  if (!address) {
    output({ ok: false, error: 'No address. Provide --address or run setup first.' });
    return;
  }

  const pub = getPublicClient();

  // Find agent ID via Register events
  const agentId = await getAgentIdForAddress(pub, address);

  if (agentId === null) {
    output({ ok: true, registered: false, address, message: 'Not registered as an agent.' });
    return;
  }

  const tokenURI = await pub.readContract({
    address: CONTRACTS.IDENTITY_REGISTRY,
    abi: identityAbi,
    functionName: 'tokenURI',
    args: [agentId],
  });

  const metadata = parseDataURI(tokenURI);

  // Get reputation summary
  let reputation = null;
  try {
    const [count, value, decimals] = await pub.readContract({
      address: CONTRACTS.REPUTATION_REGISTRY,
      abi: reputationAbi,
      functionName: 'getSummary',
      args: [agentId, [], '', ''],
    });
    reputation = {
      feedbackCount: count.toString(),
      totalValue: value.toString(),
      decimals: Number(decimals),
    };
  } catch { /* no reputation yet */ }

  output({
    ok: true,
    registered: true,
    address,
    agentId: agentId.toString(),
    name: metadata?.name || null,
    description: metadata?.description || null,
    skills: metadata?.skills || [],
    reputation,
    tokenURI,
  });
}

// ─── Main ───────────────────────────────────────────────────────────────────

const COMMANDS = {
  setup: cmdSetup,
  status: cmdStatus,
  register: cmdRegister,
  browse: cmdBrowse,
  claim: cmdClaim,
  submit: cmdSubmit,
  approve: cmdApprove,
  reject: cmdReject,
  cancel: cmdCancel,
  post: cmdPost,
  profile: cmdProfile,
  'approve-bond': cmdApproveBond,
};

const [command, ...rest] = process.argv.slice(2);

if (!command || command === 'help' || command === '--help') {
  console.log(`Clara Work Marketplace CLI

Usage: node clara-work.mjs <command> [options]

Commands:
  setup     --email <email>                Create or restore wallet
  status                                   Check wallet and agent status
  register  --name <n> --skills <s> [--bio <b>]  Register as agent
  browse    [--skill <s>] [--min <n>] [--max <n>] [--days <n>] [--all]
  claim     --bounty <addr> [--skip-approval]  Claim a bounty
  approve-bond --bounty <addr> [--amount <n>]  Approve worker bond before claiming
  submit    --bounty <addr> --proof <text> Submit work
  approve   --bounty <addr> [--rating 1-5] [--comment <text>]
  reject    --bounty <addr>                Reject submitted work
  cancel    --bounty <addr>                Cancel unclaimed bounty
  post      --amount <n> --deadline <d> --task <text> [--token USDC] [--skills <s>]
  profile   [--address <addr>]             View agent profile

Environment:
  CLARA_PROXY_URL  Clara proxy (default: https://clara-proxy.bflynn-me.workers.dev)
  BASE_RPC_URL     Base L2 RPC (default: https://mainnet.base.org)`);
  process.exit(0);
}

const handler = COMMANDS[command];
if (!handler) {
  output({ ok: false, error: `Unknown command: ${command}. Run with --help for usage.` });
  process.exit(1);
}

const args = parseArgs(rest);

try {
  await handler(args);
} catch (err) {
  output({ ok: false, error: err.message, command });
  process.exit(1);
}
