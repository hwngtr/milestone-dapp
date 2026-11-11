#!/usr/bin/env bash
# Milestone demo: contribute -> deliver -> release -> withdraw on a fresh Anvil chain.
# No reading of source required. Run: make demo
set -euo pipefail
RPC="${ETH_RPC_URL:-http://127.0.0.1:8545}"
export ETH_RPC_URL="$RPC"

DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # anvil #0
CREATOR_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" # anvil #1
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
CREATOR=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
DEPOSIT=10000000000000000 # 0.01 ether creation deposit
GOAL=10000000000000000000 # 10 ether

if ! curl -s -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$RPC" \
    | grep -q '0x7a69'; then
  echo "starting a fresh Anvil node (stops when the demo ends)..."
  anvil --silent &
  ANVIL_PID=$!
  CREATED_ANVIL=1
  trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
  sleep 2
fi

say() { echo; echo "== $1"; }

say "1. Deploy the CampaignFactory (one implementation, every campaign is a cheap clone)"
FACTORY_ADDR=$(forge script deploy/DeployFactory.s.sol --rpc-url "$RPC" --broadcast --private-key "$DEPLOYER_KEY" 2>/dev/null \
  | grep -oP 'CampaignFactory:\s+\K0x[0-9a-fA-F]{40}')
if [ -z "$FACTORY_ADDR" ]; then echo "factory deploy failed"; exit 1; fi
echo "   factory: $FACTORY_ADDR"

say "2. A creator opens a campaign: 10-ether goal, 3 milestones (4/3/3), 90 s funding, 90 s challenge window"
DEADLINE=$(($(date +%s) + 90))
cast send "$FACTORY_ADDR" \
  "createCampaign(string,string,uint96,uint64,uint96[],uint32)" \
  "Clean water for Kampot" "r2://demo" "$GOAL" "$DEADLINE" \
  "[4000000000000000000,3000000000000000000,3000000000000000000]" 90 \
  --value "$DEPOSIT" --private-key "$CREATOR_KEY" >/dev/null
CAMPAIGN=$(cast call "$FACTORY_ADDR" 'campaignAt(uint256)(address)' 0)
echo "   campaign: $CAMPAIGN"
echo "   status:   $(cast call "$CAMPAIGN" 'status()(uint8)') (0 = Funding)"
echo "   deposit locked in escrow: $(cast balance "$CAMPAIGN") wei"

say "3. A donor contributes the 10-ether goal (funds are held by the contract, nobody else)"
cast send "$CAMPAIGN" "contribute()" --value "$GOAL" --private-key "$DEPLOYER_KEY" >/dev/null
echo "   totalRaised: $(cast call "$CAMPAIGN" 'totalRaised()(uint256)')"

say "4. Deadline passes, goal met -> the campaign activates"
cast rpc evm_increaseTime 95 >/dev/null; cast rpc evm_mine >/dev/null
cast send "$CAMPAIGN" "finalizeOutcome()" --private-key "$DEPLOYER_KEY" >/dev/null
echo "   status: $(cast call "$CAMPAIGN" 'status()(uint8)') (2 = Active)"

say "5. The creator delivers milestone 0 and opens the challenge window (evidence hash on-chain)"
EVIDENCE=$(cast keccak "evidence/well-photo.png")
cast send "$CAMPAIGN" "deliver(uint8,bytes32)" 0 "$EVIDENCE" --private-key "$CREATOR_KEY" >/dev/null
echo "   milestone 0: $(cast call "$CAMPAIGN" 'milestoneStatus(uint8)(uint8)' 0) (1 = ChallengeWindow)"
echo "   donors have 90 seconds to object. Silence is consent."

say "6. The window closes with no objections. Anyone - not an admin - releases the milestone"
cast rpc evm_increaseTime 95 >/dev/null; cast rpc evm_mine >/dev/null
cast send "$CAMPAIGN" "release(uint8)" 0 --private-key "$DEPLOYER_KEY" >/dev/null
echo "   milestone 0: $(cast call "$CAMPAIGN" 'milestoneStatus(uint8)(uint8)' 0) (3 = Released)"

say "7. The creator pulls the payout. Push nothing; the creator calls withdraw()"
cast send "$CAMPAIGN" "withdraw()" --private-key "$CREATOR_KEY" >/dev/null
echo "   creator received 4 ether (milestone 0), still holding milestones 1-2"
echo "   campaign escrow: $(cast balance "$CAMPAIGN") wei (6 ether + 0.01 deposit)"

say "8. What the class cannot do: there is no function that moves donor funds to an operator"
echo "   no owner key, no pause, no upgrade, no admin withdraw. That is the whole claim."
echo
echo "demo complete"
