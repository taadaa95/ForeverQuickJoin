# Changelog

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
