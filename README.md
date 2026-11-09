# Forever QuickJoin v0.6.5

A World of Warcraft **Forever** (1.60.1, Interface `16001`) addon for finding groups, managing listings using Blizzard’s secure listing tab, and handling incoming recruitment whispers in a dedicated role-sorted inbox.

## Installation

1. Remove the previous `ForeverQuickJoin` folder.
2. Extract the ZIP so the path is `_forever_/Interface/AddOns/ForeverQuickJoin/ForeverQuickJoin.toc`.
3. Restart WoW, or type `/reload` after updating the addon.
4. Open with `/qj` or the minimap button. `/qj list` opens the hosting screen directly; `/qj find` opens group search.

## New in v0.6.5 — Roster fixes and Advanced Filters

- **Member class formatting:** The member panel shows the class once. When Forever's `specName` is just a repetition of `className`, QuickJoin suppresses it; real specializations remain visible.
- **Always-accessible Whisper to Join:** The Whisper button stays pinned to the fixed-height listing header when the roster is expanded (rather than moving with the expanded row).
- **Advanced Filters:** Click **Advanced Filters >>** near the standard role filters to open an opaque side panel (or an inset overlay on smaller screens). Click the button again or the close icon to collapse it.
- **Exclude classes:** Select any combination of class checkboxes to hide groups already containing those classes, such as **Warlock** and **Warrior**. The filters use each listed member's actual `classFilename`, retrieved from the read-only LFG API. If the roster is incomplete or unreadable, QuickJoin excludes that group by default; select **Include groups with unreadable rosters** to allow it as a possible match.
- **Additional options:** Filter by **Playstyle**, maximum current member count, **Only groups I can whisper** (leader name is accessible), and **Only groups with descriptions**. Advanced filters combine with existing role filters and apply to the already cached results; use the normal **Search** button for new server results.
- **Saved preferences:** Advanced options persist per character. **Clear Filters** and **Clear All Filters** reset both standard and advanced criteria. The drawer closes automatically when switching to **List Group**.

**Class-filter caveat:** Excluding a class can only be guaranteed when the client exposes the full member roster. Enabling the unknown-roster override may let unverified groups through; it does not mean the missing members were checked. Missing member details are not inferred using class/spec guesses or automatic `/who` calls.

## Find Groups

**Expandable group details (new in v0.6.4):** Click any group listing (except its **Whisper to Join** button) to expand an inline roster. Click again to collapse it or click a different group to switch. The details include Blizzard class and role icons, each member's name where provided, level, class, specialization, area and a leader indicator. Group notes are also displayed. Large raid rosters scroll inside the listings pane; the whisper editor remains visible. Names, levels, specs and locations that Forever hides or has not supplied are shown as unknown—not obtained through /who and never fabricated. This panel reads `C_LFGList.GetSearchResultPlayerInfo()` (with legacy member-info fallback) only from existing results; **it does not trigger another Search or any protected action**.

**Show all level ranges:** In Find Groups, check **Show all level ranges** beneath the activity selectors to include activities outside your character's suggested level range. Leave it unchecked for suggested-level activities only. The checkbox updates the activity dropdown, the category's Search activity scope, and locally cached listings. The preference is saved per character; `/qj all` toggles the same setting. Changing it does **not** run a protected Search call: click **Search** to retrieve fresh listings. Actual entry/eligibility restrictions still apply.

Select a category/activity and click **Search**, sort by group size, filter by estimated role vacancies or groups already containing a tank/healer, inspect current group roles, and send customizable one-click whispers. `/qj reset` restores the original solo/group-aware template.

Each search result now shows its **Playstyle** beneath the activity name: **Learning**, **Relaxed**, **Competitive**, or **Carry Offered**. This comes from `C_LFGList.GetSearchResultInfo().generalPlaystyle`; QuickJoin prefers Blizzard's localized labels. When the client does not expose the value, the row shows **Playstyle: Unavailable** instead of guessing. The playstyle display does not change searching or filtering.

**Preview:** the word `Preview:` now uses the normal UI text color; only the resolved whisper text uses the player's configured Blizzard `WHISPER` chat color.

