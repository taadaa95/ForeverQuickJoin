# Forever QuickJoin v0.6.0

A World of Warcraft **Forever** 1.60.1 (Interface `16001`) addon for finding groups, listing your own group, and managing recruitment whispers in a role-sorted inbox.

## Installation

Extract the install ZIP into `_forever_/Interface/AddOns/` so the folder contains both `ForeverQuickJoin.lua` and `ForeverQuickJoin_Host.lua` alongside `ForeverQuickJoin.toc`. Replace the previous version and `/reload` or restart.

Open using **`/qj`** or the minimap icon. **`/qj list`** opens the hosting view directly, and **`/qj find`** opens Find Groups.

## Find Groups (retained)

Choose a category and activity, click **Search**, sort by member count, filter by group composition/estimated role vacancies, view the Blizzard role icons, and use **Whisper to Join**. Search is only initiated by a physical click.

The solo default message is exactly:

`Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!`

Use **Reload Whisper Template** or `/qj reset` to restore the solo/party-aware default. Custom templates remain persistent per character. The **Preview:** label is now the normal UI text color; only the resulting message uses Blizzard's whisper color.

## List Group and Applicant Inbox (new)

1. Open the **List Group** tab, choose category and activity, and click **List Group**. To change an existing listing, use **Update Listing**; **Delist** removes it. These are native Blizzard Group Finder operations, initiated directly by each button.
2. Incoming whispers are collected in a **session-only queue**, even when the QuickJoin window is closed. Toggle **Capture incoming whispers** to pause. The inbox includes all regular whispers while enabled, not exclusively LFG applicants.
3. Applicants are sorted in **Tank**, **Healer**, **DPS**, then **Unknown** order. Each row displays Blizzard's role icon, the class icon when known, and an unread count. Click a row to see **only that character's messages** in the conversation panel.
4. The detail panel shows name, class, level, inferred/assigned role, known location, and a spec availability notice. Click a role button to override an incorrect inference.
5. **Reply** sends your own custom whisper. **Invite** requests a party invite. **Decline + Remove** submits the standard rejection whisper (`Sorry, we can't take you for this group. Good luck!`) and clears that applicant. **Dismiss** clears one applicant without messaging.
6. **Lookup /who** fills in the chat command for that person. Press **Enter** yourself. On a successful Who result, QuickJoin can update class, level and zone information.

### Player information: accuracy and restrictions

- **Class and level:** Usually available from `GetPlayerInfoByGUID()` when WoW provides the sender's GUID and player record; a `/who` result may supply missing class/level.
- **Role:** Generic whispers contain no verified role field. Only clear self-reports such as `Tank LFG`, `Healer here`, and `DPS LFG` are auto-classified. Ambiguous or unrelated messages stay **Unknown**. Correct a role manually using the role buttons.
- **Zone:** A whisper does not contain the sender's current location. The player must submit `/who` manually; a successful query can supply zone information.
- **Spec:** Not available through generic whisper events; QuickJoin shows **unknown**, not a fabricated specialization.
- **Protected/secret messages:** During restricted client states, WoW can prevent addon code from reading or grouping a whisper sender and message. These whispers continue to appear in normal chat and cannot be forced into the inbox.

### Privacy and capacity

Applicant conversations live only in **session memory** (up to **100 applicants**, last **35 messages** per applicant). Whisper histories are **not saved** to the disk, and disappear on `/reload` or logout. Capture is enabled by default, but can be disabled per character.

### Protected actions

The listing/update/delist actions require a permitted click and may still be blocked by the Forever client. The addon does not try to bypass this restriction. The **Lookup /who** control only **prepares text**; it does not run automated WHO requests. Invitations can require additional Blizzard confirmation. A chat send attempt is not a guarantee of delivery. Whispers exceeding **255 bytes** or attempted during client chat lockdown are refused.

Formal Group Finder application records are not yet included in the whisper inbox; this version routes actual chat whispers.

## Commands

- `/qj`: open/close
- `/qj list`: List Group / inbox
- `/qj find`: Find Groups
- `/qj reset`: restore default message
- `/qj activities`: refresh available activity metadata
- `/qj all`: include off-level activities
- `/qj retry`: re-enable a blocked Search button
- `/qj status`: diagnostics

## Verification

Lua syntax and mocked-client regression tests passed for the previous finder, whisper rendering, listing creation/update, applicant classification and role grouping, thread isolation, Who lookup preparation, invites, and declines. **The new UI has not been tested in the actual game client.**