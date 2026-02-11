# OpenClaw Setup Research: Best Practices & Patterns

## Research Scope
Analyzed OpenClaw documentation and automation patterns to identify improvements for Brian's setup.

---

## Key Patterns from Documentation

### 1. Heartbeat vs Cron: Optimization Strategy

**Current Brian Setup:**
- ✅ Morning briefing (8:30am) - Cron ✓
- ✅ Pre-lunch heads-up (11:45am) - Cron ✓  
- ✅ EOD prep (3:45pm) - Cron ✓
- ✅ AMM Challenge daily update (9am) - Cron ✓

**Recommendation:** Add HEARTBEAT.md batching for background checks

**What to Add:**
```markdown
# HEARTBEAT.md - Batched Checks (every 30 min during work hours)

Rotate through (pick 1-2 per heartbeat):
- Email scan (urgent only)
- Calendar check (upcoming events)
- GitHub PRs (Clara/ERC8004)
- Expense tracking (receipts)
- Blogwatcher updates

Only message if actionable. HEARTBEAT_OK if clear.
```

**Benefits:**
- Batches 5+ checks into 1 agent turn (saves tokens)
- Context-aware prioritization
- Natural drift acceptable for monitoring

---

### 2. Cron Best Practices (From Docs)

**Current Usage:** Correct
- Isolated sessions for standalone tasks ✓
- Main session only for system events ✓
- Delivery to iMessage ✓

**Improvements to Consider:**

| Current | Improvement |
|---------|-------------|
| Fixed schedule | Add `--delete-after-run` for one-shots |
| Single model | Override with cheaper model for simple tasks |
| Always announce | Use `--mode none` for silent tasks |

**Example: Cheaper Model for Simple Checks**
```json
{
  "name": "Morning briefing",
  "model": "anthropic/claude-sonnet-4", // Cheaper than Kimi
  "schedule": { "kind": "cron", "expr": "30 8 * * *" }
}
```

---

### 3. Gmail Pub/Sub Integration (Advanced)

**From docs:** Real-time email alerts via Gmail webhooks

**Setup for Brian:**
- Enable Gmail push notifications
- Get real-time alerts for urgent emails
- Avoid polling overhead

**Benefits:**
- Instant alerts vs 30-min heartbeat polling
- Better for time-sensitive investor/team emails

---

### 4. Webhook Automation

**From docs:** External services can trigger agent via webhooks

**Ideas for Brian:**
- GitHub webhooks → PR summaries
- Vercel deploy alerts → notifications  
- Crypto price alerts (via Zapier/webhook)

**Setup:**
```json
{
  "hooks": {
    "mappings": [{
      "match": { "path": "/github-pr" },
      "action": "agent",
      "messageTemplate": "New PR on {{repo}}: {{title}}",
      "channel": "imessage",
      "to": "+15167218042"
    }]
  }
}
```

---

### 5. Sub-Agent Specialization

**Current:** AMM Challenge expert agent spawned ✓

**Expand to:**
- **Research agent** - Deep research tasks, web browsing
- **Email agent** - Draft responses, triage
- **Coding agent** - Clara/ERC8004 work
- **Crypto agent** - Portfolio monitoring, Bankr operations

**Benefits:**
- Isolated context per domain
- Different models/thinking levels per task
- Parallel execution

---

### 6. Memory Management

**Current Setup:**
- ✅ Local embeddings (privacy-first) ✓
- ✅ MEMORY.md for curated memory ✓
- ✅ Daily notes in memory/YYYY-MM-DD.md ✓

**Improvements:**
- Add `sessionMemory: true` for transcript indexing
- Configure hybrid search (vector + BM25)
- Set up memory sync intervals

---

### 7. Browser Automation (In Progress)

**Current:** Headless Brave browser configured ✓

**Use Cases to Add:**
- Form submissions (AMM Challenge, etc.)
- Research (navigate + extract)
- Competitive monitoring
- Account creation/management

**Blockers to Resolve:**
- X account creation (anti-bot)
- CAPTCHA handling
- 2FA flows

---

## Specific Recommendations

### High Priority (This Week)

1. **Add Brave Search API to 1Password**
   - Enables web search for research
   - Unlocks proactive research capabilities

2. **Set up HEARTBEAT.md batching**
   - Combine email + calendar + GitHub checks
   - Reduces token usage
   - More context-aware

3. **Configure Gmail Pub/Sub**
   - Real-time urgent email alerts
   - Better than polling for time-sensitive stuff

### Medium Priority (Next 2 Weeks)

4. **GitHub Integration**
   - Webhooks for PRs/issues
   - Sub-agent for code review
   - Daily summaries

5. **Expense Tracking Automation**
   - Scan emails for receipts
   - Auto-log to Google Sheets
   - Weekly summaries

6. **Apple Notes Skill**
   - Personal knowledge base
   - Meeting notes integration

### Long Term (Month 2+)

7. **Multi-Agent Setup**
   - Research agent with web browsing
   - Coding agent for side projects
   - Crypto agent for portfolio

8. **Voice Integration**
   - ElevenLabs TTS for summaries
   - Voice commands via OpenClaw Talk

9. **Advanced Browser Automation**
   - Solve CAPTCHA challenges
   - 2FA handling
   - Full autonomous submission

---

## Comparison: Brian's Setup vs Best Practices

| Area | Current | Best Practice | Gap |
|------|---------|---------------|-----|
| **Scheduling** | Cron-heavy | Cron + Heartbeat mix | Add HEARTBEAT.md |
| **Email** | Polling via gog | Pub/Sub webhooks | Set up push |
| **Memory** | Local embeddings | Hybrid search | Configure BM25 |
| **Agents** | 1 main + 1 sub | Multi-specialized | Add 2-3 more |
| **Browser** | Headless ready | Full automation | Solve auth/CAPTCHA |
| **Secrets** | 1Password CLI | Auto-inject via op | Add API keys |

---

## Research Sources

- OpenClaw docs: `/automation/cron-jobs.md`
- OpenClaw docs: `/automation/cron-vs-heartbeat.md`
- OpenClaw docs: `/automation/gmail-pubsub.md`
- OpenClaw docs: `/automation/hooks.md`
- OpenClaw docs: `/tools/browser.md`

---

## Next Actions

1. ✅ Documented current state
2. ⏳ Add Brave Search API key to 1Password
3. ⏳ Create HEARTBEAT.md with batched checks
4. ⏳ Set up Gmail Pub/Sub for real-time email
5. ⏳ Spawn research agent for deeper investigation

---

*Research completed: 2026-02-10*
