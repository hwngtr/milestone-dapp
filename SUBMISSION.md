# Milestone submission

## What to open

| Artifact | Path | Purpose |
|---|---|---|
| Presentation, 5 minutes | `milestone-week3-4-code-demo.pptx` | Nine slides. Source code, two diagrams, demo and test results. |
| Presentation, same content | `slides/code-demo-print.html` | Self-contained HTML. Arrow keys or next and back move between slides. |
| Printed slides | `slides/milestone-week3-4.pdf` | Beamer version of the code demonstration. |
| Repository readme | `README.md` | Build commands, commands for the demo, and the project claim. |
| Week 1-2 submission | `Submission-v2.pdf` | Proposal, necessity analysis, architecture. |

## What to run

```bash
export PATH="$PATH:$HOME/.foundry/bin"
make test          # 38 unit tests plus the invariant suite, all green
make demo          # fresh Anvil node: create, contribute, deliver, release, withdraw
make deploy-local  # deploy the factory to Anvil
forge snapshot --check
```

The demo uses the standard public Anvil test keys. No real key or real wallet is needed.

## Source map

- `contracts/Campaign.sol` holds the escrow and the state machine.
- `contracts/CampaignFactory.sol` deploys EIP-1167 clones.
- `contracts/interfaces/` pins the public API, events and errors.
- `tests/` holds the unit suite and the ghost-ledger invariant suite.
- `deploy/` holds the deploy script and the one-command demo.
- `docs/` holds the proposal, necessity analysis, architecture, security preview, and the gas report.
- `diagrams/` holds the architecture and lifecycle diagrams.
- `scripts/` holds the cost model, decision matrix, and gas comparison tool.

## Verification evidence

- `.gas-snapshot` is the current gas snapshot. `docs/gas-snapshot-baseline.txt` is the pre-optimization baseline.
- `docs/gas-optimization-report.md` records the measured change: full lifecycle 676,426 to 630,020 gas, a 6.86 percent saving.
- `slides/` holds the slide sources. `slides/build-pptx.cjs` rebuilds the PPTX from `slides/code-demo-print.html`.
