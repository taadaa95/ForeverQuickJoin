# Changelog

## 0.8.6 — 2026-11-12

- Fixed the minimap keybinding tooltip showing WoW's abbreviated **c+I** instead of **Ctrl + I**.
- Modifier names are now expanded (Ctrl, Shift, Alt) from the raw current binding, with readable spacing and localized non-modifier keys where available.
- Supports combined modifiers, mouse bindings, secondary keybindings, and changes made in WoW's Keybindings settings without reload.
- The existing default Ctrl+I binding and all user-assigned shortcuts remain untouched.


## 0.8.5 — 2026-11-12

- Minimap tooltip now displays the player's **current** Toggle Forever QuickJoin keybinding, rather than assuming the default Ctrl+I.
- Dynamically reads WoW's keybinding settings on each mouseover, including character-specific overrides and secondary shortcuts; shows **Not bound** when unassigned.
- Uses WoW's localized keybinding labels when available, and falls back to raw key names on clients without that formatter.
- Added Lua 5.1 regression coverage. Existing saved bindings, native default, and protected actions are unchanged.


## 0.8.4 — 2026-11-12

- Assigned **Ctrl+I** as the native default shortcut for **Toggle Forever QuickJoin**.
- Removed the binding's custom `header` attribute: Forever's Keybindings UI was displaying an extra, unbindable `HEADER_FOREVERQUICKJOIN` row. Only the toggle action should remain under the built-in Other category.
- The shortcut remains fully customizable, including character-specific bindings through WoW's own Keybindings UI. No login-time binding overrides or forced resets are used.
- Updated binding and packaging regression coverage for the default shortcut.


## 0.8.3 — 2026-11-12

