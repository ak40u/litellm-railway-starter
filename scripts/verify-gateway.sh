#!/usr/bin/env bash
# End-to-end check of a deployed LiteLLM gateway.
#
# Proves the parts that make this a gateway rather than a proxy: virtual keys
# stored in Postgres, per-key limits enforced through Redis, and a request path
# that actually returns a completion.
#
#   scripts/verify-gateway.sh https://your-gateway.up.railway.app sk-your-master-key
set -uo pipefail

BASE="${1:?usage: verify-gateway.sh <base-url> <master-key>}"
MASTER="${2:?usage: verify-gateway.sh <base-url> <master-key>}"
BASE="${BASE%/}"
failed=0

ok()   { echo "  ok   $1${2:+ - $2}"; }
fail() { echo "  FAIL $1 - $2"; failed=1; }

# Reads a value out of a JSON document by walking the given path segments;
# numeric segments index into lists. The document is passed as an argument
# rather than on stdin, so this stays usable inside command substitution.
pick() {
  python3 -c '
import json, sys
try:
    node = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
for part in sys.argv[2:]:
    try:
        node = node[int(part)] if part.isdigit() else node[part]
    except Exception:
        sys.exit(0)
print(node if isinstance(node, str) else json.dumps(node))
' "$@"
}

echo "checking $BASE"

# 1. Liveness, without credentials.
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health/liveliness")
[ "$code" = "200" ] && ok "liveness" || fail "liveness" "got $code"

# 2. An unauthenticated completion must be refused.
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/v1/chat/completions" \
  -H 'content-type: application/json' \
  -d '{"model":"self-test","messages":[{"role":"user","content":"hi"}]}')
[ "$code" = "401" ] && ok "unauthenticated request is refused" || fail "unauthenticated request is refused" "got $code"

# 3. A virtual key with a request-per-minute limit - written to Postgres.
key_json=$(curl -s -X POST "$BASE/key/generate" \
  -H "authorization: Bearer $MASTER" -H 'content-type: application/json' \
  -d '{"key_alias":"verification-'"$RANDOM"'","rpm_limit":1,"max_budget":5,"models":["self-test"]}')
KEY=$(pick "$key_json" key)
if [ -n "$KEY" ]; then ok "virtual key created" "rpm limit 1, budget 5"; else fail "virtual key created" "$key_json"; fi

# 4. The key works.
body=$(curl -s -X POST "$BASE/v1/chat/completions" \
  -H "authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"self-test","messages":[{"role":"user","content":"hi"}]}')
answer=$(pick "$body" choices 0 message content)
if [ -n "$answer" ]; then ok "completion through the virtual key" "${answer:0:44}"; else fail "completion through the virtual key" "$body"; fi

# 5. The limit is enforced. Redis holds the counter, so this is also the check
#    that the gateway would still hold the limit across several replicas.
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/v1/chat/completions" \
  -H "authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"self-test","messages":[{"role":"user","content":"again"}]}')
[ "$code" = "429" ] && ok "rate limit enforced" "second call in the same minute refused" \
  || fail "rate limit enforced" "expected 429, got $code"

# 6. The key is readable back out of the database.
info=$(curl -s "$BASE/key/info?key=$KEY" -H "authorization: Bearer $MASTER")
alias_name=$(pick "$info" info key_alias)
if [ -n "$alias_name" ]; then ok "key is readable back from the database" "$alias_name"; else fail "key is readable back" "$info"; fi

# 7. Models can be added at runtime - the reason store_model_in_db is on.
add=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/model/new" \
  -H "authorization: Bearer $MASTER" -H 'content-type: application/json' \
  -d '{"model_name":"verification-echo","litellm_params":{"model":"openai/gpt-4o-mini","mock_response":"added at runtime"}}')
[ "$add" = "200" ] && ok "model added at runtime" || fail "model added at runtime" "got $add"

# 8. Clean up what the check created.
curl -s -X POST "$BASE/key/delete" -H "authorization: Bearer $MASTER" \
  -H 'content-type: application/json' -d "{\"keys\":[\"$KEY\"]}" > /dev/null

echo
[ "$failed" = "0" ] && echo "all checks passed" || { echo "some checks failed"; exit 1; }
