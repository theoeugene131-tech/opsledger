# OpsLedger — AI Compliance & Operations Platform

Forked from Procwise's codebase, restructured into an executive-facing
GRC (governance, risk & compliance) platform. Top nav, in order:

- **Dashboard** — cross-module overview and account settings.
- **Compliance** — regulatory requirements guide, license/permit expiry
  tracker, with Cybersecurity assessments nested underneath.
- **Governance** — risk register, internal audits, and **Tasks**: every
  audit finding with a corrective action automatically becomes an
  assigned, trackable task. Also houses the expanded "AI Compliance
  Officer" document generator (risk assessments, board papers, CAPA,
  incident/investigation reports, vendor assessments, compliance gap
  analysis, policies).
- **Operations** — purchase approvals (procurement is one aspect of
  this, not its own top-level module), inventory, vendors, assets,
  document management.
- **Finance** — real double-entry books (chart of accounts, journal
  entries, P&L, balance sheet, ratios), with Financial Compliance
  (AML/KYC) nested underneath.
- **People** — employee roster, leave approvals, HR documents, with
  Training (courses, certifications, expiry tracking) nested underneath.
- **Documents** — the AI SOP/policy generator (formerly "Document
  Workspace").
- **Reports** — the cross-module AI operations briefing, plus the
  **Evidence Log**: a general-purpose place to log proof (inspections,
  sign-offs, board approvals, attached files) — not just policies.

## Positioning

Tagline: "Stay compliant. Pass audits. Control operations. Train staff.
Manage risk." Title: "AI Compliance & Operations Platform." Pricing
panel shows Starter/Professional/Business/Enterprise tiers aimed at
overseas SME buyers rather than a single flat $30/yr — **the Paddle
price IDs in `checkout()` are still placeholders** (`YOUR_PADDLE_PRICE_ID_STARTER`
etc.) and need real prices created in your Paddle dashboard before this
is live.

## Deferred — needs your decision, not a code change

- **Vertical focus** (healthcare / fintech / food & hospitality, per
  the strategy note this build was based on) — copy is currently
  generic across verticals; narrowing it is a marketing decision.
- **Merging Procwise and CertifyPath into OpsLedger as sub-modules** —
  a business/brand decision, not implemented here.
- **License-key paywall hardening** — flagged in an earlier session as
  a real vulnerability (hardcoded keys + a client-trusted `?activated=true`
  URL param both grant free Pro access). Not yet fixed; needs a
  server-side Paddle webhook + Supabase check.


This is a **separate product** from Procwise. Nothing here should
touch Procwise's GitHub repo, Vercel project, or Supabase project —
that one keeps running exactly as it was for anyone who just wants the
original compliance-document generator.

## Setup — run the SQL in this exact order

In a **brand-new Supabase project** (do not reuse Procwise's):

1. `schema_foundation.sql` — `profiles` and `documents`. These existed
   in Procwise's Supabase project but were only ever created by hand
   in the dashboard, never written down as SQL — reconstructed here
   from how the app code uses them, so a fresh project has them from
   the start.
2. `schema_procurement.sql` — organizations, team invites, purchase
   approvals.
3. `schema_expansion.sql` — assets, risk register, internal audits,
   deeper vendor fields, document storage bucket.
4. `schema_financials.sql` — chart of accounts, double-entry journal
   entries, the balance-enforcing posting function.
5. `schema_compliance.sql` — the license/permit expiry tracker.
6. `schema_hr_training.sql` — employee roster, leave requests, training
   courses, and the certification/training-record expiry tracker.
   Reuses `organizations`, `org_members`, `my_org_id()` and
   `is_org_approver()` from step 2, and the `org-documents` storage
   bucket from step 3 (for certificate attachments).
7. `schema_grc.sql` — Tasks (remediation tracking, auto-created from
   audit findings) and the Evidence Log. Reuses `organizations`,
   `my_org_id()` from step 2, and the `org-documents` bucket from step 3
   (for evidence file uploads).

## New infrastructure needed (none of this can be shared with Procwise)

- **New Supabase project** — new `SUPABASE_URL` / `SUPABASE_ANON_KEY`,
  both marked as placeholders at the top of the script section in
  `index.html` (search for `YOUR_PROJECT_ID`)
- **New Paddle product and price** — the old $30/yr Procwise price and
  live client token have been replaced with placeholders
  (`YOUR_PADDLE_CLIENT_TOKEN`, `YOUR_NEW_PADDLE_PRICE_ID`). OpsLedger
  is a materially bigger product; price it separately rather than
  reusing Procwise's number by default.
- **New GitHub repo** and **new Vercel project**, pointed at the new
  Supabase + Paddle config above via Vercel's environment variables
  (same `GEMINI_API_KEY` setup as before — that part can stay as is,
  it's just an API key with its own usage limits, not tied to either
  product's identity)

## What did NOT get fixed in this rename

The license-key paywall issue flagged earlier in Procwise is present
in this codebase too, just renamed (`OPSLEDGER-2025-PRO1-ABCD` etc. are
still sitting in plain text in the client-side JS, and `docs_used` in
`profiles` still isn't reliably enforced — real usage counting still
happens in `localStorage`). Forking the app carried the bug forward.
Worth fixing here before OpsLedger has real paying customers, same as
it was for Procwise.

## What's unchanged from Procwise

The document-generation engine, compliance requirements guide,
cybersecurity assessments, and the core AI-writing flow are the same
code, unbranded-and-rebranded. Any improvement made to that shared
core in one codebase won't automatically appear in the other — they're
independent copies from this point forward.
