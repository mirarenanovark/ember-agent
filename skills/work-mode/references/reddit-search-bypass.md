# Reddit search without reddit.com access (validated 2026-09-02)

## Context
reddit.com/old.reddit 403 from tortuga AND rena VPS. Task class: "search reddit
for X" — brand mentions, sentiment, discussion discovery.

## Primary: Arctic Shift API (no auth)
Base: https://arctic-shift.photon-reddit.com

- Post search: `/api/posts/search?subreddit=S&limit=100&after=EPOCH&fields=id,title,created_utc,score,subreddit,selftext`
- Comments: `/api/comments/search?link_id=<id>&fields=body`
- Lookup: `/api/posts/ids?ids=<id>`

### Param rules (current as of 2026-09-02)
- `permalink` and `author` in fields= → HTTP 400 (API decayed; both used to work).
  Construct links from `id`: https://reddit.com/r/<sub>/comments/<id>.
- `title=X` filter REQUIRES `subreddit` (or author) alongside.
- 525 = server throttle → sleep 5-10s, retry (up to 3x).
- POST to /api/posts/search → 404. GET only.
- Pagination: `after=<epoch>`; take min(created_utc) of page as next `after`.

### Mention-scan recipe (45d, ~1,700 posts across 11 subs in ~2 min)
```python
subs = ["LocalLLaMA","claudeai","ChatGPTCoding","OpenAI","ollama",
        "selfhosted","AI_Agents","vibecoding","mcp","ClaudeCode"]
after = now - 45*86400
for sub in subs:
    for page in range(4):  # 100/page → up to 400/sub
        fetch(f"...?subreddit={sub}&limit=100&after={a}&fields=id,title,created_utc,score,subreddit,selftext")
        if len(posts)<100: break
        a = min(p['created_utc'] for p in posts); sleep(3)
hits = [p for p in all if needle in (title+' '+selftext).lower()]
```
User-Agent "mira-research/1.0"; sleep 3-4s between sub fetches.

## Cross-check: Bing scraping (keyless)
Arctic Shift only covers indexed subs/history — cross-check with a web search:
- DDG html/lite endpoints → anomaly/captcha wall from tortuga. Dead end, skip.
- Bing works: GET `https://www.bing.com/search?q=<q>+site:reddit.com&setlang=en&cc=US`
  with Chrome UA + `Accept-Language: en-US`. Parse `<li class="b_algo">` →
  `<h2><a href="...">TITLE</a>` (hrefs are bing redirect wrappers; titles are clean).
- hermes web_search backend can return 0 results on queries Bing answers —
  verify an "empty" result set against Bing before reporting zero.
- zai-search MCP: web_search 429s without balance; web_reader 404s. Don't burn turns.

## Case study: "9router" (2026-09-02)
~1,700 posts / 11 AI subs / 45d → ONE mention: r/ollama 2026-09-02, author runs
3 Ollama Pro accounts through 9router as multi-account round-robin (42k requests,
3.62B input tokens/50d). Conclusion pattern: 27k GitHub stars but no Reddit
community yet — star-vs-discussion mismatch = tutorial-driven adoption signal.
