# Milestone, escrow crowdfunding dApp

Current Topics in CS individual project (VGU). Week 1–2 delivered the proposal, the necessity
analysis, and the architecture; Week 3 delivered the working contracts.

**Claim:** crowdfunding where donor money is held by a contract and released one milestone at a
time, with donor-triggered objections and refunds as a right. No privileged key can move the funds.

Start with `SUBMISSION.md` for the list of files to open and the commands to run.

## Deliverables

| File | What it is |
|---|---|
| `docs/01-proposal.md` | Project proposal: problem, scope, success criteria, risks, schedule |
| `docs/02-blockchain-necessity-analysis.md` | The graded argument: chain vs database, with numbers and kill criteria |
| `docs/03-architecture.md` | Components, contracts, flows, trust boundary, deployment |
| `docs/04-security-preview.md` | 12 threats with mitigations and tests, 8 invariants |
| `contracts/Campaign.sol` | The state machine: funding, milestones, challenge window, veto⇒cancel, pull payouts |
| `contracts/CampaignFactory.sol` | EIP-1167 clone factory; holds no funds, has no power over a campaign |
| `tests/` | 38 unit tests + fuzz invariant suite (ghost ledger), all green |
| `docs/gas-optimization-report.md` | Measured before and after gas snapshot for the Week 3-4 optimization pass |
| `deploy/demo.sh` | `make demo`: the full lifecycle on a fresh Anvil node, one command |
| `PLAN.md` | Week-by-week plan and status |

Week 1–2 submission package: `Submission-v2.pdf`. Week 1–2 slides: `slides/milestone.tex` →
`slides/milestone.pdf`.

Supporting material:

| Path | Purpose |
|---|---|
| `scripts/cost_model.py` | Generates every cost figure. Change assumptions, re-run, documents follow |
| `scripts/decision_matrix.py` | Weighted comparison plus the sensitivity test that flips the winner |
| `scripts/export_deliverable.py` | Concatenates the docs into one markdown for Obsidian |
| `diagrams/*.dot` | Graphviz sources; `*.png` and `*.svg` are rendered from them |
| `contracts/interfaces/` | The pinned public API, implemented by the Week 3 contracts |

## Build and demo (Week 3)

```bash
export PATH="$PATH:$HOME/.foundry/bin"   # once, or add to your shell profile
make test          # forge test: 38 unit tests + invariant suite, all green
make demo          # one command: fresh Anvil node -> create -> contribute -> deliver -> release
make snapshot      # gas snapshot -> .gas-snapshot
make anvil         # local node on 127.0.0.1:8545 (separate terminal)
make deploy-local  # deploy the factory to Anvil with anvil's default account
```

The Foundry project root is this directory: contracts live in `contracts/`, tests in `tests/`,
deploy scripts in `deploy/` (python scripts stay in `scripts/`).

## Rebuild the numbers and diagrams

```bash
python3 scripts/cost_model.py          # -> docs/cost-model-output.md, data/cost-model.csv
python3 scripts/decision_matrix.py     # -> docs/decision-matrix-output.md

cd diagrams
for f in *.dot; do dot -Tsvg "$f" -o "${f%.dot}.svg"; dot -Tpng -Gdpi=200 "$f" -o "${f%.dot}.png"; done
cd ..
```

## The three numbers to remember

| Number | Meaning |
|---|---|
| **69%** | Share of gas the naive per-donor voting design wasted on confirming visible work |
| **$79.80 vs $75.00** | On L1 the chain is *not* cheaper than card fees, for one $2,000 campaign |
| **0.02%** | Share of funds raised that the same campaign costs on an L2 |

## What is deliberately not here

The gas optimization pass is complete. The full lifecycle test dropped from 676,426 to 630,020 gas, a 6.86% saving. See `docs/gas-optimization-report.md`.

Week 4 remains: exhaustive milestone edge matrix, a reentrancy attack test that fails on a
deliberately broken implementation, and Sepolia deployment. Weeks 5–7: frontend, edge gateway,
zkSync Sepolia, measured gas.

Out of scope for the whole project: fiat on-ramp, on-chain arbitration, ERC-20 contributions,
upgradeable contracts, privacy, production indexer.
