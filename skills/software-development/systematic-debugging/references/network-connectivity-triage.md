# Network Connectivity Triage

When downloads, pulls, or installs hang, isolate the failure systematically.

## Step 1: Test individual endpoints

Don't test "the internet" — test specific URLs:

```bash
# Test with timing info
for url in "https://pypi.org" "https://registry.npmjs.org" \
           "https://hub.docker.com" "https://github.com" \
           "https://objects.githubusercontent.com"; do
  code=$(curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" \
         --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "timeout")
  echo "$code $url"
done
```

## Step 2: If pull/download hangs (Docker, pip, curl)

Check IPv4 vs IPv6 with verbose curl:

```bash
curl -sv --connect-timeout 10 "https://registry-1.docker.io/v2/" 2>&1 | head -30
```

Output shows each connection attempt. Pattern to recognize:
```
* Trying 1.2.3.4:443...                              ← IPv4 attempt
* Trying 2600:...:443...                              ← IPv6 attempt
* Immediate connect fail for 2600:... Network is unreachable   ← IPv6 broken
* Connected to registry-1.docker.io (1.2.3.4) port 443         ← IPv4 succeeds
```

If IPv6 fails but IPv4 succeeds, the daemon may be hung on IPv6-first behavior.

## Step 3: Test the smallest possible payload

Before pulling a multi-GB image, pull a tiny one:

```bash
timeout 30 docker pull alpine:latest
```

If even `alpine` hangs, the issue is at the registry transport level, not payload size.

## Step 4: Check daemon config for DNS/IPv6

```bash
cat /etc/docker/daemon.json 2>/dev/null
docker info 2>&1 | grep -i "proxy\|dns\|ipv6"
```

Common fix for IPv6 hang:

```json
{"ipv6": false}
```

in `/etc/docker/daemon.json` → `sudo systemctl restart docker`.

## Step 5: Verify DNS resolution

```bash
host registry-1.docker.io
```

If DNS resolves but connections fail, it's a transport/route issue, not DNS.

## Key principle

**Find the cut point.** A working registry (Docker Hub 200 OK) but hanging pulls means the daemon transport is broken, not the network. A working pypi.org but failed pip install means dependency resolution, not network. Use the smallest possible test at each layer.
