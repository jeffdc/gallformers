# V1→V2 Cutover Execution Plan

**Date:** Tuesday, February 4, 2026
**Start Time:** 10:00 AM Eastern
**Operator:** Jeff (solo)
**Estimated Duration:** 1-2 hours active work + 1-2 hours monitoring
**Rollback Window:** 7 days (DO droplet stays running)

## Overview

**Current State:**
- V1 (Next.js) running on DO droplet at 157.245.243.86
- V2 (Phoenix) running on Fly.io at gallformers.fly.dev
- DNS points to DO: gallformers.org → 157.245.243.86
- CloudFront V2 ready at dfd18lb16qtjl.cloudfront.net
- ACM certificate validated: arn:aws:acm:us-east-1:885187511538:certificate/b6597ed2-26c9-4134-9c72-1d7a419c939a
- Database: ~50MB SQLite with orphaned records needing cleanup

**Target State:**
- DNS points to CloudFront V2: gallformers.org → dfd18lb16qtjl.cloudfront.net
- CloudFront routes to Fly.io with maintenance page fallback
- Clean, compacted database on Fly.io
- V1 stays running as rollback option

**Critical Blockers (must be ready by 10 AM):**
- ✅ V1 edit-disable deployed (prevents data loss)
- ⏳ Database upload solution working (custom implementation)
- ⏳ Auth0 callback URLs added (pre-cutover task)

---

## Section 1: Pre-Cutover Preparation (Before 10 AM)

### T-24 hours (Today - February 3)

**1. Lower DNS TTL at DigitalOcean**
- Set TTL to 300 seconds (5 min) for all records:
  - gallformers.org A record
  - www.gallformers.org CNAME
  - gallformers.com A record
  - www.gallformers.com CNAME
- Allows fast rollback if needed
[x] DONE at 1900 ET Feb 3

**2. Document current DNS configuration**
- Screenshot all DNS records at DigitalOcean
[x] DONE at 1905PM ET Feb 3
- Record DO droplet IP: 157.245.243.86
[x] DONE at 1906PM ET Feb 3
- Save for rollback reference

**3. Update Auth0 (gallformers-59gg)**
- Log into Auth0 dashboard
- Add V2 callback URLs:
  - `https://gallformers.org/auth/callback`
  - `https://www.gallformers.org/auth/callback`
  - `https://gallformers.com/auth/callback`
  - `https://www.gallformers.com/auth/callback`
- Add V2 logout URLs (same domains, check Phoenix auth config for exact path)
- **Keep all V1 URLs** - don't remove until V1 shutdown
- Test auth on gallformers.fly.dev
[x] DONE at 1946PM ET Feb 3

**4. Finalize database upload solution**
- Custom Fly.io approach must be tested and ready
- Document the exact commands/steps for tomorrow
[x] DONE at 1950PM ET Feb 3


**5. Update gallformers-status page (gallformers-c53r)**
- Post scheduled maintenance notice
- "Scheduled maintenance February 4, 10 AM-12 PM Eastern"
[x] DONE at 2005PM ET Feb 3

### T-0 (Tomorrow morning, before 10 AM start)

**6. Deploy V1 edit-disable**
- Deploy to DO droplet
- Verify editing is blocked on live site
- This prevents data loss during cutover
[x] DONE at 735AM ET Feb 4

---

## Section 2: Database Cleanup & Preparation (10:00-10:30 AM)

### Step 1: Create backup on DO droplet
```bash
ssh user@157.245.243.86
cd /mnt/gallformers_data/prisma/
cp gallformers.sqlite gallformers-pre-cutover-backup-2026-02-04.sqlite
ls -lh gallformers*.sqlite  # Verify backup exists
```

### Step 2: Download database to local machine
```bash
scp user@157.245.243.86:/mnt/gallformers_data/prisma/gallformers.sqlite \
  ~/cutover-working/gallformers-v1-raw.sqlite
```
[x] DONE at 745AM ET Feb 4

### Step 3: Clean up orphaned records
```bash
cp ~/cutover-working/gallformers-v1-raw.sqlite ~/cutover-working/gallformers-v1-clean.sqlite
sqlite3 ~/cutover-working/gallformers-v1-clean.sqlite < /Users/jeff/dev/gallformers/priv/repo/cleanup_orphaned_records.sql
```

**Script location:** `priv/repo/cleanup_orphaned_records.sql`

**What it cleans up:**
- Orphaned galls (no valid gallspecies link):|217
- Orphaned aliases:|8824

**Verification:** The script includes verification queries that run automatically and show remaining orphan counts (all should be 0).
[x] DONE at 846AM ET Feb 4

