# Forever QuickJoin

**Forever QuickJoin** is an in-game group finder and recruitment assistant for **World of Warcraft: Forever** (client 1.60.1; interface 16001). It helps you find a group, send one-click whispers, and manage people asking to join your group.

## Features

### Find Groups

- Search Blizzard's Group Finder directly by category and activity.
- See each group's activity, playstyle, size, and Blizzard tank/healer/DPS icons.
- Expand a group to inspect available member names, classes, levels, roles, specializations, and areas. Right-click a named member to prepare a manual `/who` query when their area is unknown.
- Keep the large **Party detected** panel visible in both Find Groups and List Group, with an obvious **Review / Fix Roles** or **Change Roles** button.
- Use **Advanced Filters** for *all* finder options: Show all level ranges, sorting by member count, Space for Tank/Healer/DPS, Already has Tank/Healer, class and playstyle exclusions, size, description, and whisperability.
- Click **Whisper to Join** to contact a group leader using your saved message.

### Party Roles

A larger **Party detected** panel occupies the area below Search in **both** QuickJoin tabs. It displays the Tank / Healer / DPS counts using large Blizzard role icons, plus any unassigned members. Select **Review / Fix Roles** when QuickJoin flags uncertain assignments, or **Change Roles** at any time.

- QuickJoin detects party and raid members and reads Blizzard-assigned roles, names, classes, and levels.
- DPS assignments for multi-role classes (such as a Priest) are **flagged for review**, not assumed to be correct. An unavailable role is **Unknown**, not guessed from class.
- In **Party Role Manager**, choose **Tank**, **Healer**, or **DPS** for each member. A large icon beside the character reflects the chosen role. **Confirm detected roles** affirms known assignments; **Auto** or **Reset to WoW** discards overrides. Unknown roles must be assigned a valid role before confirmation.
- Corrections immediately update the role counts and the `{role}` / `{party}` whisper placeholders. QuickJoin requires uncertain roles to be reviewed before sending a group-composition whisper; the one-time bypass has been removed.
- Corrections are **local to your current group session**. They are cleared when the group disbands or a member leaves, and flagged for review if Blizzard's assignment changes. They do **not** edit other players' roles in WoW or require other players to install the addon.
- Open the manager directly with `/qj roles` or `/qj party`.

### List Group / Applicant Inbox

Use **Open Blizzard Listing** to create and manage your listing in Blizzard's protected UI. QuickJoin collects incoming whispers in a separate, session-only inbox, grouped by self-reported Tank, Healer, DPS, or Unknown role. Select an applicant to see their conversation and known class/level details. Reply, invite, decline, dismiss, or prepare a manual `/who` lookup.

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
- The applicant inbox and party role overrides are session-only. Your filters, minimap position, and whisper template are saved per character.
