# Changelog

## 0.7.1 — 2026-11-09

- Removed **Confirm detected roles** and **Reset to WoW** from the Party Role Manager, retaining per-player Tank/Healer/DPS and Auto actions.
- Replaced enlarged low-resolution role sprites with Blizzard's larger `UI-LFG-ICON-ROLES` atlas in the persistent party panel and per-character manager icons.
- Moved **Show all level ranges** below the category and activity selectors. Compact Advanced Filters vertically and align the **Exclude groups containing these classes** heading with the other yellow filter headings.
- Moved the **Sent** status directly between group-role counts and the Whisper button. `Sent*` denotes a cached, temporarily unverifiable listing.
- Repositioned **Open Blizzard Listing** into the List Group header to leave a clear gap before the party panel.
- Removed the incoming-whisper capture checkbox; capture is on by default, remains session-only, and stores no whisper history in SavedVariables.
- Completely reworked Modern into a restrained graphite/blue theme with layered surfaces, crisp borders, hierarchical typography and distinct button states, while preserving the original Forever appearance and instant switching.
- Added Lua 5.1 syntax checking to the automated GitHub release workflow.

## 0.7.0 — 2026-11-09

- Added a persistent green **Sent** badge to contacted group listings. Marker identity uses leader, activity, and listing age where available, and follows refreshed search result IDs.
- Pinned sent listings remain visible through new searches, activity changes, sorting, and advanced filters; cached-only entries say **Sent (cached)** and cannot be whispered until verified. Confirmed delisting or a distinguishable newly created listing clears the marker.
- Sent indicates the client-side send request, not confirmed delivery. Tracking is session-only.
- Added instant-switchable **Forever** (unchanged original style) and **Modern** (flat opaque charcoal/slate, teal accents, square-style controls, cleaner in-game typography) themes. No reload, external UI addons, or bundled fonts required.
- Theme choices persist per character; all QuickJoin panes, expanded rosters, role manager, and applicant inbox follow the selection.

## 0.6.9 — 2026-11-09

- Consolidated all Find Groups filters, level-range selection, and member sorting inside **Advanced Filters**; existing saved preferences and search behavior are preserved.
- Replaced the small title-bar role strip with a much larger, always-visible **Party detected** status area in both QuickJoin tabs, including large Blizzard role icons and a clearer change/review action.
- Adjusted the applicant inbox layout to keep the role panel visible without hiding hosting controls.
- Simplified **Party Role Manager** to Tank / Healer / DPS only, removed **Send anyway once**, and added a prominent selected-role icon beside each character.
- Fixed the **Auto** button becoming a question mark after a role refresh; unknown members still require a valid role before a group-composition whisper.
- Aligned the **Preview:** label and the whisper preview on a shared top baseline.

## 0.6.8 — 2026-11-09

- Added a persistent **Party detected** composition strip in Find Groups and List Group with Blizzard role icons and Tank / Healer / DPS / Unknown counts.
- Added **Party Role Manager** with class and level information for each party/raid member, explicit role confirmation and correction, pagination for large raids, and reset-to-WoW controls.
- Changed the whisper generator to use confirmed QuickJoin roles instead of blindly trusting `UnitGroupRolesAssigned()` for party members.
- Flagged DPS assignments on multi-role classes, unassigned roles, and changed underlying WoW assignments for review.
- Open the role manager before sending a group whisper with uncertain roles; allow an explicit one-whisper override.
- Preserve role confirmations during the current group session, forget departed players, and clear corrections when the group disbands.
- Added `/qj roles` and `/qj party` commands; no protected role-writing calls or background polling.

## 0.6.7 — 2026-11-09

- Added a manual right-click `/who` lookup for named members in expanded group rosters. Returned zones are short-lived snapshots.

## 0.6.6 — 2026-11-09

- Corrected class filters for WoW Forever; changed playstyle filters to independent exclusions; removed the unreadable-roster override.

## 0.6.5 — 2026-11-09

- Corrected duplicate class labels and kept Whisper to Join visible with expanded rosters.
- Added class, playstyle, size, description, and whisperability advanced filters.

## 0.6.4 — 2026-11-09

- Added expandable group rosters and available member information.

## 0.6.3 — 2026-11-08

- Added Show all level ranges to Find Groups.

## 0.6.2 — 2026-11-08

- Displayed group playstyles (Learning, Relaxed, Competitive, Carry Offered).

## 0.6.1 — 2026-11-08

- Moved listing creation and management to Blizzard's native protected listing UI.

## 0.6.0 — 2026-11-08

- Added the List Group tab, applicant inbox, conversations, invites and declines.

## 0.5.x — 2026-11-08

- Added role icons, sorting, minimap launcher, current-location and party-aware whisper templates.