### Step 4: Run V1→V2 migration
```bash
cp ~/cutover-working/gallformers-v1-clean.sqlite ~/cutover-working/gallformers-v2.sqlite
sqlite3 ~/cutover-working/gallformers-v2.sqlite < /Users/jeff/dev/gallformers/priv/repo/migrate_v1_to_v2.sql
```
[x] DONE at 848AM ET Feb 4

### Step 5: Compact and sync WAL
```bash
sqlite3 ~/cutover-working/gallformers-v2.sqlite "VACUUM;"
sqlite3 ~/cutover-working/gallformers-v2.sqlite "PRAGMA wal_checkpoint(TRUNCATE);"
```
[x] DONE at 848AM ET Feb 4

### Step 6: Verify and checksum
```bash
# Sanity check with Phoenix
DATABASE_PATH=~/cutover-working/gallformers-v2.sqlite iex -S mix phx.server
# Spot check localhost:4000, then shut down (Ctrl+C twice)

# Check file size
ls -lh ~/cutover-working/gallformers-v2.sqlite

It is 14M

# Final checksum
shasum -a 256 ~/cutover-working/gallformers-v2.sqlite > ~/cutover-working/checksum.txt
cat ~/cutover-working/checksum.txt
```

`8c4e2e3fee507cb44a11b250419498d50526dd9240fe3e866cdd2b1925d0115c  /Users/jeff/cutover-working/gallformers-v2.sqlite`
[x] DONE at 850AM ET Feb 4

---

## Section 3: Upload Database to Fly.io (10:30-10:45 AM)

**Use the automated Mix task** - it handles all the complexity safely.

### Single command upload & verification

```bash
cd ~/dev/gallformers
mix gallformers.update_prod_db ~/cutover-working/gallformers-v2.sqlite
```

**What this task does:**
1. ✓ Re-validates local database (integrity + species count ≥ 5000)
2. ✓ Creates clean single-file copy (VACUUM + WAL checkpoint)
3. ✓ Asks for confirmation (type 'REPLACE' to continue)
4. ✓ Stops production machine
5. ✓ Updates machine to sleep mode (releases DB lock)
6. ✓ Starts sleeping machine (DB file no longer in use)
7. ✓ Backs up existing database (timestamped: `/data/gallformers-YYYYMMDD-HHMMSS.sqlite.bak`)
8. ✓ Uploads new database via SFTP
9. ✓ Verifies remote database (integrity + species count match)
10. ✓ Clears Litestream backups (forces fresh generation)
11. ✓ Restarts machine normally (reverts to app command)
12. ✓ Checks health endpoint

**Prerequisites:**
- flyctl CLI (authenticated)
- aws CLI (configured)
- sqlite3
- jq

**Expected duration:** ~5-10 minutes

**On success:**
- Shows species count, file size, SHA-256 checksum
- Backup location for rollback if needed
- Health check confirmation

**On failure:**
- Task offers automatic rollback (restores backup)
- Machine left in sleep mode for investigation
- Clear error messages

