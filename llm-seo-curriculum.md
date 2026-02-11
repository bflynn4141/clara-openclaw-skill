# LLM SEO Crash Course - 14-Day Curriculum

Brian is learning LLM SEO (Generative Engine Optimization). Deliver one lesson per day at noon via Telegram. Each lesson should be **bite-sized** (3-5 min read), **conversational** (you're his study partner, not a textbook), and include a **daily micro-task** that builds toward the Week 1-2 project.

## The Project: Multi-Platform AI Audit

Over 14 days, Brian will audit how LLMs recommend brands in a niche he picks. By Day 14, he'll have a complete analysis of how ChatGPT, Perplexity, Claude, and Google AI Overviews differ in what they cite and why.

---

## Day 1: Why LLM SEO Exists
**Concept:** AI search traffic grew 1,200% in one year. 60% of searches now result in zero clicks — the AI just answers. If your content isn't in the AI's answer, you're invisible.
**Key stat:** AI search visitors convert 4.4x better than traditional organic.
**The shift:** Traditional SEO = rank on Google. LLM SEO = get cited when someone asks ChatGPT a question.
**Micro-task:** Pick a niche you're curious about (crypto tools, productivity apps, running shoes, whatever). Write it down. Tomorrow we'll use it.

## Day 2: The Three Knowledge Pathways
**Concept:** LLMs have 3 ways to "know" things:
1. **Parametric** — baked into training data. 60% of ChatGPT queries use ONLY this. No search, no retrieval.
2. **RAG (Retrieval-Augmented Generation)** — semantic vector search + keyword matching to pull relevant docs.
3. **Web search grounding** — live crawling via bots (OAI-SearchBot, PerplexityBot, ClaudeBot, etc.)
**Why it matters:** Most people only optimize for #3 (web search). But #1 is where 60% of answers come from. Getting into training data = being a recognized, authoritative entity.
**Micro-task:** Ask ChatGPT (no web search) and Perplexity the same question about your niche: "What are the best [tools/brands] for [your niche]?" Screenshot both answers. Notice how different they are.

## Day 3: What Actually Gets Cited (The Data)
**Concept:** Analysis of 5.7 million LLM citations reveals who gets cited most:
- Reddit: 40.1%
- Wikipedia: 26.3%
- Google/YouTube: 23%
- LinkedIn, StackOverflow: significant
**Content signals that boost citations:**
- Statistics in your content → +22%
- Direct quotations → +37%
- Self-contained chunks of 50-150 words → 2.3x more citations
- Semantic URLs (5-7 descriptive words) → +11.4%
- Citing authoritative sources yourself → +132% visibility
**Key insight:** The #1 predictor of being cited isn't backlinks — it's brand search volume.
**Micro-task:** Look at your Day 2 screenshots. Which brands got mentioned? Google each one — how old is their domain? How many platforms are they on? Start a simple spreadsheet tracking: Brand, Mentioned by ChatGPT (Y/N), Mentioned by Perplexity (Y/N), Domain Age, Platforms Present On.

## Day 4: The GEO Paper (Part 1)
**Concept:** The foundational academic paper is "GEO: Generative Engine Optimization" from Princeton (KDD 2024). Read the abstract and introduction: https://arxiv.org/abs/2311.09735
**Key findings:**
- GEO optimizations can increase visibility by up to 40%
- Citing sources in your content → +115% visibility for lower-ranked sites
- These effects are **domain-dependent** — what works in health content differs from e-commerce
- The paper introduces GEO-bench, a benchmark for testing optimization strategies
**Why this paper matters:** It's the first rigorous academic framework. Everything else in the industry builds on this.
**Micro-task:** Skim the GEO paper abstract and Section 1 (Introduction). Write down one thing that surprised you. Share it with me — I want to discuss it.

## Day 5: The GEO Paper (Part 2) — The 7 Techniques
**Concept:** The GEO paper tested 9 optimization methods. Here's what worked:
1. **Cite Sources** — Add "[according to X]" references → biggest impact
2. **Add Statistics** — Concrete numbers, percentages, data points
3. **Add Quotations** — Expert quotes give weight
4. **Fluency Optimization** — Clear, well-structured writing
5. **Unique Words** — Distinctive vocabulary (not keyword stuffing)
6. **Technical Terms** — Domain-appropriate jargon when warranted
7. **Authoritative Tone** — Confident, definitive statements
What DIDN'T work well: keyword stuffing, generic filler.
**Micro-task:** Find a blog post or article from one of the brands in your audit. Score it 1-5 on each of the 7 techniques above. Does the score correlate with whether LLMs cite this brand?

## Day 6: How Each Platform Sources Differently
**Concept:** This is critical — there's no single optimization target:
- **ChatGPT:** Parametric-first. Favors Wikipedia (47.9%). Only searches when it decides to.
- **Perplexity:** Retrieval-first. Every answer has citations. Favors Reddit. Built for research.
- **Google AI Overviews:** Leverages existing search index + Gemini. Needs cosine similarity >0.88 for selection.
- **Claude:** Parametric-first. Decides autonomously when to search. Favors clarity and relevance.
**Micro-task:** Ask all 4 platforms the exact same question about your niche. Add Claude and Google AI Overviews to your spreadsheet. For each platform, note: How many sources cited? Which sources? Does it recommend the same brands?

## Day 7: PROJECT CHECK-IN — Pattern Analysis
**Concept:** Mid-point reflection. By now you have data from 4 platforms across multiple queries.
**Analysis questions:**
1. Which brands appear on ALL platforms? (These have strong parametric presence)
2. Which only appear on Perplexity? (These are good at being crawlable/recent but weak on authority)
3. Which only appear on ChatGPT? (These have strong training data presence, probably old/authoritative)
4. Do any platforms cite the SAME source URL?
**Micro-task:** Write a 1-paragraph summary of patterns you've noticed. What's your #1 hypothesis about what makes a brand "LLM-visible"? Send it to me.

## Day 8: Traditional SEO vs LLM SEO
**Concept:** LLM SEO doesn't replace traditional SEO — it layers on top. The "Authority Flywheel" (IDX research) shows brands winning in LLM results invested in SEO first.
**Key differences:**
| Traditional | LLM |
|---|---|
| Keywords | Semantic meaning |
| Backlinks | Brand authority |
| Click-through | Zero-click citations |
| SERP position | Share of voice |
| Page-level | Entity-level |
**The prerequisite:** Strong technical SEO health, structured data, and authority signals are the bedrock. LLM optimization amplifies what's already there.
**Micro-task:** Pick the #1 brand from your audit (most cited across platforms). Check their robots.txt — do they allow AI crawlers? Check if they have an llms.txt file. Check their schema markup (use Google's Rich Results Test).

## Day 9: The Technical Stack — llms.txt, Crawlers, Schema
**Concept:** The technical side of LLM SEO:
- **llms.txt** — Markdown file at domain root telling AI systems about your best content. 844k+ sites use it (Anthropic, Cloudflare, Stripe). BUT: no AI platform has confirmed reading it.
- **robots.txt for AI** — Allow: OAI-SearchBot, PerplexityBot, ClaudeBot, Google-Extended, Applebot-Extended
- **Schema markup** — Article, FAQPage, HowTo, Product schemas help AI understand content structure
- **Semantic URLs** — 5-7 descriptive words → +11.4% citations
**Warning:** In Dec 2025, OpenAI quietly removed language saying ChatGPT-User would comply with robots.txt. Only OAI-SearchBot and GPTBot confirmed.
**Micro-task:** Check 3 more brands from your audit for: robots.txt AI bot rules, llms.txt presence, schema markup. Add this to your spreadsheet. Do the technically-optimized brands get more citations?

## Day 10: Content Architecture for Extraction
**Concept:** LLMs don't read your whole page — they extract chunks. Your content should be a database of extractable answers.
**The rules:**
- Self-contained passages of 100-300 tokens (75-225 words)
- Each chunk should fully answer a question on its own
- Content scoring 8.5/10+ on semantic completeness → 4.2x more likely to be cited
- Comparison content (best, top, vs, alternatives) → ~1/3 of all LLM mentions
- Freshness: content older than 3 months sees significant citation drops
**Micro-task:** Take one highly-cited piece of content from your audit. Break it into chunks. Which chunks would an LLM extract? Are they self-contained? Could you answer a user's question with just that chunk?

## Day 11: Brand Authority and Entity Strength
**Concept:** The strongest predictor of LLM citation is brand authority (0.334 correlation). This means:
- Average domain age of cited sources: 17 years
- Multi-platform presence across 4+ channels
- Brand search volume matters more than backlinks
- Consistent signals across Reddit, Wikipedia, YouTube, LinkedIn, StackOverflow
**The uncomfortable truth:** You can't hack this. It takes time to build genuine authority. BUT you can accelerate by being present on the platforms LLMs cite most.
**Micro-task:** For your top 3 audited brands, search for them on Reddit, YouTube, LinkedIn. How present are they? Do they have active communities? Does community presence correlate with LLM citation?

## Day 12: Measurement and Tools
**Concept:** How to measure LLM visibility:
- **Free:** HubSpot AEO Grader, Am I Cited
- **Paid:** Peec AI, Profound, Evertune, Goodie AI, Semrush AI Visibility
- **Key metrics:** Share of voice, citation frequency, AI brand score, perception drift
- **The challenge:** No standard metrics yet. The field is <18 months old.
**Perception Drift:** Your brand's LLM visibility can swing wildly month-to-month as models retrain. You need ongoing monitoring, not one-time optimization.
**Micro-task:** Run your top brand through HubSpot's AEO Grader (free). What score does it get? Does the score match your manual audit findings?

## Day 13: Open Questions and Challenges
**Concept:** What makes this field hard and interesting:
- 50-90% of LLM citations aren't fully supported by cited sources
- Zero-click economics: your content powers AI answers but you may get zero traffic
- Brand hallucination risk: LLMs can fabricate facts about your brand
- Domain-specific variation: no universal playbook
- Citation accuracy is poor — models often cite sources that don't fully support what they say
**The opportunity:** Because this is early and messy, expertise is rare. Understanding these challenges IS the competitive advantage.
**Micro-task:** Test citation accuracy. Take 3 citations from Perplexity's answer about your niche. Click through to the sources. Does the source actually say what Perplexity claims? Document the accuracy rate.

## Day 14: PROJECT WRAP-UP — Write Your Analysis
**Concept:** Synthesize everything into a deliverable.
**Your final output should include:**
1. **Niche overview** — What niche did you audit? Why?
2. **Platform comparison matrix** — Which brands get cited where? With what sources?
3. **Pattern analysis** — What do the most-cited brands have in common? (domain age, platform presence, content structure, technical setup)
4. **Citation accuracy findings** — How reliable are the citations?
5. **Your hypothesis** — If you were advising a brand in this niche on LLM SEO, what 3 things would you tell them to do first?
**Micro-task:** Write the analysis (even if rough). This is your first LLM SEO artifact. It's also content that demonstrates expertise — which is itself a form of LLM SEO.

---

## Delivery Instructions for Gia

When delivering each day's lesson:
1. Read this file to find the current day's lesson (start Day 1 on Feb 11, 2026)
2. Deliver the lesson in a conversational, engaging tone — you're a study partner, not a textbook
3. Include the concept, key stats, and micro-task
4. Reference previous days' work when relevant ("remember what you found on Day 2?")
5. Keep it bite-sized: 3-5 minutes to read, max
6. End with the micro-task and encourage Brian to share his findings
7. If Brian has shared findings from a previous day, acknowledge and build on them
8. Use the day number to calculate which lesson: Day = (current_date - 2026-02-10) so Feb 11 = Day 1, Feb 12 = Day 2, etc.

## Key Resources
- GEO Paper: https://arxiv.org/abs/2311.09735
- Digital Bloom 2025 AI Visibility Report: https://thedigitalbloom.com/learn/2025-ai-citation-llm-visibility-report/
- HubSpot AEO Grader: https://www.hubspot.com/aeo-grader
- Visual Capitalist citation data: https://www.visualcapitalist.com/ranked-the-most-cited-websites-by-ai-models/
