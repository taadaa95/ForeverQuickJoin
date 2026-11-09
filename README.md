# Forever QuickJoin

**Forever QuickJoin** is a Group Finder companion addon for **World of Warcraft: Forever** (client 1.60.1, interface 16001). It helps you find dungeon and raid groups quickly, send a customized request to join, and organize recruitment whispers when you're the group leader.

## Features

### Find Groups

- Browse groups by category and activity, with an optional **Show all level ranges** checkbox.
- See playstyle (Learning, Relaxed, Competitive, Carry Offered), current group size, and Blizzard tank/healer/DPS role icons.
- Click a listing to expand its member roster, including class, role, level, specialization and location **when the game provides them**. **Right-click a named member** to prepare a targeted `/who` location lookup; press **Enter** in chat to submit.
- Sort by total group members and filter by available tank, healer or DPS positions, or groups already containing a tank or healer.
- **Advanced Filters:** exclude groups containing any of WoW Forever's nine classes; exclude one or more playstyles; set a maximum group size; or show only groups with descriptions or whisperable leaders. Class exclusions require a readable roster, so groups with unknown member classes are hidden while class exclusions are active.
- Click **Whisper to Join** to send your customizable message without typing it each time.

### Looking up an unknown area

If an expanded group member shows **Area unknown**, right-click their member card. QuickJoin prepares a targeted `/who n-"Character"` command in chat; **press Enter** to run it. When the server returns a matching result through the Who list, QuickJoin fills in the area and labels it **(via /who)**. A Who location is only a momentary snapshot, not live tracking, and expires from the addon’s temporary display cache after five minutes.

WoW can restrict or throttle Who requests; some searches return no result, or only appear in Blizzard’s Who interface. There is **no automatic background polling**, and QuickJoin never sends Who searches without you submitting the command. The name must be available in the group roster—hidden players cannot be looked up individually. For this lookup QuickJoin requests that WHO results be shown in Blizzard's Who interface, which may also open that window.

### List Group / Applicant Inbox

- Use **Open Blizzard Listing** to create or manage your listing in WoW's native Group Finder interface.
- Collect incoming whispers in an in-session applicant inbox, grouped by Tank, Healer, DPS and Unknown.
- Select an applicant to read their conversation and available character details, change the assigned role, reply, invite, decline or dismiss them.
- Prepare a manual `/who` lookup for additional information when available.

### Whisper templates

When you're solo, the default template is:

`Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!`

The default adjusts when you're in a group to include other party members. Click **Reload Whisper Template** to restore it after editing. Supported tokens are `{level}`, `{class}`, `{role}`, `{activity}`, `{location}`, `{name}`, `{party}`, and `{partycount}`.

## Installation and updates

**WowUp:** In WowUp, choose your WoW Forever installation, then use **Get Addons → Install from URL** with `https://github.com/taadaa95/ForeverQuickJoin`. Installing from the repository allows WowUp to track new GitHub releases.

**Manual:** Download the newest `ForeverQuickJoin-vX.Y.Z-forever.zip` from [Releases](https://github.com/taadaa95/ForeverQuickJoin/releases). Extract it into your Forever `Interface/AddOns` folder so the files are at `Interface/AddOns/ForeverQuickJoin/ForeverQuickJoin.toc`. Type `/reload` in-game.

## Commands

| Command | Action |
|---|---|
| `/qj` | Open or close QuickJoin |
| `/qj find` | Open Find Groups |
| `/qj list` | Open List Group / applicant inbox |
| `/qj reset` | Restore the default whisper template |
| `/qj all` | Toggle showing activities across all level ranges |
| `/qj activities` | Refresh activity metadata |
| `/qj retry` | Re-enable Search after a blocked API request |
| `/qj status` | Display diagnostic information |

You can also open QuickJoin using its draggable minimap button.

## Good to know

- Searches are initiated by clicking **Search**; the addon does not search automatically in the background.
- WoW restricts some Group Finder actions. Group listing creation and editing happen in Blizzard's own interface.
- The game may hide roster data or a player's role, level, specialization, or location. Unknown information is not guessed.
- Incoming recruitment whispers are stored **only for the current game session**; they aren't saved permanently. Role identification from incoming whispers is best-effort and can be corrected manually.

This is an independent community addon, not affiliated with Blizzard Entertainment.