**COMPLETED:**
[x] DONE at 905AM ET Feb 4
```
➜  gallformers git:(main) ✗ mix gallformers.update_prod_db ~/cutover-working/gallformers-v2.sqlite
Checking prerequisites...
✓ All prerequisites met

=== Step 1: Local Validation & Preparation ===
Checking source database integrity...
✓ Source integrity check passed
Checking species count...
Species count: 5793
✓ Species count validated

Creating clean copy (VACUUM + WAL checkpoint)...
✓ Clean database created
Verifying clean copy...
✓ Clean copy verified
File size: 14.29 MB
SHA-256: 44427754dba0887f46a997216d9b8be41ed01ed6b57c8c71f5bb94370ca35b0f

WARNING: This will replace the production database on Fly.io
App: gallformers
Species count: 5793
File size: 14.29 MB

The existing database will be backed up with a timestamp.
If anything fails, you can rollback to the backup.

Type 'REPLACE' to continue:  REPLACE

=== Step 2: Get Machine Info ===
Machine ID: 7847515a205e68
Machine state: started

=== Step 3: Stop Machine ===
Stopping machine...
✓ Machine stopped

=== Step 4: Update Machine to Sleep Mode ===
Updating machine command to 'sleep infinity'...
✓ Machine updated to sleep mode

=== Step 5: Start Sleeping Machine ===
Starting machine (will run 'sleep infinity', not the app)...
Waiting for machine to start...
✓ Machine started (DB lock released)

=== Step 6: Backup Existing Database ===
Backup filename: /data/gallformers-20260204-140256.sqlite.bak
No existing database found (fresh install)

=== Step 7: Upload New Database ===
Uploading database (14.29 MB)...
✓ Database uploaded

=== Step 8: Verify Remote Database ===
Checking integrity on remote...
Connecting to fdaa:d:c2ca:a7b:60e:f1fb:2cb5:2...
✓ Remote integrity check passed
Connecting to fdaa:d:c2ca:a7b:60e:f1fb:2cb5:2...
Remote species count: 5793
✓ Remote species count matches

=== Step 9: Clear Litestream Backups ===
Clearing Litestream backups from S3 (forces fresh generation)...
✓ Litestream backups cleared

=== Step 10: Restore Normal Operation ===
Clearing command override (reverts to Dockerfile CMD)...
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 1/1)
  Waiting for 7847515a205e68 to become healthy (started, 1/1)
✓ Command override cleared
Restarting machine...
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 0/1)
  Waiting for 7847515a205e68 to become healthy (started, 1/1)
Waiting for machine to start...
Checking machine status...
App
  Name     = gallformers
  Owner    = personal
  Hostname = gallformers.fly.dev
  Image    = gallformers:deployment-01KGK3RYGFDM2DYKWYW38428JJ

Machines
PROCESS	ID            	VERSION	REGION	STATE  	ROLE	CHECKS            	LAST UPDATED
app    	7847515a205e68	91     	iad   	started	    	1 total, 1 passing	2026-02-04T14:03:25Z



Checking health endpoint...
✓ Health check passed

=== Database Update Complete ===

Summary:
  Species count: 5793
  File size: 14.29 MB
  SHA-256: 44427754dba0887f46a997216d9b8be41ed01ed6b57c8c71f5bb94370ca35b0f

Next steps:
  1. Verify site: https://gallformers.fly.dev/
  2. Check logs: fly logs -a gallformers
```

**After the task completes:**

```bash
# Verify V2 via Fly.io URL
curl -i https://gallformers.fly.dev/health
# Should return 200
[x] DONE at 905AM ET Feb 4

# Run smoke tests
mix smoke_test https://gallformers.fly.dev
```
[x] DONE at 905AM ET Feb 4
```
➜  gallformers git:(main) ✗ mix smoke_test https://gallformers.fly.dev
Running smoke tests against https://gallformers.fly.dev

✓ Health check (/health)
✓ API stats (/api/v2/stats)
✓ Discover gall ID (/api/v2/galls) → found ID 4153
✓ Discover host ID (/api/v2/hosts) → found ID 2241
✓ Discover genus ID (/api/v2/families) → found ID 507
✓ Home page (/)
✓ Gall page (/gall/4153)
✓ Host page (/host/2241)
✓ Genus page (/genus/507)
✓ Search API (/api/v2/search?q=weldi)
✓ Search UI (/globalsearch?q=weldi)
✓ Static CSS (/assets/css/app-b70450bb1260ce0f35e138f2fe92b73c.css?vsn=d)
✓ Static JS (/assets/js/app-cc61c76223b57e2478ffe1796ff695b0.js?vsn=d)
✓ Image gallery (/gall/4153)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
14 checks, 14 passed, 0 failed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
**⚠️ If smoke tests fail, STOP - do not proceed to DNS cutover.**

**See:** `lib/mix/tasks/gallformers/update_prod_db.ex` for implementation details

---

## Section 4: DNS Cutover (10:45-11:00 AM)

### Pre-cutover final checks
```bash
# Verify V2 is healthy on Fly.io
curl -i https://gallformers.fly.dev/health
```
[x] DONE at 907AM ET Feb 4

```
➜  gallformers git:(main) ✗ curl -i https://gallformers.fly.dev/health
HTTP/2 200
date: Wed, 04 Feb 2026 14:06:51 GMT
content-length: 2
vary: accept-encoding
cache-control: max-age=0, private, must-revalidate
x-request-id: GJEQQ97IqssGtvYAAAth
content-type: text/plain; charset=utf-8
server: Fly/c3040578e (2026-01-27)
via: 2 fly.io
fly-request-id: 01KGMFMD9REBG32CY2EWEPDRHG-iad