- Added a **Toggle Forever QuickJoin** action to WoW's native Keybindings menu. WoW handles the chosen shortcut and character-specific/account bindings; no default key is forced.
- Added suggested dungeon level ranges (from the Forever client's activity metadata) to the activity dropdown, selected dungeon, group-result secondary labels, and per-activity mouseover tooltips. Non-dungeon categories are unchanged and missing level data is never invented.
- Updated GitHub release ZIP packaging to include the automatically loaded root `Bindings.xml` without incorrectly listing it in the TOC.
- Added Lua 5.1 regression tests for dungeon range formatting, category boundaries, multi-activity selection, binding wiring, and packaging checks.


## 0.8.2 — 2026-11-11

- Fixed Find Groups controls, result rows, whisper editor and filter labels showing through the List Group / Applications tabs when theme transparency is enabled.
- All finder-only UI is now grouped in its own independently hidden content frame; the persistent header and navigation remain visible in every tab.
- The shared party summary remains visible in Find Groups and List Group but no longer overlays Applications.
- Both Forever and Modern theme transparency continue to show the world behind the active tab without leaking hidden tab content.
- Added a tab isolation regression test and kept Blizzard-protected searches on explicit button clicks only.


## 0.8.1 — 2026-11-10

- Fixed protected Group Finder descriptions rendering as raw Kstring tokens. Native protected tokens are passed to WoW's renderer unchanged, while ordinary untrusted text is still escaped.
- Added complete group descriptions in a wrapped tooltip and expanded group details, with layout height measured from rendered text rather than truncated.
- Added a note icon and a one-line, visually clipped description preview in listings.
- Improved the local activity/zone keyword search with alternate names from Blizzard's activity metadata.
- Added Lua 5.1 regression tests for protected and ordinary description text and UI wiring. No background restricted search actions were added.


## 0.8.0 — 2026-11-10

- Added a local-only **Filter activities** input beside the Activity dropdown. Typing narrows the menu options; pressing Enter selects the first match. No background or protected searches are triggered.
- Added a per-character **Reply notifications** checkbox to Applications, enabled by default. Matching incoming group-leader replies play an optional sound and show on-screen/chat alerts, except when that conversation is already open.
- Added proportional window resizing through a bottom-right grip (70–145% scale), persisted per character. Right-click the grip to reset to 100%; preserving the fixed layouts avoids clipping in Find Groups, List Group, and Applications.
- Added regression tests for filtering, scale limits, notification preferences, and UI wiring. Original protected click-to-search behavior remains unchanged.


## 0.7.7 — 2026-11-10

- Added complete support for group listings advertising multiple dungeon activities (WoW Forever allows several activities on one listing).
- Finder activity matching now checks **every** advertised activity ID, including when the selected dungeon is the second or third. Each group still appears just once in search results.
- Finder rows show the selected matching dungeon first and a **+N** indicator when the full list does not fit. Hover to see every dungeon; expanded group details include all advertised activities.
- The outgoing `{activity}` whisper placeholder includes all advertised activities, prioritizing the currently selected dungeon. If the full list would exceed WoW's 255-byte whisper limit, it falls back to a concise **(+N more)** activity description.
- Sent tracking and NEW-listing identity now use a canonical, order-independent set of activity IDs. Reordering dungeons no longer loses the Sent marker.
- When a leader edits an existing listing to change its activities, QuickJoin can retain Sent if the original result ID, leader and listing creation time still identify the same listing.
- Group-size inference, cached snapshots and My Applications conversations now account for all advertised activities. Legacy single-activity API fields remain supported.
- Added Lua 5.1 regression tests for single/multiple matches, filtering, deduplication, whisper length, and edited listing identities.
- README intentionally unchanged.

## 0.7.6 — 2026-11-10

- Replaced the two Forever/Modern header buttons with one compact **Theme** dropdown.
- Select **Forever** or **Modern** inside the dropdown; the selected theme remains visible on the closed control.
- Added a **Transparency** checkbox to the same dropdown, which applies to both themes immediately and stays enabled when changing themes.
- Transparency affects the background backdrops of QuickJoin's windows and panels, not the entire window alpha, preserving readable text, role icons, borders and controls.
- Saved the selected theme and transparency mode per character. Disabling transparency restores the original Forever backdrop colors and opacity or Modern opaque styling, without /reload.
- Added Lua 5.1 smoke tests for dropdown selection, saved settings, live switching, backdrop-alpha restoration and non-fading text.
- Added a CurseForge `.pkgmeta` so tagged source packaging produces only the addon files, excluding development scripts and tests.
- README intentionally unchanged.

## 0.7.5 — 2026-11-10

- Fixed contacted groups lingering in Find Groups long after Blizzard stopped listing them. QuickJoin no longer re-pins an old search result ID merely because the client still returns cached details.
- On a successfully completed manual Search covering the contacted activity, remove absent Sent listings immediately **when the result set is complete**. Incomplete/capped or unrelated searches do not incorrectly claim a disband.
- Keep cached Sent listings from unrelated searches for at most 10 minutes after their last verified appearance, then remove them from Finder automatically via local housekeeping. This does **not** initiate background Group Finder searches.
- Prevent expired Blizzard result IDs from resurfacing through local refreshes until a new completed search actually returns those IDs.
- Retain whisper conversations in My Applications after Finder eviction; show **Not in Finder** rather than falsely asserting the listing disbanded. Explicit server delisting still displays **Listing ended**.
- Capture the activity scope at the player's Search click, so changing dropdowns while the server responds cannot invalidate unrelated listings.
- Added Lua 5.1 regression tests for complete/truncated search results, changed activities, cache expiry, suppression, revalidation, and late leader replies.
- README intentionally unchanged.

## 0.7.4 — 2026-11-09

- Added **Ignore team composition** to Advanced Filters for unconventional dungeon/raid groups (e.g. four DPS or four tanks).
- When enabled, bypasses QuickJoin's local **Space for Tank/Healer/DPS** and **Already has Tank/Healer** requirements. Saved role choices stay intact but appear dimmed and disabled until the toggle is turned off.
- All other filters, including class/playstyle exclusions and group-size restrictions, continue to apply. The setting persists per character and **Clear All Filters** resets it.
- Does not override WoW Forever's protected search API or any server-side listing restrictions.
- Added Lua 5.1 regression tests for unconventional compositions, preservation of unrelated filters, and clearing the override.

## 0.7.3 — 2026-11-09

- Added **My Applications**, a third tab for contacted group leaders. Tracks QuickJoin-sent whispers, manual follow-up whispers, matching incoming replies, and unread conversations for the current session only.
- Added **Replied** status in application history and a compact **Reply** marker beside the existing Whisper button. Groups still show Sent until a matching leader actually replies; missing responses are never classified as rejection.
- Kept repeat whispers to the same live listing together. New listings with distinguishable creation times start separate applications; confirmed delisting marks old history as ended rather than deleting it.
- Added colored counts for character friends (F), Battle.net friends (B), and guildmates (G) beneath the group leader, with expanded explanations on hover. Uses actual, readable search-result fields and does not guess hidden names.
- Added approximate listing age and **NEW** highlights. NEW is based on observed newly available results from completed manual searches within the same category/activity, or very recent listing age; changing filters never issues a search.
- Added `/qj apps` and `/qj applications`; all conversations remain session-only and replies use Blizzard chat to send.
- Extended GitHub Actions to syntax-check the Applications module and run regression smoke tests for reply matching, repeat sends, and ambiguous cross-realm identities.

## 0.7.2 — 2026-11-09

- Restored Blizzard's original 19×19-pixel role icons in the permanent party summary and each Party Role Manager member row.
- Role icons now display at their native size without enlargement or reduction.
- All other party management, group finder, hosting, filters, Sent status and themes remain unchanged.

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