## List Group / Applicant Inbox

1. Switch to **List Group** from the tabs at the top of `/qj`.
2. Click **Open Blizzard Listing**. This opens Blizzard's native Listing tab, where you create, edit or remove your listing. Blizzard performs the restricted action; QuickJoin does not call `C_LFGList.CreateListing()`, `UpdateListing()`, or `RemoveListing()`.
3. Return to QuickJoin via `/qj` or the minimap button. Incoming whispers are captured even while the QuickJoin window is hidden.
4. Incoming player whispers automatically enter the in-session inbox (even while the QuickJoin window is closed), unless **Capture incoming whispers** is unchecked.
5. Applicants are sorted into **Tank**, **Healer**, **DPS**, and **Unknown** groups, with Blizzard role icons and class icons when the class is known. Newest messages appear first within each group. Unread counts and role totals are visible.
6. Click an applicant to see **only that player's conversation** and available class/level/role/location details. The role buttons let you manually correct the role assignment.
7. Use **Reply** to respond, **Invite** to send a party invitation, **Decline + Remove** to send the standard decline whisper and remove the applicant, or **Dismiss** to remove a conversation without messaging.
8. **Lookup /who** pre-fills the `/who` query for the selected player in chat. Press **Enter** yourself to run it. When the game returns Who data, QuickJoin updates the applicant's class, level and zone where available.

### What the addon can actually know

- **Class:** From `GetPlayerInfoByGUID()` when a character GUID and record are available. Shows a question-mark icon otherwise.
- **Level:** From the same GUID lookup (when provided by the Forever client), or a returned `/who` result.
- **Role:** Generic whispers do **not** contain a role field. QuickJoin conservatively parses self-reported phrases like `Tank LFG` / `Healer here` / `DPS LFG`; a message asking for a tank is **not** classified as a tank applicant. Unknown/ambiguous roles stay in **Unknown** until set manually.
- **Location:** Not available directly from a whisper. A player-initiated `/who` can provide their current zone, if the client/server returns it. Location is not tracked automatically.
- **Spec:** Not exposed by general whisper events. QuickJoin displays **unknown** instead of guessing.

### Important restrictions and privacy

- Creating, updating, and removing your listing happens **in Blizzard’s own Listing tab**, not in QuickJoin. This is a deliberate compatibility workaround for the protected-action error reported in v0.6.0; there is no automatic background listing and no attempt to bypass WoW restrictions.
- `/who` is also restricted. **Lookup /who only prepares text**: it never sends a Who request itself. It is possible for the client not to produce a usable Who response.
- The inbox stores up to **100 applicants**, each with their most recent **35 messages**, in **session memory only**. Whisper contents are **not** written to SavedVariables and disappear on logout/reload.
- The inbox captures ordinary incoming whispers from any sender while capture is enabled, not just formal Group Finder applicants. Formal native Group Finder applications are **not yet imported** into this whisper inbox.
- While WoW marks sender names or message contents as *secret*, the addon cannot reliably group those messages into per-player conversations. Such messages remain visible in normal WoW chat; QuickJoin does not try to circumvent the restriction.
- **Invite** means an invitation was attempted; the game may require additional confirmation. The applicant stays queued until they join or are dismissed.
- **Decline + Remove** sends: `Sorry, we can't take you for this group. Good luck!` It removes the applicant after the client accepts the send attempt; actual delivery is not guaranteed.
- Chat messages are limited to 255 bytes. QuickJoin refuses oversized messages and messages during reported chat lockdown.

## Controls

- `/qj` — toggle QuickJoin
- `/qj find` — Find Groups tab
- `/qj list` — List Group / applicant inbox tab
- `/qj reset` — restore the current solo/party default whisper template
- `/qj activities` — request group activity metadata
- `/qj all` — toggle showing activities outside your suggested level range
- `/qj retry` — re-enable a search button that WoW blocked
- `/qj status` — show diagnostic state

## Validation

The Lua sources were checked and simulated client regression tests were run for the existing Find Groups features and the native listing handoff, incoming-whisper routing, role sorting, character details, `/who` preparation, Invites, and Declines. **Testing in the actual Forever client remains necessary.**