ok%
```

```bash
# Verify CloudFront distribution is accessible
curl -i https://dfd18lb16qtjl.cloudfront.net/health
```
[x] DONE at 907AM ET Feb 4
```
➜  gallformers git:(main) ✗ curl -i https://dfd18lb16qtjl.cloudfront.net/health
HTTP/2 200
content-type: text/plain; charset=utf-8
content-length: 2
date: Wed, 04 Feb 2026 14:07:17 GMT
vary: accept-encoding
cache-control: max-age=0, private, must-revalidate
x-request-id: GJEQSeaLJZ0i7CsAAAuB
server: Fly/c3040578e (2026-01-27)
via: 1.1 fly.io, 1.1 fly.io, 1.1 54a56da0fe0bae919389c7d572d4720e.cloudfront.net (CloudFront)
fly-request-id: 01KGMFN6JWG4B4MNTD2KNGD55B-ewr
x-cache: Miss from cloudfront
x-amz-cf-pop: JFK50-P6
x-amz-cf-id: fc0o_ubECTSqOkFKL1iBoUXz6U7-ObWsaZCWlH0ip4C19k-_5fWZRA==
vary: Origin

ok%
```
### Both should return 200 OK

# DNS Cutover

## Background & Rationale

**The Problem:** DigitalOcean DNS does NOT support ALIAS/ANAME records (confirmed via DO documentation and community forums, Feb 2026). We cannot point apex domains (gallformers.org, gallformers.com) directly to CloudFront via CNAME because:
1. DNS standards prohibit CNAME records at the zone apex (conflicts with SOA/NS records)
2. ALIAS records are a workaround that DO doesn't support
3. Using hardcoded CloudFront IPs is unreliable (they can change)

**The Solution:** Keep apex A records pointing to DO droplet, configure nginx to 301 redirect apex → www. The www records will CNAME to CloudFront.

**Why This Works:**
- The 301 redirect is a browser-level redirect - the browser makes a NEW DNS lookup for the www domain
- After DNS change, www resolves to CloudFront, so the redirect sends users to V2
- Apex A records never change, so rollback is simple (just revert www CNAME + disable redirect)

**Traffic flow after cutover:**
```
User visits gallformers.org (apex)
  → DNS resolves to DO droplet (A record, unchanged)
  → Nginx returns 301 redirect to www.gallformers.org
  → Browser makes NEW request to www.gallformers.org
  → DNS resolves to CloudFront (CNAME, changed)
  → CloudFront → Fly.io → V2 app responds

User visits www.gallformers.org
  → DNS resolves to CloudFront (CNAME)
  → CloudFront → Fly.io → V2 app responds
