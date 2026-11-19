# Plan, Milestone (escrow-crowdfunding dApp)

Course: Current Topics in CS, Blockchain, Web3 & Decentralized Systems (VGU).
Project: individual. Week 1–2 deliverables are due **Fri 6 Nov 2026**.

## What "done" means for Week 1–2

The graded package is three artifacts, not code:

| # | Artifact | File | Status |
|---|---|---|---|
| 1 | Project proposal | `docs/01-proposal.md` | done |
| 2 | Use-case justification (blockchain necessity vs central DB) | `docs/02-blockchain-necessity-analysis.md` | done |
| 3 | System architecture diagram + explanation | `docs/03-architecture.md`, `diagrams/*.png` | done |

Supporting material that makes the three artifacts credible:

- `docs/cost-model-output.md` and `data/cost-model.csv`, the generated cost numbers and raw data.
- `docs/04-security-preview.md`, threat table for the contract design.
- `contracts/interfaces/`, Solidity interfaces that pin the API the architecture assumes.

## Deliverable sequence

```
1. Cost model run            -> numbers for the architecture and the report
2. Architecture diagram      -> reading order of the whole system
3. Proposal                  -> what, why, scope, risks, schedule
4. Necessity analysis        -> the argument that carries the grade
5. Security preview          -> three attacks, three mitigations, three tests
6. Rehearse out loud         -> cut, don't add
```

## The argument the project makes

1. Crowdfunding's real failure is **custody**, not code quality.
2. A database can move money correctly. It cannot make the operator *unable* to move money wrongly.
3. That single property, no privileged key can touch donor funds, is the whole justification.
4. Everything else (cost, latency, privacy) is worse on-chain, and the analysis says so.
5. The cost model killed naive per-donor voting: 69% of gas went to confirming visible work. Design is optimistic release with an objection window.

The sentence to defend: **"Nobody, including me, can move the money."**

## Week 3–8 status

| Week | Work | Verifiable output | Status |
|---|---|---|---|
| 3 | Contracts + Foundry tests + `make demo` | factory + EIP-1167 clones, full `Campaign` state machine, 38 unit tests + invariant suite green, Anvil lifecycle verified with `cast` | **done** (2026-11-11) |
| 4 | Exhaustive milestone suite + hardening | multi-milestone flows, deliver/objection edge matrix, reentrancy attack test that fails on a deliberately broken implementation, Sepolia deployment. Gas optimization pass done: `docs/gas-optimization-report.md` | next |
| 5–6 | Frontend + Effect-TS tx machine + Cloudflare Workers | End-to-end contribute on Anvil | planned |
| 7 | Deploy to zkSync Sepolia + Ethereum Sepolia, measure real gas | Cost table replaced by measured numbers | planned |
| 8 | Report (IEEE, 5 pages), README, demo | Submission | planned |

## Risks and how the plan absorbs them

| Risk | Response |
|---|---|
| Scope creep (S3, DAO governance, a production indexer) | Ingest is rebuildable from genesis and the UI reads direct RPC without it |
| L2 testnet faucet issues | Develop against Anvil; deploy to Sepolia L1 as the guaranteed fallback |
| Wallet UX eats frontend time | Buy: wagmi + viem. Build only the tx state machine |
| Report written at the end from memory | Each phase writes its own section; cost model regenerates tables |
| Contract bug found late | Invariant tests from day one; no upgrade path, so tests are the only safety net |

## Definition of done for the code (Week 8)

- `forge test` green, including at least 4 invariants and a reentrancy test.
- A stranger clones the repo, runs `make demo`, and completes contribute → deliver → release on Anvil without reading source.
- The report quotes measured gas, not estimates.
