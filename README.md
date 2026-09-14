# Phenom Personal Copilot

Empty **personal OS** for a Phenom PM: inbox, context layer, meeting routing, morning brief, weekly review.

This is a **GitHub template**. Use it to create **your** private repo. Do not clone this template and commit your 1:1s back here.

Product skills, Jira rules, and engineering context live in **[phenom-product-copilot](https://github.com/officiallybasti/phenom-product-copilot)** — open **both** folders in one Cursor window.

## Setup

1. GitHub → **Use this template** → private repository under your account.
2. Clone your copy.
3. Cursor: **Add Folder to Workspace** → this clone **and** Product Copilot.
4. In chat, on this vault: `set me up`.

That fills `99_System/context/` and `99_System/meetings/routing.json` from your calendar. Skip any step.

Day to day: `morning brief`, `sync meetings`, `plan my week`.

## What stays empty on purpose

No other PM's meetings, people notes, or goals. You build those. Stubs say **Fill in**.

## Optional later

- `extras/eod/` — nightly digest (launchd). Turn on after two weeks of briefs.
- `extras/gsd/` — team weekly-goals board if your org uses that process.

## Health

```bash
./99_System/scripts/healthcheck.sh
```

## Shared vs personal

Would another Phenom PM need this with no extra explanation? If yes, promote it to Product Copilot (`promote context`). If no, it stays here.