```

**Critical:** Configure nginx redirect BEFORE changing any DNS records. This ensures:
1. No downtime - www still works through V1 during transition
2. When DNS propagates, the redirect target is already pointing to CloudFront
3. Safe intermediate state to verify before proceeding

---

## DO Droplet Nginx Configuration

### Discovery: Current nginx setup

The V1 Next.js app runs on the DO droplet with this architecture:
- Next.js server on localhost:3000
- Nginx reverse proxy on ports 80/443
- Let's Encrypt SSL certificates via Certbot

**Config location:** `/etc/nginx/conf.d/nginx.conf` (NOT in sites-enabled)

**Original config before changes:**
```nginx
server {
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    server_name gallformers.org www.gallformers.org gallformers.com www.gallformers.com;

    location / {
        if (-f $document_root/maintenance.html) {
            return 503;
        }
        proxy_set_header   X-Forwarded-For $remote_addr;
        proxy_set_header   Host $http_host;
        proxy_pass http://localhost:3000;
    }

    error_page 503 @maintenance;
    location @maintenance {
        rewrite ^(.*)$ /maintenance.html break;
    }

    location ~ /.well-known/acme-challenge {
        allow all;
        root /var/www/html;
    }

    listen [::]:443 ssl ipv6only=on;
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/gallformers.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gallformers.org/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if ($host = www.gallformers.org) { return 301 https://$host$request_uri; }
    if ($host = www.gallformers.com) { return 301 https://$host$request_uri; }
    if ($host = gallformers.com) { return 301 https://$host$request_uri; }
    if ($host = gallformers.org) { return 301 https://$host$request_uri; }

    listen 80;
    listen [::]:80;
    server_name gallformers.org www.gallformers.org gallformers.com www.gallformers.com;
    return 404;
}
```

**Problem with original:** Single server block handles all 4 domains identically (all proxy to Next.js). We need apex domains to redirect to www instead.

---

### Step 1: Configure nginx redirect on DO droplet

SSH into the droplet:
```bash
ssh jeff@157.245.243.86
```

**1a. Backup current config:**
```bash
sudo cp /etc/nginx/conf.d/nginx.conf /etc/nginx/conf.d/nginx.conf.bak
```
[x] DONE at 920AM ET Feb 4

**1b. Replace with new config:**
```bash
sudo tee /etc/nginx/conf.d/nginx.conf << 'EOF'
# Apex domains - redirect to www (this is what handles traffic after DNS cutover)
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name gallformers.org gallformers.com;

    ssl_certificate /etc/letsencrypt/live/gallformers.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gallformers.org/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Redirect apex to www (preserves path and query string)
    return 301 https://www.$host$request_uri;
}

# WWW domains - proxy to Next.js (handles traffic until DNS propagates)
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name www.gallformers.org www.gallformers.com;

    ssl_certificate /etc/letsencrypt/live/gallformers.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gallformers.org/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    location / {
        if (-f $document_root/maintenance.html) {
            return 503;
        }

        proxy_set_header   X-Forwarded-For $remote_addr;
        proxy_set_header   Host $http_host;
        proxy_pass http://localhost:3000;
    }

    error_page 503 @maintenance;
    location @maintenance {
        rewrite ^(.*)$ /maintenance.html break;
    }

    location ~ /.well-known/acme-challenge {
        allow all;
        root /var/www/html;
    }
}

# HTTP to HTTPS redirect for all domains
server {
    listen 80;
    listen [::]:80;
    server_name gallformers.org www.gallformers.org gallformers.com www.gallformers.com;

    return 301 https://$host$request_uri;
}
EOF
```
[x] DONE at 930AM ET Feb 4

**What this config does:**
- **Apex server block (443):** gallformers.org and gallformers.com return 301 redirect to `https://www.$host$request_uri`
- **WWW server block (443):** www.gallformers.org and www.gallformers.com proxy to Next.js (V1) - this continues working until DNS propagates
- **HTTP server block (80):** All domains redirect HTTP → HTTPS

**1c. Test and reload:**
```bash
sudo nginx -t && sudo systemctl reload nginx
```
[x] DONE at 931AM ET Feb 4

**Verification:**
- [X] `nginx -t` shows "syntax is ok" and "test is successful"
- [X] `systemctl reload nginx` completes without errors

---

### Step 2: Test redirect locally on DO droplet

**Important:** At this point, DNS hasn't changed. Both apex and www still resolve to DO droplet. We're testing that:
1. Apex domains now redirect to www
2. WWW domains still serve V1 (no downtime)

```bash
# Test apex HTTPS redirect
curl -I https://gallformers.org
# Expected: HTTP/2 301, Location: https://www.gallformers.org/

curl -I https://gallformers.com
# Expected: HTTP/2 301, Location: https://www.gallformers.com/

# Test www still serves V1
curl -I https://www.gallformers.org
# Expected: HTTP/2 200 (served by Next.js)

curl -I https://www.gallformers.com
# Expected: HTTP/2 200 (served by Next.js)

# Test full redirect chain works (follow redirects)
curl -IL https://gallformers.org 2>&1 | head -20
# Expected: 301 → www → 200
```

[x] DONE at 937AM ET Feb 4
**Verification:**
- [X] `https://gallformers.org` returns 301 with `Location: https://www.gallformers.org/`
- [X] `https://gallformers.com` returns 301 with `Location: https://www.gallformers.com/`
- [X] `https://www.gallformers.org` returns 200 (V1 still working)
- [X] `https://www.gallformers.com` returns 200 (V1 still working)

### Step 3: Update www DNS records at DigitalOcean

Log into DigitalOcean → Networking → Domains

**For gallformers.org:**
- Delete the A record for `www.gallformers.org`
- Create CNAME record: `www` → `dfd18lb16qtjl.cloudfront.net`
[x] DONE at 941AM ET Feb 4

**For gallformers.com:**
- Delete the A record for `www.gallformers.com`
- Create CNAME record: `www` → `dfd18lb16qtjl.cloudfront.net`
[x] DONE at 941AM ET Feb 4

**DO NOT change the apex (@) A records** - they stay pointing to `157.245.243.86`

### Step 4: Monitor DNS propagation

```bash
# Check www DNS (should show CloudFront domain, may take 1-5 min with 300s TTL)
dig www.gallformers.org +short
dig www.gallformers.com +short
# Expected: dfd18lb16qtjl.cloudfront.net (or CloudFront IPs)

# Verify apex still points to DO droplet
dig gallformers.org +short
dig gallformers.com +short
# Expected: 157.245.243.86
```
[x] DONE at 944AM ET Feb 4

**Verification:**
- [x] `www.gallformers.org` resolves to CloudFront
- [x] `www.gallformers.com` resolves to CloudFront
- [x] `gallformers.org` still resolves to `157.245.243.86`
- [x] `gallformers.com` still resolves to `157.245.243.86`

### Step 5: Verify www works through CloudFront

```bash
# Check for CloudFront headers on www
curl -sI https://www.gallformers.org | grep -i "x-cache\|via\|server"

# Should see:
# x-cache: Miss from cloudfront (or Hit from cloudfront)
# via: 1.1 xxxxx.cloudfront.net (CloudFront)
# server: Fly/...
```
[x] DONE at 943AM ET Feb 4

**Verification:**
- [x] `www.gallformers.org` returns 200 with CloudFront headers
- [x] `www.gallformers.com` returns 200 with CloudFront headers

### Step 6: Verify apex redirect works end-to-end

```bash
# Test apex redirects to www (follow redirects to verify full chain)
curl -IL https://gallformers.org 2>&1 | head -20

# Should show:
# 1. 301 redirect from gallformers.org to www.gallformers.org
# 2. 200 OK from www.gallformers.org with CloudFront headers
```
[x] DONE at 943AM ET Feb 4

**Verification:**
- [x] `gallformers.org` returns 301 → `www.gallformers.org`
- [x] `gallformers.com` returns 301 → `www.gallformers.com`
- [x] Following the redirect gives 200 with CloudFront headers

### Step 7: Run smoke tests against all domains

```bash
mix smoke_test https://www.gallformers.org
mix smoke_test https://www.gallformers.com
mix smoke_test https://gallformers.org
mix smoke_test https://gallformers.com

# All should pass (apex tests will follow redirects)
```
[x] DONE at 944AM ET Feb 4

**Verification:**
- [x] All 4 smoke tests pass (14/14 each)

**✅ DNS Cutover complete. End timestamp: 944AM ET Feb 4**

**Note:** The DO droplet must remain running to handle apex redirects. Future cleanup task: migrate DNS to Cloudflare (supports CNAME flattening) to eliminate DO dependency.

---

## Litestream Fix (Post-Cutover Issue)

**Issue discovered at ~9:48 AM:** Litestream was logging errors every second:
```
level=ERROR msg="sync error" db=/data/gallformers.sqlite error="checkpoint: mode=PASSIVE err=database disk image is malformed"
```

**Root cause:** When we uploaded the new VACUUMed database, Litestream's internal state directory (`.gallformers.sqlite-litestream`) from the old database was incompatible. Additionally, the WAL file created after restart was corrupted.

**Impact:** App was serving requests fine (200s), but backups weren't working.

**Verification:** Checked logs - no POST/PUT/DELETE requests since cutover, so no user data at risk.

**Fix applied at ~10:04 AM:**
```bash
# SSH into machine
fly ssh console -a gallformers

# Delete corrupted WAL and SHM files
rm /data/gallformers.sqlite-wal /data/gallformers.sqlite-shm

# Delete Litestream state directory
rm -rf /data/.gallformers.sqlite-litestream

# Exit and restart machine
exit
fly machine restart 7847515a205e68 -a gallformers
```

**Result:** Litestream now working correctly:
```
level=INFO msg="write wal segment" ... replica=s3
level=INFO msg="wal segment written" ... elapsed=40.115007ms
```

---

## Section 5: Post-Cutover Monitoring & Verification (11:00 AM-1:00 PM)

### Immediate verification (first 15 minutes)

**1. Run automated smoke tests**
```bash
# Test all production domains
mix smoke_test https://gallformers.org
mix smoke_test https://www.gallformers.org
mix smoke_test https://gallformers.com
mix smoke_test https://www.gallformers.com

# All tests must pass before continuing
# If any fail, investigate immediately
```
[x] DONE at 944AM ET Feb 4 - All 4 domains passing (14/14 each)

**2. Monitor Fly.io logs**
```bash
fly logs -a gallformers

# Watch for:
# - Successful requests (200s)
# - No error spikes (500s, database errors)
# - LiveView connections working
# - Normal traffic patterns
```
[x] DONE at 1005AM ET Feb 4 - Logs clean after Litestream fix

**3. Check Fly.io metrics dashboard**
```bash
fly dashboard -a gallformers

# Monitor:
# - CPU usage (should be normal, <50%)
# - Memory usage (should be stable)
# - Request rate (traffic flowing)
# - Response times (should be fast)
```
[x] DONE at 1005AM ET Feb 4 - Machine healthy, 1/1 checks passing

**4. Manual functional testing**
- Browse to https://gallformers.org
- Verify homepage loads with LiveView connected
- Test search functionality
- Browse to a gall page, host page, species page
- Verify images load from CloudFront
- Test admin login via Auth0
- Verify admin can edit (editing is enabled on V2)

### 30-minute checkpoint

**5. Review error rates**
```bash
# Check for any error patterns in logs
fly logs -a gallformers | grep -i error

# Acceptable: occasional 404s, old bookmarks
# Not acceptable: 500s, database errors, auth failures
```
[x] DONE at 1251PM ET Feb 4 - No errors or 5xx in logs

**6. Verify CloudFront caching behavior**
```bash
# Check that static assets are cached
curl -sI https://gallformers.org/assets/app.css | grep -i "x-cache"
# Should show "Hit from cloudfront" after first request

# Check that dynamic pages are NOT cached
curl -sI https://gallformers.org/ | grep -i "x-cache"
# Should show "Miss from cloudfront" or no x-cache header
```
[x] DONE at 1251PM ET Feb 4 - Static assets cached (Hit), dynamic pages not cached (private, must-revalidate)

### 1-hour checkpoint

**7. Test full user workflows**
- Browse multiple galls, hosts, species
- Test search with various queries
- Test identification tool (if applicable)
- Verify all images display correctly
- Test external links, source citations
[x] DONE at 1251PM ET Feb 4

**8. Check for any user reports**
- Monitor Discord for issues
- Check email for error reports
[x] DONE at 1251PM ET Feb 4 - No issues reported

### Decision point (1-2 hours)

**If all green:**
- ✅ No error spikes in logs
- ✅ Normal CPU/memory usage
- ✅ All core functionality working
- ✅ Images loading correctly
- ✅ Auth working
- ✅ No user complaints

→ **Declare cutover successful**
→ Continue passive monitoring for rest of day
→ DO droplet stays running for 7-day rollback window

**If critical issues:**
→ **Execute rollback** (Section 6)

**✅ CUTOVER DECLARED SUCCESSFUL at 1251PM ET Feb 4**

---

## Section 6: Rollback Procedure (If Needed)

**Full details:** See `runbooks/v2-cutover-rollback.md`

### Quick rollback (if critical issues in V2)

**Note:** With the apex-redirect approach, rollback is simpler because apex A records never changed - they still point to DO droplet.

**Step 1: Stop V2 app (optional but recommended)**
```bash
fly scale count 0 --app gallformers
# Prevents new data creation during rollback
```

**Step 2: Disable apex redirect on DO droplet**

SSH into the droplet and remove/disable the redirect server block:
```bash
ssh jeff@157.245.243.86
sudo nano /etc/nginx/sites-enabled/default  # or wherever the redirect was added
# Comment out or remove the apex redirect server block
sudo nginx -t
sudo systemctl reload nginx
```

**Step 3: Revert www DNS at DigitalOcean**

Log into DigitalOcean → Networking → Domains

**For gallformers.org:**
- Delete the CNAME record for `www`
- Create A record: `www` → `157.245.243.86`

**For gallformers.com:**
- Delete the CNAME record for `www`
- Create A record: `www` → `157.245.243.86`

**Note:** Apex (@) A records don't need to change - they already point to DO.

**Save changes.**

**Step 4: Wait for DNS propagation**
```bash
# Check DNS (5-15 minutes with 300s TTL)
dig www.gallformers.org +short
dig www.gallformers.com +short
# Both should return 157.245.243.86
```

**Step 5: Verify V1 is serving traffic**
```bash
curl -i https://gallformers.org
curl -i https://www.gallformers.org
# Both should return 200 OK from V1 (DO droplet)

# Verify a few pages work
curl -i https://gallformers.org/galls/1
```

**Step 6: Re-enable editing on V1 (if needed)**
```bash
# Redeploy V1 without edit-disable
# Or manually revert the edit-disable code
```

**⚠️ Data loss warning:**
- Any data created in V2 after cutover will be lost
- Export V2 database before rollback if needed:
```bash
fly ssh console -a gallformers -C "sqlite3 /data/gallformers.sqlite .dump" > v2-post-cutover-dump.sql
```

**Rollback window: 7 days** (DO droplet stays running)

---

## Section 7: Post-Success Tasks

### After declaring cutover successful (12:00-1:00 PM)

**Immediate:**

**1. Update status page**
- Close the maintenance announcement issue: `gh issue close 7 --repo jeffdc/gallformers-status`
- Remove announcement banner from `.upptimerc.yml`
- Verify status page shows "All systems operational" (after Upptime rebuilds in ~5 min)
[x] DONE at 1010AM ET Feb 4

**2. Re-enable editing on V2**
- Editing was already enabled on V2
[x] N/A - editing already enabled

**3. Post communication**
- Discord announcement: "V2 cutover complete, site running on new infrastructure"
- Thank users for patience
[x] DONE at 1015AM ET Feb 4

### T+24 hours (Wednesday, February 5)

**4. Review overnight logs**
```bash
fly logs -a gallformers --since=24h | grep -i error
# Check for any issues during off-hours traffic
```

**5. Verify all functionality**
- Test admin CRUD operations
- Verify search indexing working
- Check image uploads (if re-enabled)
- Verify external integrations (if any)

**6. Run data audit**
```bash
mix audit.schema_fields
# Check data completeness (gallformers-3rtg)
```

### T+7 days (Tuesday, February 11)

**7. Final verification checkpoint**
- Review week's logs for patterns
- Verify no user complaints
- Check Fly.io metrics for stability

**8. Document any issues encountered**
- Create GitHub issues for any bugs found
- Note any performance improvements needed

### Future cleanup (no rush - P4 tasks)

- **gallformers-7yep:** Remove V1 callback URLs from Auth0 (after 7+ days)
- **gallformers-jqac:** Shut down DO droplet (after 7+ days, take final backup first)
- **gallformers-94kv:** Delete AWS Lambda downdetector
- **gallformers-d18u:** Remove legacy IAM policies
- **gallformers-uuou:** Remove v1/ directory from repo (after DO shutdown)
- **gallformers-1f19:** Migrate DNS from DigitalOcean to Namecheap (optional, lower priority)

**Reset DNS TTL:**
After 7 days of stability, increase TTL back to 3600 seconds (1 hour) for better caching.

---

## Quick Reference

**Key URLs:**
- V1 (current): https://gallformers.org → 157.245.243.86
- V2 (Fly.io): https://gallformers.fly.dev
- V2 (CloudFront): https://dfd18lb16qtjl.cloudfront.net

**Key commands:**
```bash
# Smoke tests
mix smoke_test <url>

# Fly.io monitoring
fly logs -a gallformers
fly status -a gallformers
fly dashboard -a gallformers

# DNS checks
dig gallformers.org +short

# CloudFront verification
curl -sI https://gallformers.org | grep -i "x-cache"
```

**Rollback trigger:** Critical functionality broken, cannot fix forward in <1 hour

**Support contacts:** Solo operation - no external support

**Runbooks:**
- Full rollback procedure: `runbooks/v2-cutover-rollback.md`
- CloudFront operations: `runbooks/cloudfront-v2-cutover.md`

---

## Timeline Summary

| Time | Phase | Duration |
|------|-------|----------|
| T-24h | Pre-cutover prep (DNS TTL, Auth0, status page) | 30 min |
| T-0 | Deploy V1 edit-disable | 10 min |
| 10:00 AM | Database cleanup & migration | 30 min |
| 10:30 AM | Upload to Fly.io & verify | 15 min |
| 10:45 AM | DNS cutover | 15 min |
| 11:00 AM | Immediate verification | 15 min |
| 11:15 AM | 30-min checkpoint | 15 min |
| 12:00 PM | 1-hour checkpoint | 30 min |
| 12:30 PM | Decision: success or rollback | - |
| 1:00 PM | Post-success tasks (if successful) | 30 min |

**Total estimated downtime:** 15-30 minutes (during DNS propagation)

---

## Checklist

### Pre-cutover (T-24h)
- [ ] DNS TTL lowered to 300s at DigitalOcean
- [ ] DNS records documented (screenshots)
- [ ] Auth0 V2 callback URLs added
- [ ] Database upload solution tested and ready
- [ ] Status page updated with maintenance notice
- [ ] V1 edit-disable deployed and verified

### Cutover day (10:00 AM)
- [ ] Database downloaded from DO
- [ ] Orphaned records cleaned up
- [ ] V1→V2 migration applied
- [ ] Database compacted and WAL synced
- [ ] Database verified locally
- [ ] Database uploaded to Fly.io
- [ ] Upload checksum verified
- [ ] Fly.io app restarted
- [ ] Health checks passing on Fly.io
- [ ] DNS updated at DigitalOcean
- [ ] DNS propagation confirmed
- [ ] Smoke tests passing on all domains
- [ ] CloudFront headers verified

### Post-cutover monitoring
- [ ] Smoke tests passing (immediate)
- [ ] Fly.io logs clean (no errors)
- [ ] Metrics normal (CPU, memory, requests)
- [ ] Manual testing passed
- [ ] 30-min checkpoint passed
- [ ] 1-hour checkpoint passed
- [ ] Decision: success or rollback

### Post-success
- [ ] Status page updated
- [ ] Editing re-enabled on V2
- [ ] Communication posted (Discord)
- [ ] T+24h logs reviewed
- [ ] T+7d verification complete
- [ ] DNS TTL reset to 3600s
