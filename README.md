# Forever QuickJoin

**Forever QuickJoin** is an in-game group finder and recruitment assistant for **World of Warcraft: Forever** (client 1.60.1; interface 16001). It helps you find a group, send one-click whispers, and manage people asking to join your group.

## Features

### Find Groups

- Search Blizzard's Group Finder directly by category and activity.
- Click **Whisper to Join** to contact a group leader using your saved message.
- See each group's activity, playstyle, size, and Blizzard tank/healer/DPS icons.
- **Friends and guildmates:** Listings containing people you know display colored `F:` (character friends), `B:` (Battle.net friends), and `G:` (guildmates) counts beneath the leader's name. Hover over a listing for the full explanations. Counts are shown only when the client provides them; friend categories may overlap.
- Expand a group to inspect available member names, classes, levels, roles, specializations, and areas. Right-click a named member to prepare a manual `/who` query when their area is unknown.

- Contacted listings display a distinct **green Sent** indicator. When the contacted leader replies, it becomes **Reply** and the Applications tab shows the unread conversation. Sent groups remain pinned at the top even after searching other activities or changing filters.

### My Applications & reply tracking

The **Applications** tab (or `/qj apps`) shows the groups you've contacted through QuickJoin and your outgoing messages. Replies from a matching leader are attached to that conversation, and an unread counter appears on the Applications tab. Open a conversation to mark its replies read, or click **Reply to leader** to prepare a whisper in Blizzard chat (press Enter yourself to send). Follow-up whispers to the same active listing stay in the same thread.

### List Group / Applicant Inbox

Use **Open Blizzard Listing** in the List Group header to create and manage your listing in Blizzard's protected UI. QuickJoin automatically collects incoming whispers while loaded in a separate, session-only inbox, grouped by self-reported Tank, Healer, DPS, or Unknown role. Select an applicant to see their conversation and known class/level details. Reply, invite, decline, dismiss, or prepare a manual `/who` lookup.

## Interface themes

Select **Forever** or **Modern** using the **Theme** controls at the top of either QuickJoin tab.

## Whisper messages

The solo default is:

`Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!`

With a party, the default also adds `Party: {party}`. `{party}` includes **other** members' names, levels, classes, and QuickJoin-confirmed roles. Supported placeholders: `{level}`, `{class}`, `{role}`, `{activity}`, `{location}`, `{name}`, `{party}`, and `{partycount}`. Click **Reload Whisper Template** to restore the appropriate default. Custom messages are preserved until you reset them.

## Slash commands

 `/qj` Toggle QuickJoin 

## Important limitations

- Blizzard controls search, listing creation, whispers, invites, and who-queries. Protected actions cannot be run automatically in the background; listing creation occurs in Blizzard's own window.
- Player details may be withheld by the client. Missing specs, roles, or locations are shown as unknown; `/who` requires you to submit the prepared query yourself.
- Party role confirmations are **not talent/spec detection**. Verify the roles with your party; QuickJoin does not secretly inspect another player's build or alter their assigned group role.
- The applicant inbox, applications/replies, party role overrides, and **Sent tracking** are session-only. Sent markers survive searches and filter changes, but are cleared on logout/reload. When a group is no longer included in the current server search, its cached Sent row is **not proof it is still available**; the client must explicitly confirm delisting for automatic removal. Your filters, theme, minimap position, and whisper template are saved per character.
