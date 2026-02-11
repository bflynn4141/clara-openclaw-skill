# HEARTBEAT.md - High Signal Only

## Rules
- **Working hours only:** 8am–11pm PT. Outside these hours, reply HEARTBEAT_OK unless genuinely urgent (e.g. security alert, server down).
- **Don't repeat yourself.** If I already notified Brian about something, don't mention it again next heartbeat.
- **Rotate checks.** Pick 1-2 per heartbeat to keep token usage low.
- **Only message if actionable.** No "all clear" messages. If nothing needs attention, reply HEARTBEAT_OK.

## Rotation Schedule (pick 1-2 per heartbeat)

### A. Morning Block (8:30am-12pm)
- Check calendar for next 4 hours
- Scan email for urgent items only
- Verify no double-bookings

### B. Midday Block (12pm-4pm)
- Pre-lunch: Any meetings after lunch?
- Email triage (investors, team, urgent only)
- Check if morning action items were handled

### C. Evening Block (4pm-8pm)
- Tomorrow's calendar prep
- End-of-day email summary (only if >3 important unread)
- Any lingering todos from today

## Checks

### Email (High Signal Only)
Scan `bflynn.me@gmail.com` and `brian@boost.xyz` for:
- Urgent/priority flagged emails
- Investors (Neynar, Syndicate, Reverie)
- Team leads
- Keywords: "urgent", "asap", "action required", "deadline"
- Skip: newsletters, promotions, forums, social, auto-replies

If something needs attention: brief iMessage summary to +15167218042

### Calendar (High Signal Only)
- Check upcoming events in next 2-3 hours
- Flag: meetings you might not know about, conflicts, changes since last check
- No alerts for routine standups you already know about

### Smart Reminders
- 15 min before meetings (only if not obvious)
- End-of-block summaries (only if there's something to report)

## Tracking File
Read/write `memory/heartbeat-state.json` to track:
- Last check times per category
- Already-notified items (deduplication)
- Pending action items

### Expense Tracking (1x daily, evening block)
Scan emails for spending receipts and log to Google Sheet.

**Sources to scan:**
- `from:doordash no-reply@doordash.com` — delivery receipts (extract restaurant, total, tip)
- `from:uber receipts@uber.com` — rides and Uber Eats
- `from:chime alerts@account.chime.com subject:"payment/transfer"` — Chime transfers (amounts are in HTML images, extract what you can)
- `from:ally` — Ally Bank transactions/alerts

**What to log (append to Google Sheet "Expense Tracker 2026"):**
- Date, Merchant/Description, Amount, Category (Food Delivery, Transport, Transfer, Groceries, Other)
- Spreadsheet ID: 1GycucUsi-Frcov8ytSc6xKGIAp--vybu4ZroYWbMDj0

**Weekly summary (Sunday evening):**
- Total spend by category
- DoorDash/Uber count and total
- iMessage Brian with a brief breakdown

## Not Yet Connected (add when available)
- Weather (for outdoor meetings)
- GitHub (PRs, issues on Clara/ERC8004)
- Blogwatcher (crypto/AI news)
