# Forever QuickJoin

**Forever QuickJoin** is an in-game group finder and recruitment assistant for **World of Warcraft: Forever** (client 1.60.1; interface 16001). It helps you find a group, send one-click whispers, and manage people asking to join your group.

## Features

### Find Groups

- Search Blizzard's Group Finder directly by category and activity.
- See each group's activity, playstyle, size, and Blizzard tank/healer/DPS icons.
- Expand a group to inspect available member names, classes, levels, roles, specializations, and areas. Right-click a named member to prepare a manual `/who` query when their area is unknown.
- Keep the **large Party detected** panel visible while browsing or hosting, with a one-click **Review / Fix Roles** or **Change Roles** button.
- Select **Show all level ranges** beneath the category/activity menus when needed. **Advanced Filters** includes sorting, Space for Tank/Healer/DPS, Already has Tank/Healer, class and playstyle exclusions, group size, and whisperability/description restrictions.
- Click **Whisper to Join** to contact a group leader using your saved message.
- Contacted listings display a distinct **green Sent** indicator between their group-role counts and the Whisper button. Sent groups remain pinned at the top even after searching other activities or changing filters. If the client stops exposing a listing, QuickJoin keeps a **Sent*** marker on a cached row, with the Whisper button disabled until it verifies that the listing is still available. A confirmed delisting or a new listing with a different creation time clears the marker. **Sent means the whisper was submitted from QuickJoin, not that the recipient received or read it.**

### Party Roles

A large, persistent **Party detected** panel appears in the area below Search on **both** Find Groups and List Group. It shows current Tank / Healer / DPS totals with large Blizzard role icons, plus any unassigned members. **Review / Fix Roles** appears when confirmation is needed; otherwise, **Change Roles** opens the editor.

- QuickJoin detects party and raid members and reads Blizzard-assigned roles, names, classes, and levels.
- DPS assignments for multi-role classes (such as a Priest) are **flagged for review**, not assumed to be correct. An unavailable role is **Unknown**, not guessed from class.
- In **Party Role Manager**, choose **Tank**, **Healer**, or **DPS** for each member. The selected role appears next to the character using a sharper built-in Blizzard role icon. **Auto** clears an individual override and uses the role WoW currently reports; unknown roles require a choice. There are no bulk confirmation or reset buttons.
- Corrections immediately update the role counts and the `{role}` / `{party}` whisper placeholders. If a group whisper contains uncertain roles, QuickJoin opens the manager and requires you to confirm them first; there is no bypass button.
- Corrections are **local to your current group session**. They are cleared when the group disbands or a member leaves, and flagged for review if Blizzard's assignment changes. They do **not** edit other players' roles in WoW or require other players to install the addon.
- Open the manager directly with `/qj roles` or `/qj party`.

### List Group / Applicant Inbox

Use **Open Blizzard Listing** in the List Group header to create and manage your listing in Blizzard's protected UI. QuickJoin automatically collects incoming whispers while loaded in a separate, session-only inbox, grouped by self-reported Tank, Healer, DPS, or Unknown role. Select an applicant to see their conversation and known class/level details. Reply, invite, decline, dismiss, or prepare a manual `/who` lookup.

## Interface themes

Select **Forever** or **Modern** using the **Theme** controls at the top of either QuickJoin tab.

- **Forever** is the original WoW Forever-inspired interface: Blizzard borders, buttons, and typography.
- **Modern** uses a redesigned graphite interface with layered opaque panels, understated gray borders, cool-blue accents, clear primary-action buttons, and Blizzard's bundled narrow font. It is inspired by clean WoW UI suites such as ElvUI/Ellesmere; it does not require them or copy their assets.

Switching is **instant**: no `/reload` required. Your choice is saved per character. Theme changes apply to Find Groups, Advanced Filters, expanded rosters, the Party Role Manager, and the applicant inbox. Only QuickJoin's own windows are styled; Blizzard's Group Finder and other addons are not modified.

## Whisper messages

The solo default is:

`Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!`

With a party, the default also adds `Party: {party}`. `{party}` includes **other** members' names, levels, classes, and QuickJoin-confirmed roles. Supported placeholders: `{level}`, `{class}`, `{role}`, `{activity}`, `{location}`, `{name}`, `{party}`, and `{partycount}`. Click **Reload Whisper Template** to restore the appropriate default. Custom messages are preserved until you reset them.

## Install and update

In **WowUp**, select WoW Forever, choose **Install from URL**, and enter:

`https://github.com/taadaa95/ForeverQuickJoin`

For manual installation, download a release from [GitHub Releases](https://github.com/taadaa95/ForeverQuickJoin/releases) and extract the `ForeverQuickJoin` folder into `_forever_/Interface/AddOns/`. Reload the UI with `/reload`. Future versioned releases are automatically packaged for WowUp from the TOC version.

## Slash commands

| Command | Function |
| --- | --- |
| `/qj` | Toggle QuickJoin |
| `/qj find` | Find Groups |
| `/qj list` | List Group and Applicant Inbox |
| `/qj roles` or `/qj party` | Open Party Role Manager |
| `/qj reset` | Restore the solo/party whisper default |
| `/qj all` | Toggle all activity level ranges |
| `/qj activities` | Refresh activity metadata |
| `/qj retry` | Re-enable a search blocked by the game |
| `/qj status` | Search and addon diagnostics |

## Important limitations

- Blizzard controls search, listing creation, whispers, invites, and who-queries. Protected actions cannot be run automatically in the background; listing creation occurs in Blizzard's own window.
- Player details may be withheld by the client. Missing specs, roles, or locations are shown as unknown; `/who` requires you to submit the prepared query yourself.
- Party role confirmations are **not talent/spec detection**. Verify the roles with your party; QuickJoin does not secretly inspect another player's build or alter their assigned group role.
- The applicant inbox, party role overrides, and **Sent tracking** are session-only. Sent markers survive searches and filter changes, but are cleared on logout/reload. When a group is no longer included in the current server search, its cached Sent row is **not proof it is still available**; the client must explicitly confirm delisting for automatic removal. Your filters, theme, minimap position, and whisper template are saved per character.
