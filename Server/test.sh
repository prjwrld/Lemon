#!/bin/zsh
# Tests the key server locally: runs it with `wrangler dev` and a throwaway local database,
# sends it Razorpay notices signed with a test secret, and checks every rule.
# Usage: ./test.sh            (run the tests, then stop the server and delete the test data)
#        KEEP=1 ./test.sh     (leave the server running on :8787 for testing the app against it)
set -u
cd "${0:a:h}"
URL=http://localhost:8787; SECRET=test-webhook-secret; ADMIN=test-admin-token
PRICE=$(sed -n 's/^PRICE_PAISE = "\([0-9]*\)"/\1/p' wrangler.toml)   # the price the server accepts
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1 (expected '$3', got '$2')"; ((fail++)); fi; }
sign() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}'; }
webhook() { curl -s -o /tmp/lemon-wh.json -w '%{http_code}' -X POST $URL/razorpay/webhook -H "Content-Type: application/json" -H "X-Razorpay-Signature: ${2:-$(sign "$1")}" --data-binary "$1"; }
paid() { echo "{\"event\":\"payment.captured\",\"payload\":{\"payment\":{\"entity\":{\"id\":\"$1\",\"amount\":${2:-$PRICE},\"currency\":\"${3:-INR}\",\"email\":\"Buyer@Example.com\"}}}}"; }
api() { curl -s -X POST $URL/v1/licenses/$1 -H "Accept: application/json" "${@:2}"; }
field() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval('d'+sys.argv[1]))" "$1" 2>/dev/null; }
admin_list() { curl -s $URL/admin/keys -H "Authorization: Bearer $ADMIN"; }
count_keys() { admin_list | python3 -c "import json,sys; print(len(json.load(sys.stdin)['licences']))"; }
key_for() { admin_list | python3 -c "import json,sys; print([l['key'] for l in json.load(sys.stdin)['licences'] if l['payment_id']=='$1'][0])"; }

# Fresh local database and test secrets (.dev.vars is git-ignored).
rm -rf .wrangler/state
printf 'RAZORPAY_WEBHOOK_SECRET=%s\nADMIN_TOKEN=%s\n' $SECRET $ADMIN > .dev.vars
npx wrangler d1 execute lemon-licences --local --file schema.sql >/dev/null 2>&1 || { echo "Couldn't create the local database"; exit 1; }
npx wrangler dev --port 8787 >/tmp/lemon-wrangler.log 2>&1 &
SERVER=$!
for i in {1..60}; do curl -s -o /dev/null $URL/key && break; sleep 0.5; done

echo "1. Payment notices"
check "bad signature is rejected" "$(webhook "$(paid pay_TEST1)" deadbeef)" 401
check "good payment accepted" "$(webhook "$(paid pay_TEST1)")" 200
check "one key made" "$(count_keys)" 1
check "same notice again (Razorpay retry) accepted" "$(webhook "$(paid pay_TEST1)")" 200
check "still only one key: no duplicate" "$(count_keys)" 1
webhook "$(paid pay_WRONGAMT 100)" >/dev/null
webhook "$(paid pay_WRONGCUR $PRICE USD)" >/dev/null
check "wrong amount or currency makes no key" "$(count_keys)" 1
OTHER="{\"event\":\"payment.captured\",\"payload\":{\"payment\":{\"entity\":{\"id\":\"pay_SANTA\",\"amount\":$PRICE,\"currency\":\"INR\",\"email\":\"x@example.com\",\"description\":\"Pro (300 credits)\",\"notes\":{\"kind\":\"pack\",\"skuId\":\"pack_300\"}}}}}"
webhook "$OTHER" >/dev/null
RIGHTLY="{\"event\":\"payment.captured\",\"payload\":{\"payment\":{\"entity\":{\"id\":\"pay_RIGHTLY\",\"amount\":$PRICE,\"currency\":\"INR\",\"email\":\"x@example.com\",\"notes\":{\"app\":\"rightly\"}}}}}"
webhook "$RIGHTLY" >/dev/null
check "Secret Santa / Rightly payment at the same price makes no key" "$(count_keys)" 1
KEY=$(key_for pay_TEST1)
check "key looks right" "$([[ $KEY =~ '^LEMON-([A-HJ-NP-Z2-9]{5}-){3}[A-HJ-NP-Z2-9]{5}$' ]] && echo yes)" yes

