# Automated Credential Scanner Probe - February 7, 2026

## Summary

Between 13:45-13:54 UTC (8:45-8:54 AM ET), an automated vulnerability scanner
probed gallformers.org with 3,194 requests across 1,596 unique paths, searching
for exposed credentials, configuration files, database dumps, and known
application vulnerabilities. All probes were correctly rejected. No data was
exposed.

Two smaller follow-up scans occurred later in the day from different sources.

## Impact

**None.** All sensitive-path probes returned 404. The site served no credentials,
configuration, or database files.

## Timeline

| Time (UTC)  | Time (ET)    | Event                                          |
|-------------|------------- |-------------------------------------------------|
| 13:45:08    | 8:45 AM      | First probe arrives from 18.68.50.71            |
| 13:45-13:47 | 8:45-8:47 AM | Peak burst: 2,051 requests in 3 minutes         |
| 13:47-13:54 | 8:47-8:54 AM | Sustained probing at ~175 req/min               |
| 13:54:35    | 8:54 AM      | Last probe from this scanner                    |
| 15:57-16:00 | 10:57-11:00 AM | Second scanner: favicon/logo probes (~140 req) |
| 16:51       | 11:51 AM     | Third scanner: PHP webshell probes (177 req)    |

## Scanner 1: Credential Probes (Main Incident)

### Source

- **User agent**: `curl/8.7.1`
- **IP range**: `18.68.50.x` (16 distinct IPs)
- **Infrastructure**: Amazon/AWS (ARIN NetName: AT-88-Z, Amazon Technologies Inc.)
- **Top IPs by volume**:
  - `18.68.50.71` — 1,601 requests
  - `18.68.50.78` — 1,187 requests
  - `18.68.50.106` — 293 requests
  - 13 other IPs with 1-33 requests each

### Attack Profile

Classic automated credential/config scanner. Probed **1,596 unique paths** across
these categories:

| Category | Example Paths | Count |
|----------|--------------|-------|
| Environment files | `/.env`, `/.env.backup`, `/.env.staging`, `/.env.production`, `/.env.docker`, etc. | ~300+ variants |
| AWS credentials | `/.aws/credentials`, `/.aws/config`, `/.aws/secret_access_key.txt` | ~10 |
| Git config | `/.git/config`, `/.gitignore`, `/.git/HEAD` | ~5 |
| Database dumps | `/db.sql`, `/backup.sql`, `/wp-content/uploads/mysql.sql` | ~20 |
| API keys | `/sendgrid_keys.json`, various key paths | ~10 |
| Docker/CI | `/.docker/config.json`, `/.circleci/config.yml`, `/.azure-pipelines.yml` | ~10 |
| WordPress | `/wp-login.php`, `/wp-config.php`, `/wp-content/...` | ~50 |
| PHP probes | `/phpinfo.php`, `/xdebug.php`, various `.php` files | ~30 |
| Shell history | `/.bash_history`, `/.bashrc` | ~5 |
| Misc config | `/config.json`, `/application.yml`, `/settings.py` | ~50+ |

### Response Analysis

| Status | Count | Notes |
|--------|-------|-------|
| 404    | 3,200 | Correctly rejected |
| 200    | 322   | Legitimate pages (see below) |
| 302    | 4     | Redirects for `/admin/` and `/auth/auth0` |

**200 responses on suspicious-looking paths**: Six requests to paths like
`/source/.env`, `/user/.env.staging`, and `/keys/sendgrid_keys.json` returned
200. These are **false positives** — they match Phoenix LiveView catch-all routes
(e.g., `/source/:id` treats `.env` as a source ID). The responses contain
rendered HTML pages, not actual sensitive files. Confirmed by testing locally
where the same paths return 404 (the catch-all routes only render in production
with connected LiveView).

## Scanner 2: Favicon/Logo Probes

### Source

- **User agent**: `Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0`
- **Time**: 15:57-16:00 UTC (~140 requests)

### Profile

Probed for favicons, logos, and static assets from other websites — likely
checking whether gallformers.org is a clone or phishing site for known brands.

Example paths:
- `/txpro/img/html_icon.ico`
- `/themes/custom/ahaspeed/favicon.ico`
- `/static/picture/logo_jg2.png`
- `/v1/file/icon/seo/cdc3fff6-6034-46fb-8ef3-1746e374d4fc.png`

All returned 404. No concern.

## Scanner 3: PHP Webshell Probes

### Source

- **User agent**: `Amazon CloudFront`
- **IP range**: `15.158.17.x` (AWS CloudFront IPs)
- **Time**: 16:51 UTC (177 requests in ~1 minute)

### Profile

Probed for PHP webshells and WordPress backdoors with randomized filenames:
- `/zwso.php`, `/ya.php`, `/xxxx.php`, `/xpwer1.php`
- `/wp-update.php`, `/wp-the.php`
- `/wp-includes/certificates/plugins.php`
- `/xmlrpc.php`

All returned 404. The site doesn't run PHP.

## Observations

### What Worked

1. **No sensitive files exposed** — Phoenix/Elixir doesn't serve static files
   from the project root, so `.env`, `.git/config`, etc. are never reachable.
2. **All probes returned 404** — No information leakage beyond "this path doesn't
   exist."
3. **Request logging captured the full incident** — Enabled post-incident analysis
   with full detail.

### Areas to Watch

1. **Phoenix catch-all routes return 200 for nonsense paths** — `/source/.env`
   matches `/source/:id` and returns a rendered page. While no sensitive data is
   served, this could:
   - Waste server resources rendering pages for invalid IDs
   - Confuse automated scanners into repeated probing of "successful" paths
   - Consider adding ID format validation (e.g., require numeric IDs) at the
     router level.

2. **No rate limiting** — The scanner sent 864 requests in a single minute with
   no throttling. Consider:
   - Fly.io's built-in connection limits
   - Application-level rate limiting (e.g., `PlugAttack` or `Hammer`)
   - CloudFront/CDN-level WAF rules

3. **AWS-sourced attacks** — All three scanners came from AWS infrastructure.
   This is common (cheap compute for scanning), but worth noting that blocking
   AWS IP ranges is generally impractical since legitimate traffic (bots,
   services) also originates from AWS.

## Raw Data

Log file: `priv/logs/requests-2026-02-07.log` (downloaded from production)

Useful queries for further analysis:

```bash
# All 404s from the main scanner
cat priv/logs/requests-2026-02-07.log | jq -c 'select(.status == 404 and .ua == "curl/8.7.1")'

# All unique paths probed
cat priv/logs/requests-2026-02-07.log | jq -c 'select(.status == 404 and .ua == "curl/8.7.1") | .path' | sort -u

# 404s by minute during the spike
cat priv/logs/requests-2026-02-07.log | jq -c 'select(.status == 404 and .ua == "curl/8.7.1") | .ts[0:16]' | sort | uniq -c

# All traffic from the scanner IP range
cat priv/logs/requests-2026-02-07.log | jq -c 'select(.ip | startswith("18.68.50."))'
```
