# Forever QuickJoin v0.5.2

A standalone group browser and one-click whisper addon for **WoW Forever 1.60.1** (Interface 16001).

## Install

1. Remove the existing `ForeverQuickJoin` folder from your Forever `Interface/AddOns` directory.
2. Extract the ZIP so the path is `Interface/AddOns/ForeverQuickJoin/ForeverQuickJoin.toc` (no nested duplicate folder).
3. Restart the game, or type `/reload` after replacing the addon files.
4. Open the addon with `/qj` or its draggable minimap icon.

## What's new in v0.5.2

- The full whisper preview is colored using WoW's own `ChatTypeInfo["WHISPER"]` RGB settings. It follows your personalized whisper color and updates when that color changes. If unavailable, it uses the usual pink whisper color.
- Removed the redundant **Refresh** button. Click **Search** to request new listings; the addon will continue processing server results automatically.
- All activity filters, sorting, minimap button, group-aware messages, party detection and `/qj` controls remain unchanged.

## Previous improvements from v0.5.1

- Solo default whisper is now **exactly**:
  `Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!`
- Added **Reload Whisper Template**. Click to discard a custom message and restore the appropriate default for your current party state. `/qj reset` does the same.
- While grouped, the default changes to:
  `Level {level} {class} {role} LFG {activity}, Current location: {location}, Party: {party}, inv please!`
  The `{party}` placeholder describes **other group members** by name, level, class, and **assigned role**. Example: `Alex (Lv32 Priest Healer); Bob (Lv31 Warrior Tank)`.
- The default automatically switches back to the *exact* solo template when you leave the group; it updates for new/removed players, level changes and role assignments. Any hand-written template is **left unchanged** when the roster changes.
- The `My Role` and `Hide full` controls have been removed. `Clear Filters`, role-vacancy checkboxes, already-has checkboxes and member sorting remain.
- A visible **Sort by:** label now precedes the member-count sorting dropdown.
- The preview displays your currently resolved message and group status. Saved templates persist per character.

## Placeholder reference

- `{level}` — your level
- `{class}` — your class
- `{role}` — your selected LFG role
- `{activity}` — activity selected in QuickJoin or the result's actual activity when whispering
- `{location}` — your **live** zone when you whisper
- `{name}` — your character name
- `{party}` — other group members' names, levels, classes, and assigned roles (does not include you)
- `{partycount}` — total group size including you (1 when solo)

`{party}` and `{partycount}` also work in manually customized templates. An unassigned group role is labeled **Unassigned**, not guessed from the class. Some member details may be unavailable when WoW marks them as restricted or while the group roster loads; QuickJoin indicates that instead of inventing data.

## Existing functionality

1. Select a category/activity and click **Search** in QuickJoin. Search is only issued from a real button click, not on a timer or during roster changes.
2. Sort by finder order, fewest group members, or most members.
3. Filter groups by open tank/healer/DPS slots and existing tank/healer composition. Role vacancies are **estimates** based on typical party/raid compositions, not recruitment promises.
4. Click **Whisper to Join** on a listing to send the prepared message to its leader. It does **not** file a formal application.
5. Click **Reload Whisper Template** at any time to restore the default for solo/party state.

## Commands

- `/qj` — open or close the window
- `/qj reset` — same as Reload Whisper Template
- `/qj refresh` — optional diagnostic command to re-read cached listings (no dedicated Refresh button; no server search)
- `/qj activities` — request activity metadata
- `/qj all` — show activities of all levels
- `/qj retry` — re-enable Search after a client block
- `/qj status` — print diagnostics

## Limitations and safety

- Group roles are read from `UnitGroupRolesAssigned()`. Players who have not chosen an assigned role display as **Unassigned**; the addon cannot infer their intended dungeon role from class alone.
- WoW chat whispers are limited to **255 bytes**. If a complete party/raid message is too long, QuickJoin tries shorter role labels; if it is still over the limit, it **does not send** and prompts you to shorten it. Full raid rosters usually cannot fit in one whisper.
- Changing your template manually disables automatic switching between solo and grouped defaults. Click **Reload Whisper Template** to resume automatic switching.
- WoW's `C_LFGList.Search()` may be protected. The addon will not bypass restrictions, and it will not search in the background.
- The code has been syntax-checked and simulated WoW API / UI tests passed, including roster changes and one-click whisper messages. **It still requires verification in the live Forever client.**
