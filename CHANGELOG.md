# Changelog

## 0.6.3 — 2026-11-08

- Added a persistent **Show all level ranges** checkbox to the Find Groups window; the existing `/qj all` shortcut stays synchronized.
- When enabled, out-of-range activities appear in the activity selector and are included when searching all activities in a category.
- When disabled, the dropdown, category-wide search scope, and cached listings honor suggested level ranges.
- Changing the checkbox never triggers a protected server Search call; explicitly click **Search** to refresh results.
- Preserved Blizzard playstyle labels, whisper workflow, and the hosting applicant inbox.

## 0.6.2 — 2026-11-08

- Display the group listing's **Playstyle** beneath its activity: Learning, Relaxed, Competitive, or Carry Offered.
- Read the actual `generalPlaystyle` result field, using Blizzard's translated labels when available and an explicit unavailable fallback.
- Keep role icons, whisper buttons, activity filtering, sorting, and the native-hosting handoff unchanged.

## 0.6.1 — 2026-11-08

- Fixed the live Forever `ADDON_ACTION_BLOCKED` reported at `ForeverQuickJoin_Host.lua:427`.
- The custom List/Update/Delist actions are now replaced by an **Open Blizzard Listing** handoff using `GroupFinderVanillaStyle_LoadUI` and `LFGVanilla_ToggleFrame(1)` (as in LFG Forever).
- Removed misleading unused listing selectors. Listing creation, editing, and removal are now performed in Blizzard's native protected UI.
- Preserved role-sorted applicant inbox, player conversations, invite/decline, whisper previews, and independent Find Groups.
- Added combat guard and active-listing indicator. No automatic retries or direct listing API calls.


## 0.6.0 — 2026-11-08

- Added Find Groups / List Group tab navigation and `/qj list` / `/qj find` commands.
- Added one-click group listing, updating and delisting using native protected WoW APIs from physical clicks.
- Added a session-only role-organized applicant whisper inbox with Blizzard role/class icons and unread counts.
- Added per-applicant conversations, manual role overrides, Reply, Invite, Decline + Remove, Dismiss and user-confirmed `/who` lookup.
- Added guarded GUID-based class/level enrichment and optional WHO-based location data, without guessing unavailable spec or role information.
- Changed preview styling: **Preview:** is in the normal interface color; only the resolved whisper text is pink.
- Preserved search, sorting, filters, location templates, roster-aware whispers, and minimap launcher.

## 0.5.2 — 2026-11-08

- Matched message preview color to Blizzard whispers; removed redundant Refresh UI button.

## 0.5.1 — 2026-11-08

- Solo and party-aware whisper defaults, Reload Whisper Template, dynamic party details.

## 0.5.0 — 2026-11-08

- Member sorting, role vacancy/composition filters, minimap button and location preview.

## 0.4.x — 2026-11-08

- Independent Search, Blizzard role icons and location token.