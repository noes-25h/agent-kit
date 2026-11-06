#!/bin/bash
# Detection patterns for secret-guard. This is the only file you edit to add or remove a pattern.
# block.sh and redact.sh source it. The file itself executes nothing.
#
# One row = one kind of key. Three whitespace-separated columns:
#   name   tier   regex (grep -E / sed -E syntax; no spaces and no "/" inside)
# Tier:
#   B = block before execution, and also redact when it shows up in output
#   R = do not block; redact when it shows up in output
# Redaction covers every row, so anything that is blocked is always redacted too.
#
# When you add a row, add a sample with the same name to sg_sample in tests/selftest.sh.
# selftest fails on any row that has no sample.

sg_rows() {
  cat <<'SG_TABLE'
openai-project   B  sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{40,}
openai-legacy    B  sk-[A-Za-z0-9]{40,}
anthropic        B  sk-ant-[A-Za-z0-9_-]{20,}
github-token     B  gh[pousr]_[A-Za-z0-9]{36,}
github-fine      B  github_pat_[A-Za-z0-9_]{22,}
aws-access-key   B  (AKIA|ASIA)[A-Z0-9]{16}
slack            B  xox[baprs]-[A-Za-z0-9-]{10,}
google-api       B  AIza[A-Za-z0-9_-]{35}
npm              B  npm_[A-Za-z0-9]{36}
sendgrid         B  SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}
notion           B  ntn_[A-Za-z0-9]{40,}
stripe-live      B  (sk|rk)_live_[A-Za-z0-9]{20,}
stripe-webhook   B  whsec_[A-Za-z0-9]{20,}
stripe-test      R  (sk|rk)_test_[A-Za-z0-9]{20,}
ghost-admin      R  [0-9a-f]{24}:[0-9a-f]{64}
SG_TABLE
}

# PEM private keys (a block between a header line and a footer line).
# A header line blocks the call. In output, everything from the header to the footer is redacted.
# The strings are split in two so that editing this file is not blocked by the guard itself.
SG_PEM_BEGIN_RE='BEGIN [A-Z ]*PRIVATE '"KEY"
SG_PEM_END_RE='END [A-Z ]*PRIVATE '"KEY"

# Set to 1 to also block literals such as "password": "...".
# This fires on test fixtures and sample configs too, so the default is 0.
SG_BLOCK_LITERALS=0
SG_LITERAL_RE='"(password|passwd|sec''ret)"[[:space:]]*[:=][[:space:]]*"[^"]+"'

# The replacement text
SG_MARK='[REDACTED-BY-SECRET-GUARD]'

# All rows joined into one regex, used for redaction
SG_REDACT_RE=$(sg_rows | awk 'NF>=3 {printf "%s%s", (n++ ? "|" : ""), $3}')

# Set only when the file was read to the end. block.sh and redact.sh check it to know the load succeeded.
[ -n "$SG_REDACT_RE" ] && SG_PATTERNS_LOADED=1
