# Smart Notifications - High Signal Only

## Philosophy
- **No noise**: Only actionable, time-sensitive, or genuinely useful info
- **No repetition**: Never notify about the same thing twice
- **Batch where possible**: Combine related checks
- **Respect deep work**: Only interrupt during blocks for true urgency

## Notification Tiers

### 🔴 Tier 1: Interrupt Immediately
- Calendar conflict detected
- Urgent email from key contacts (investors, team, partners)
- Security alerts
- System failures

### 🟡 Tier 2: Between Work Blocks (8:30am, 12pm, 4pm)
- Meeting reminders (15 min before)
- Email digest (3-5 items max, filtered for importance)
- Calendar changes since last check

### 🟢 Tier 3: End of Day / Batch
- Daily summary (only if there's something worth knowing)
- Tomorrow's prep
- Unusual patterns (expenses, calendar gaps, etc.)

## Current Active Cron Jobs

| Time | Task | Channel |
|------|------|---------|
| 7:00am | Morning jazz + todo list | iMessage |
| 3:00pm | Email action items reminder | iMessage |
| 8:30am | Pre-work block briefing (planned) | iMessage |
| 11:45am | Lunch break heads-up (planned) | iMessage |
| 3:45pm | EOD prep (planned) | iMessage |

## Anti-Noise Rules

1. **Email filtering**:
   - Skip: newsletters, promotions, forums, social, auto-replies
   - Flag: investors, team leads, urgent keywords, direct mentions
   
2. **Calendar**:
   - Only alert on changes or meetings you might miss
   - No alerts for routine/recurring blocks

3. **Research/monitoring**:
   - Batch updates (daily or weekly, not per-item)
   - Only surface truly interesting findings

## Key Contacts (Auto-Prioritize)
- Investors: Neynar updates, Syndicate, Reverie
- Team: Boost standup reminders, product/design syncs
- Partners: Christian Onalfo (RabbitHole residual)

## Next Improvements

1. Add blogwatcher for crypto/AI news monitoring
2. Add weather for meeting days (outdoor events)
3. Add GitHub PR notifications for Clara/ERC8004
4. Add expense tracking alerts (unusual spending)

---
*Last updated: 2026-02-10*