echo "2. Find My Key page"
check "right payment ID + email shows the key" "$(curl -s -X POST $URL/key -d payment_id=pay_TEST1 -d email=buyer@example.com | grep -c "$KEY")" 1
check "wrong email shows nothing" "$(curl -s -X POST $URL/key -d payment_id=pay_TEST1 -d email=other@example.com | grep -c "$KEY")" 0

echo "3. Activating on Macs (limit 2)"
A1=$(api activate -d license_key=$KEY -d "instance_name=Mac One" | field "['instance']['id']")
check "first Mac activates" "$([[ -n $A1 ]] && echo yes)" yes
A2=$(api activate -d license_key=$(echo $KEY | tr A-Z a-z) -d "instance_name=Mac Two" | field "['instance']['id']")
check "second Mac activates (key typed in lowercase)" "$([[ -n $A2 ]] && echo yes)" yes
check "third Mac is refused" "$(api activate -d license_key=$KEY -d "instance_name=Mac Three" | field "['activated']")" False
check "validate on Mac One" "$(api validate -d license_key=$KEY -d instance_id=$A1 | field "['valid']")" True
check "validate with a made-up Mac ID fails" "$(api validate -d license_key=$KEY -d instance_id=fake | field "['valid']")" False
check "deactivate Mac Two" "$(api deactivate -d license_key=$KEY -d instance_id=$A2 | field "['deactivated']")" True
check "now a new Mac can activate" "$(api activate -d license_key=$KEY -d "instance_name=Mac Three" | field "['activated']")" True

echo "4. Made-up keys"
check "made-up LEMON- key refused" "$(api activate -d license_key=LEMON-AAAAA-BBBBB-CCCCC-DDDDD -d instance_name=x | field "['error']")" "license_key not found."
check "made-up key fails validate" "$(api validate -d license_key=LEMON-AAAAA-BBBBB-CCCCC-DDDDD | field "['valid']")" False

echo "5. Refunds"
REFUND='{"event":"refund.processed","payload":{"refund":{"entity":{"id":"rfnd_1","payment_id":"pay_TEST1"}}}}'
check "refund notice accepted" "$(webhook "$REFUND")" 200
check "refunded key no longer valid" "$(api validate -d license_key=$KEY -d instance_id=$A1 | field "['valid']")" False
check "refunded key can't activate" "$(api activate -d license_key=$KEY -d instance_name=x | field "['activated']")" False

echo "6. Admin"
check "admin needs the token" "$(curl -s -o /dev/null -w '%{http_code}' $URL/admin/keys)" 401
MANUAL=$(curl -s -X POST $URL/admin/keys -H "Authorization: Bearer $ADMIN" -H "Content-Type: application/json" -d '{"email":"friend@example.com"}' | field "['key']")
check "make a key by hand" "$([[ $MANUAL == LEMON-* ]] && echo yes)" yes
check "hand-made key activates" "$(api activate -d license_key=$MANUAL -d instance_name=x | field "['activated']")" True

echo; echo "$pass passed, $fail failed"
if [[ -n ${KEEP:-} ]]; then
  echo "Server still running on $URL (pid $SERVER). Test key for the app: $MANUAL"
  echo "$MANUAL" > /tmp/lemon-test-key
else
  kill $SERVER 2>/dev/null; pkill -f "wrangler dev --port 8787" 2>/dev/null; sleep 1
  rm -rf .wrangler/state .dev.vars
fi
[[ $fail == 0 ]]
