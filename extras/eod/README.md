# Optional: EOD digest

Nightly headless capture. **Off by default.** Do not enable in week one — meeting sync + morning brief first.

Scripts here still need:

- `EOD_WORKSPACE` — Cursor workspace root
- `EOD_VAULT` — this clone
- `EOD_SLACK_USER_ID`
- Claude Code CLI and a Glean MCP login

Copy the scripts into `99_System/scripts/` only after you intend to load launchd. Until then, healthcheck treats missing EOD files as OK.
