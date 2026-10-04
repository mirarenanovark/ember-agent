# SSH Key Auth Debugging

When SSH key auth fails but the key text in `authorized_keys` looks correct.

## Step 1: Get the fingerprint being offered

```bash
ssh -vv -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 user@host whoami 2>&1 | grep "Offering public key"
# debug1: Offering public key: /home/xor/.ssh/id_ed25519 ED25519 SHA256:i1qREGrebIDwxiSx+8WQ0GfGvuPBkAl6W9bEmni0VcU explicit
```

Note the `SHA256:...` fingerprint.

## Step 2: Get the fingerprint on the server

On the server, as the target user (or root):
```bash
ssh-keygen -lf /home/user/.ssh/authorized_keys
# 256 SHA256:SVOwfqv2EwYyKKp18lBbmQ+RSiSQ1mMoyi54QsWTLao user@host (ED25519)
```

## Step 3: Compare

If the fingerprints **don't match**, the key was entered wrong — even if the text appears identical. Common causes:
- Hidden character (non-breaking space, zero-width char, encoding artifact)
- Truncation or line wrap
- Wrong key entirely (e.g., generated a new pair instead of copying)

## Step 4: Fix by exact copy

Don't retype. Copy the exact key bytes:

```bash
# On client:
cat ~/.ssh/id_ed25519.pub
# Copy the output exactly

# On server, overwrite with printf (not echo — echo may add newlines):
printf '%s' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host' > /home/user/.ssh/authorized_keys
chmod 600 /home/user/.ssh/authorized_keys
chmod 700 /home/user/.ssh

# Verify:
ssh-keygen -lf /home/user/.ssh/authorized_keys
```

## Pitfall: sshpass / password auth as fallback

If key auth is broken but you have the password, use paramiko (Python) instead of sshpass:

```python
import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('host', username='user', password='pass', allow_agent=False, look_for_keys=False)
```

This bypasses the key entirely and lets you fix `authorized_keys` from inside.
