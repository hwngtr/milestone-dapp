# Milestone, escrow crowdfunding dApp

Week 1–2 package for the Current Topics in CS individual project (VGU).

**Claim:** crowdfunding where donor money is held by a contract and released one milestone at a
time, with donor-triggered objections and refunds as a right. No privileged key can move the funds.

## Deliverables

| File | What it is |
|---|---|
| `docs/01-proposal.md` | Project proposal: problem, scope, success criteria, risks, schedule |
| `docs/02-blockchain-necessity-analysis.md` | The graded argument: chain vs database, with numbers and kill criteria |
| `docs/03-architecture.md` | Components, contracts, flows, trust boundary, deployment |
| `docs/04-security-preview.md` | 12 threats, 12 mitigations, 6 invariants |
| `PLAN.md` | How the package was built and what Week 3–8 looks like |

Supporting material:

| Path | Purpose |
|---|---|
| `scripts/cost_model.py` | Generates every cost figure. Change assumptions, re-run, documents follow |
| `scripts/decision_matrix.py` | Weighted comparison plus the sensitivity test that flips the winner |
| `diagrams/*.dot` | Graphviz sources; `*.png` and `*.svg` are rendered |
| `contracts/interfaces/*.sol` | The contract API the architecture assumes |

## Rebuild the numbers and diagrams

```bash
# numbers
python3 scripts/cost_model.py          # -> docs/cost-model-output.md, data/cost-model.csv
python3 scripts/decision_matrix.py     # -> docs/decision-matrix-output.md

# diagrams (Graphviz)
cd diagrams
for f in *.dot; do dot -Tsvg "$f" -o "${f%.dot}.svg"; dot -Tpng -Gdpi=200 "$f" -o "${f%.dot}.png"; done
cd ..
```

## Build and test (Week 3)

```bash
export PATH="$PATH:$HOME/.foundry/bin"   # once, or add to your shell profile
make test          # forge test: 38 unit tests + 4 invariants (64 fuzz runs)
make snapshot      # gas snapshot -> .gas-snapshot
make anvil         # local node on 127.0.0.1:8545 (separate terminal)
make deploy-local  # deploy the factory to Anvil with anvil's default account
```

The Foundry project root is this directory: contracts live in `contracts/`, tests in `tests/`,
deploy script in `deploy/` (python scripts stay in `scripts/`). A verified Week 3 run: factory
deploy → `createCampaign` → `contribute` → `finalizeOutcome` past the deadline → `claimRefund`,
with the creation deposit still locked in the clone.

## The three numbers to remember

| Number | Meaning |
|---|---|
| **69%** | Share of gas the naive per-donor voting design wasted on confirming visible work |
| **$79.80 vs $75.00** | On L1 the chain is *not* cheaper than card fees, for one $2,000 campaign |
| **0.02%** | Share of funds raised that the same campaign costs on an L2 |

## What is deliberately not here

No contracts are implemented yet. Week 1–2 is the proposal, the justification, and the architecture;
`contracts/interfaces/` pins the API so Week 3 starts from a decision instead of a blank file.

Out of scope for the whole project: fiat on-ramp, on-chain arbitration, ERC-20 contributions,
upgradeable contracts, privacy, production indexer.
