# Project Proposal: Milestone

**Course:** Current Topics in CS, Blockchain, Web3 & Decentralized Systems
**Student:** Hưng Trần · Vietnamese-German University
**Deliverable:** Week 1–2
**Date:** 6 November 2026

---

## One sentence

Milestone is crowdfunding where donor money is held by a smart contract and released to the
creator one milestone at a time, with donor-triggered objections and unconditional refunds if
the goal fails. No employee of the platform can move the funds.

## Problem

A crowdfunding platform holds other people's money for weeks. Four failures follow, and the
operator cannot structurally prevent them, only promise to avoid them:

1. Custody risk. Funds sit in the operator's account.
2. Opaque release. Whether a milestone was met is decided in a private admin panel.
3. Discretionary refunds. A refund is a support ticket, not a right.
4. Deplatforming. A campaign and its funds can be removed.

Policy fixes raise the cost of misbehaviour. They do not make misbehaviour impossible.

## What the system does

A creator opens a campaign with a funding goal, a deadline, and a milestone list. Donors
contribute native ETH during the funding window.

- Goal missed at the deadline: the campaign enters `Failed`. Any donor withdraws their exact
  contribution at any time. No approval, no ticket, no deadline.
- Goal met: the campaign enters `Active`. The creator delivers a milestone by posting an
  evidence hash. A challenge window opens.
- No objections: anyone calls `release()`. The creator's withdrawable balance grows. The
  creator pulls the money in a separate transaction.
- Objection quorum reached — a majority of the money, strictly more than half of `totalRaised`:
  the milestone is vetoed and the campaign is `Canceled`. Every donor withdraws their exact
  contribution at any time. A veto never freezes funds: without on-chain arbitration a frozen
  state has no legitimate exit, so the quorum's power is deliberately blunt — it ends the
  campaign and returns all money to the donors who supplied it.

## Why this beats the obvious design

The obvious design is per-donor voting on every milestone. The cost model rejected it.

| Design | L1 cost, 40 donors x $50, 3 milestones | Share of funds raised |
|---|---:|---:|
| A. Every donor votes on every milestone | $256.20 | 12.81% |
| B. Optimistic release + objection window | $79.80 | 3.99% |
| Card processing, same money | $75.00 | 3.75% |

Design A spends 69% of its gas on donors confirming work they can already see. Design B charges
a donor nothing in the happy path and charges only the donor who disagrees.

## Scope

In scope:

- `CampaignFactory`: create campaigns as EIP-1167 minimal clones, registry, one `CampaignCreated` event.
- `Campaign`: funding, contribution accounting, milestone delivery, challenge window, optimistic
  release, objection quorum, proportional refunds, pull payments.
- Solidity 0.8.x, Foundry tests (unit, fuzz, invariant), gas snapshot.
- React + Vite frontend with wagmi/viem, an Effect-TS transaction state machine.
- Cloudflare Workers: one edge gateway (`/rpc` allowlist proxy, `/api` domain reads, Alchemy
  webhook ingest + cron reconciler), R2 for files, Turnstile on create.
- Deployment: Anvil locally, Ethereum Sepolia (baseline), zkSync Sepolia (primary).
- 5-page IEEE report.

Out of scope: fiat on-ramp, full arbitration, ERC-20 contributions, upgradeable contracts,
governance token, privacy, production indexer.

## Success criteria

1. A stranger clones the repo and runs `make demo`; contribute, deliver, release completes on
   Anvil without reading source.
2. `forge test` passes, including at least four invariants and one reentrancy test that fails on
   a deliberately broken implementation.
3. The report's cost table is generated from measured gas, with block numbers and timestamps.
4. A vetoed milestone can never release: the campaign is `Canceled`, every donor can claim a
   full refund, and no path returns `Canceled` to `Active`.
5. The frontend shows distinct states for pending, replaced, reverted, and finalized transactions,
   and never shows success before a receipt exists.

## Schedule

| Week | Deliverable |
|---|---|
| 1-2 | This package: proposal, necessity analysis, architecture |
| 3-4 | Contracts, Foundry unit + fuzz + invariant tests, gas snapshot |
| 5-6 | Frontend, wallet connection, Effect-TS tx machine, Cloudflare Workers |
| 7 | Sepolia + zkSync Sepolia deployment, end-to-end test, measured gas |
| 8 | IEEE report, README, demo recording, submission |

## Questions for the class

1. Is "no privileged key can move funds" enough, or does milestone escrow need on-chain
   arbitration to be honest?
2. Would you fund a campaign whose only protection is a 5-day objection window?
3. Which failure is worse for adoption: gas cost per contribution, or the wallet UX?