-- Forever QuickJoin 0.7.1 -- revised party UI, accessible filters, sent badge, and modern styling.
-- C_LFGList.Search is restricted: call it ONLY from the player's Search button
-- OnClick, using a valid category ID and the activity list exactly like Blizzard
-- and LFG Forever. NEVER call it on login/show/refresh/timer/dropdown callbacks.
-- A client may still block the action; retain cached-results fallback.
local addonName = ...
local PREFIX = "|cff62c8efQuickJoin|r: "
local PREVIOUS_DEFAULT_MESSAGE = "Level {level} {class} {role} LFG {activity}, can summon. Inv pls!"
-- The canonical SOLO default is intentionally exactly this string.
local DEFAULT_MESSAGE = "Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!"
-- Grouped variant is selected by the Reload Whisper Template button (and
-- automatically while the default is active and group membership changes).
local PARTY_DEFAULT_MESSAGE = "Level {level} {class} {role} LFG {activity}, Current location: {location}, Party: {party}, inv please!"
local OLD_LOCATION_DEFAULT = "Level {level} {class} {role} LFG {activity} - current location: {location}, inv please!"
-- Exact built-in Blizzard role sprite and texcoords, also used by
-- LFGBulletinBoard/LfgToolList.lua (no external image dependencies).
local ROLE_ICONS = {
    TANK = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:17:17:0:-1:64:64:0:19:22:41|t",
    HEALER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:17:17:0:-1:64:64:20:39:1:20|t",
    DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:17:17:0:-1:64:64:20:39:22:41|t",
}
local PAGE_SIZE = 9
local COOLDOWN = 3
-- /who zones are snapshots. Never display session-cached positions indefinitely.
local WHO_ZONE_TTL = 300

local db, window, categoryDropdown, activityDropdown, searchButton
local sortDropdown, locationLabel, minimapButton, clearFilterButton, templateResetButton, allLevelsButton
local advancedButton, advancedPanel, advancedMaxMembersDropdown
local advancedClassButtons, advancedPlaystyleButtons, advancedCheckButtons = {}, {}, {}
local filterButtons = {}
local statusLabel, pageLabel, messageBox, previewLabel, previewTitleLabel, prevButton, nextButton
local rows = {}
local resultsViewport, resultsCanvas
local state = {
    categoryID = nil,
    categoryName = nil,
    activityID = nil,
    activityName = nil,
    categories = {},
    activities = {},
    results = {},
    cachedResults = {},
    page = 1,
    expandedResultID = nil,
    totalInCache = 0,
    rosterClassCache = {},
    searching = false,
    searchBlocked = false,
    searchAttemptActive = false,
    searchAttemptAt = nil,
    searchActivityIDs = {},
    whisperAttemptActive = false,
    whisperBlocked = false,
    pendingWho = nil,
    whoZones = {}, -- session-only Who results, keyed by player identity
    sentByID = {}, -- session-only attempted whispers by search result id
    sentByListing = {}, -- keep sent markers across refreshed search result IDs
    sentVirtualIDs = {}, -- virtual cached rows for sent groups absent from new search scopes
    pinnedRealIDs = {}, -- live sent groups bypass local filters and stay visible
    nextSentVirtualID = -1,
}
local lastWhisperTarget, lastWhisperTime
local Readable -- declared early for the sent-listing identity helpers
local UpdatePages -- shared by message sends and rendered search results

-- A listing may receive a different result ID after a new search. The server
-- does not expose a permanent listing GUID on every Forever client, so use the
-- leader + activity + group title, optionally backed by the listing age.
-- Never interpret a filtered-out or missing search result as a disbanded group.
local function SentIdentity(id, info)
    if type(info) ~= "table" then return nil end
    local leader = Readable(info.leaderName)
    local ids = Readable(info.activityIDs)
    local activity = type(ids) == "table" and Readable(ids[1]) or Readable(info.activityID)
    if type(leader) ~= "string" or leader == "" then return nil end
    if type(activity) ~= "number" then activity = 0 end
    return leader:lower() .. "\031" .. tostring(activity)
end

local function SentStartTime(info)
    local age = type(info) == "table" and Readable(info.age) or nil
    if type(age) == "number" and age >= 0 and age < 604800 and type(GetTime) == "function" then
        return GetTime() - age
    end
end

local function RemoveSent(record)
    if not record then return end
    for id,other in pairs(state.sentByID) do
        if other == record then state.sentByID[id] = nil end
    end
    if record.virtualID then state.sentVirtualIDs[record.virtualID] = nil end
    for id in pairs(state.pinnedRealIDs) do
        if state.sentByID[id] == nil then state.pinnedRealIDs[id] = nil end
    end
    if record.key and state.sentByListing[record.key] == record then state.sentByListing[record.key] = nil end
end

local function MatchSent(id, info)
    if type(info) ~= "table" then return nil end
    if Readable(info.isDelisted) == true and state.sentByID[id] then
        RemoveSent(state.sentByID[id])
        return nil
    end
    local key = SentIdentity(id, info)
    local record = state.sentByID[id]
    if record and record.key ~= key then record = nil end
    if not record and key then record = state.sentByListing[key] end
    if not record then return nil end
    -- A matching leader can make a *new* group with the same activity/title.
    -- Its age will reset; do not mark that brand-new listing as contacted.
    local started = SentStartTime(info)
    if record.started and started and math.abs(record.started - started) > 90 then
        RemoveSent(record)
        return nil
    end
    if Readable(info.isDelisted) == true then
        RemoveSent(record)
        return nil
    end
    state.sentByID[id] = record
    record.id = id
    return record
end

local function SnapshotSentInfo(info, id)
    local snapshot = {}
    for _,field in ipairs({"leaderName","numMembers","name","comment","generalPlaystyle",
        "isDelisted","hasSelf","age"}) do
        local value = Readable(info[field])
        if type(value)=="string" or type(value)=="number" or type(value)=="boolean" then
            snapshot[field] = value
        end
    end
    local activities = Readable(info.activityIDs)
    snapshot.activityIDs = {}
    if type(activities)=="table" then
        for i=1,math.min(#activities,20) do
            local activity = Readable(activities[i])
            if type(activity)=="number" then table.insert(snapshot.activityIDs,activity) end
        end
    end
    if #snapshot.activityIDs==0 and type(Readable(info.activityID))=="number" then
        snapshot.activityIDs[1]=Readable(info.activityID)
    end
    if C_LFGList and type(C_LFGList.GetSearchResultMemberCounts)=="function" then
        local ok,counts=pcall(C_LFGList.GetSearchResultMemberCounts,id)
        counts=ok and Readable(counts) or nil
        if type(counts)=="table" then
            snapshot.roleCounts={}
            for _,role in ipairs({"TANK","HEALER","DAMAGER"}) do
                if type(Readable(counts[role]))=="number" then
                    snapshot.roleCounts[role]=Readable(counts[role])
                end
            end
        end
    end
    snapshot._qjCached=true
    return snapshot
end

local function MarkSent(id, info, leader)
    local key = SentIdentity(id, info)
    if not key then return end
    local old = state.sentByListing[key]
    if old then RemoveSent(old) end
    local virtualID=state.nextSentVirtualID
    state.nextSentVirtualID=virtualID-1
    local record = { id = id, key = key, leader = leader, virtualID=virtualID,
        snapshot=SnapshotSentInfo(info,id),
        started = SentStartTime(info), at = type(GetTime) == "function" and GetTime() or 0 }
    state.sentVirtualIDs[virtualID]=record
    state.pinnedRealIDs[id] = true
    state.sentByID[id] = record
    state.sentByListing[key] = record
end

local function ResultInfo(id)
    -- Negative IDs never go to Blizzard's APIs. They represent the last
    -- known snapshot of a sent group whose current search scope omits it.
    if type(id)=="number" and id<0 then
        local rec=state.sentVirtualIDs[id]
        return rec and rec.snapshot or nil, false
    end
    if not C_LFGList or type(C_LFGList.GetSearchResultInfo)~="function" then
        return nil,false
    end
    local ok,info=pcall(C_LFGList.GetSearchResultInfo,id)
    return ok and Readable(info) or nil, ok and type(Readable(info))=="table"
end

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
    end
end

-- Since Forever 1.60.1, the search-result APIs can return *secret* values
-- during chat-messaging lockdown. Do not compare/format/index these values.
Readable = function(value)
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then
        return nil
    end
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return nil
    end
    return value
end

local function Truncate(value, maxLen)
    value = tostring(value or "")
    if #value <= maxLen then return value end
    return value:sub(1, maxLen - 3) .. "..."
end

local function CurrentTemplate()
    if db and type(db.template) == "string" then return db.template end
    return DEFAULT_MESSAGE
end

local function GetRole()
    -- Forever uses C_LFGListRoles, not the retail GetLFGRoles() checkbox API.
    local roles = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
    if roles then
        if roles.tank and not roles.healer and not roles.dps then return "tank" end
        if roles.healer and not roles.tank and not roles.dps then return "healer" end
        if roles.dps then return "DPS" end
    end
    return "DPS"
end

local function ActivityDisplayName(activityID)
    if type(activityID) ~= "number" or not C_LFGList or not C_LFGList.GetActivityInfoTable then
        return nil
    end
    local info = C_LFGList.GetActivityInfoTable(activityID)
    if not info then return nil end
    -- The helper is supplied by Blizzard_GroupFinder_VanillaStyle.
    if type(LFGUtil_GetActivityInfoName) == "function" then
        return LFGUtil_GetActivityInfoName(info)
    end
    return info.fullName or info.shortName or info.name or ("Activity " .. activityID)
end

local function ResultActivityName(info)
    local ids = Readable(info and info.activityIDs)
    if type(ids) == "table" and type(ids[1]) == "number" then
        return ActivityDisplayName(ids[1]) or "group"
    end
    return state.activityName or "group"
end

-- Group Finder's generalPlaystyle enum is distinct from its older playstyle
-- field. Forever 1.60.1 uses 1=Learning, 2=Relaxed, 3=Competitive,
-- 4=Carry Offered. Prefer Blizzard's localized display strings; the English
-- fallbacks allow the label to work if the UI helper is not loaded yet.
local GENERAL_PLAYSTYLE_NAMES = {
    [1] = "Learning", [2] = "Relaxed", [3] = "Competitive", [4] = "Carry Offered",
}
local function ResultPlaystyle(info)
    local value = Readable(info and info.generalPlaystyle)
    if type(value) ~= "number" then return "Unavailable" end
    if value == 0 then return "Not set" end
    if not GENERAL_PLAYSTYLE_NAMES[value] then return "Unknown" end
    if type(GetGeneralPlaystyleString) == "function" then
        local ok, label = pcall(GetGeneralPlaystyleString, value)
        label = ok and Readable(label) or nil
        if type(label) == "string" and label ~= "" then return label end
    end
    local global = Readable(_G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. value])
    if type(global) == "string" and global ~= "" then return global end
    return GENERAL_PLAYSTYLE_NAMES[value]
end

-- The location token is looked up when constructing the whisper, not cached.
-- GetZoneText reports the main zone (e.g. Stormwind City); subzones are
-- deliberately excluded so moving between districts doesn't alter the message.
local function CurrentLocation()
    local zone = type(GetZoneText) == "function" and Readable(GetZoneText()) or nil
    if type(zone) ~= "string" or zone == "" then
        zone = type(GetRealZoneText) == "function" and Readable(GetRealZoneText()) or nil
    end
    if type(zone) ~= "string" or zone == "" then
        zone = type(GetMinimapZoneText) == "function" and Readable(GetMinimapZoneText()) or nil
    end
    if type(zone) ~= "string" or zone == "" then return "Unknown location" end
    return zone
end

-- All party details use the live player/party/raid unit APIs. Never infer
-- a member's role from their class: an unassigned role stays "Unassigned".
-- Forever has secret unit-identity values in restricted states; check them
-- before formatting or concatenating their contents.
local function ReadUnitValue(func, unit)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, unit)
    if not ok then return nil end
    return Readable(value)
end

local function GroupSize()
    if type(GetNumGroupMembers) ~= "function" then return 0 end
    local ok, size = pcall(GetNumGroupMembers)
    size = ok and Readable(size) or nil
    if type(size) ~= "number" or size < 2 then return 0 end
    return math.min(math.floor(size), 40)
end

local ROLE_NAMES = {TANK="Tank", HEALER="Healer", DAMAGER="DPS", NONE="Unassigned"}
local function PartyRoster()
    local total = GroupSize()
    if total == 0 then return {}, 0 end
    local raid = type(IsInRaid) == "function" and Readable(IsInRaid()) == true
    local slots = raid and total or math.min(total - 1, 4)
    local roster = {}
    for i = 1, slots do
        local unit = (raid and "raid" or "party") .. i
        local exists = ReadUnitValue(UnitExists, unit)
        local isSelf
        if type(UnitIsUnit) == "function" then
            local ok, yes = pcall(UnitIsUnit, unit, "player")
            if ok then isSelf = Readable(yes) end
        else
            -- Without UnitIsUnit, partyN tokens do not include the player;
            -- raid tokens might. Avoid guessing which raid unit is self.
            isSelf = raid and nil or false
        end
        if exists == true and isSelf == false then
            local name = ReadUnitValue(UnitName, unit)
            local level = ReadUnitValue(UnitLevel, unit)
            local class = ReadUnitValue(UnitClass, unit)
            local role = ReadUnitValue(UnitGroupRolesAssigned, unit)
            local resolved = ForeverQuickJoinParty and ForeverQuickJoinParty.RoleFor
                and ForeverQuickJoinParty.RoleFor(unit) or nil
            if type(resolved) == "string" then role = resolved end
            table.insert(roster, {
                name=type(name) == "string" and name ~= "" and name or "Unknown member",
                level=type(level) == "number" and level > 0 and tostring(level) or "?",
                class=type(class) == "string" and class ~= "" and class or "Unknown class",
                role=ROLE_NAMES[role] or "Unassigned",
            })
        end
    end
    return roster, total
end

local function FormatRoster(roster, compact)
    local list = {}
    for _, member in ipairs(roster) do
        if compact then
            local shortRole = ({Tank="T", Healer="H", DPS="D", Unassigned="?"})[member.role] or "?"
            list[#list+1] = ("%s L%s %s %s"):format(member.name, member.level, member.class, shortRole)
        else
            list[#list+1] = ("%s (Lv%s %s %s)"):format(member.name, member.level, member.class, member.role)
        end
    end
    return table.concat(list, "; ")
end

local function DefaultTemplate()
    return GroupSize() > 0 and PARTY_DEFAULT_MESSAGE or DEFAULT_MESSAGE
end

local function BuildMessage(info)
    local class = Readable(UnitClass("player")) or "player"
    local roster, groupSize = PartyRoster()
    local playerRole = GetRole()
    if ForeverQuickJoinParty and ForeverQuickJoinParty.RoleFor then
        local effective = ForeverQuickJoinParty.RoleFor("player")
        if effective == "TANK" then playerRole = "Tank"
        elseif effective == "HEALER" then playerRole = "Healer"
        elseif effective == "DAMAGER" then playerRole = "DPS"
        elseif effective == "UNKNOWN" then playerRole = "Unassigned" end
    end
    local parts = {
        level = tostring(Readable(UnitLevel("player")) or "?"),
        class = class,
        role = playerRole,
        activity = ResultActivityName(info),
        name = Readable(UnitName("player")) or "player",
        location = CurrentLocation(),
        party = FormatRoster(roster),
        partycount = tostring(groupSize > 0 and groupSize or 1),
    }
    -- Any member whose data has not loaded yet must not disappear silently.
    -- Show the number of missing members instead of inventing identities.
    local expected = math.max(0, groupSize - 1)
    local missing = math.max(0, expected - #roster)
    if missing > 0 then
        local suffix = ("%d other member%s (details unavailable)"):format(missing, missing == 1 and "" or "s")
        parts.party = parts.party ~= "" and (parts.party .. "; " .. suffix) or suffix
    end
    local template = CurrentTemplate()
    local function Resolve()
        return (template:gsub("{([%w_]+)}", function(key)
            key = key:lower()
            return parts[key] or "{" .. key .. "}"
        end):gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local message = Resolve()
    -- Default group messages are designed to fit a 255-byte whisper. Long
    -- names in raids may not; compress role labels if needed and, if still
    -- too long, refuse rather than silently omitting party members.
    if #message > 255 and template:find("{party}", 1, true) then
        parts.party = FormatRoster(roster, true)
        if missing > 0 then
            local suffix = ("+%d unavailable"):format(missing)
            parts.party = parts.party ~= "" and (parts.party .. "; " .. suffix) or suffix
        end
        message = Resolve()
    end
    return message
end

local function Status(msg)
    if statusLabel then statusLabel:SetText(msg or "") end
end

local function UpdatePreview()
    if previewLabel then
        -- Match the player's actual Blizzard whisper chat color (including
        -- custom chat colors). The pink fallback supports clients that do not
        -- expose ChatTypeInfo during early addon initialization.
        local color = type(ChatTypeInfo) == "table" and ChatTypeInfo["WHISPER"] or nil
        local r, g, b = 1, 0.5, 1
        if type(color) == "table" and type(color.r) == "number"
            and type(color.g) == "number" and type(color.b) == "number" then
            r, g, b = color.r, color.g, color.b
        end
        previewLabel:SetTextColor(r, g, b)
        -- Never truncate: the {location} value is often near the end.
        previewLabel:SetText(BuildMessage(nil))
    end
    if locationLabel then
        local partySize = GroupSize()
        local groupState = partySize > 0 and ("Party/raid: %d total (including you)"):format(partySize)
            or "Solo"
        locationLabel:SetText("Current location: " .. CurrentLocation() .. "   |   " .. groupState)
    end
end

local function SendWhisper(resultID)
    if not C_LFGList or not C_LFGList.GetSearchResultInfo then
        Print("Group Finder API is unavailable.")
        return
    end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or not info then
        Print("Group expired; search again.")
        return
    end
    local removed = Readable(info.isDelisted)
    if removed == nil or removed then
        Print("Listing is unavailable; search again.")
        return
    end
    local name = Readable(info.leaderName)
    if type(name) ~= "string" or name == "" then
        Print("Leader name is hidden by the client right now; no message sent.")
        return
    end
    local selfListing = Readable(info.hasSelf)
    if selfListing == nil or selfListing then
        Print("Cannot send to your own or an unavailable group.")
        return
    end
    local count = Readable(info.numMembers)
    if type(count) ~= "number" or count < 1 then
        Print("This listing is unavailable.")
        return
    end
    -- A wrong party role is worse than an extra click. Review uncertain
    -- assignments before sending group composition to a group leader.
    local template = CurrentTemplate()
    if GroupSize() > 0 and (template:find("{party}",1,true) or template:find("{role}",1,true))
        and ForeverQuickJoinParty and ForeverQuickJoinParty.NeedsReview
        and ForeverQuickJoinParty.NeedsReview() > 0 then
        Status("Confirm each uncertain party role before whispering a group leader.")
        ForeverQuickJoinParty.Open()
        return
    end
    local message = BuildMessage(info)
    if message == "" then
        Print("Enter a message template first.")
        return
    end
    if #message > 255 then
        Print("Whisper exceeds 255 characters. Shorten your message.")
        return
    end
    local now = GetTime()
    if lastWhisperTarget == name and lastWhisperTime and now - lastWhisperTime < COOLDOWN then
        Print("Already whispered this leader recently.")
        return
    end
    -- Forever marks chat messaging as restricted during some client states.
    -- Never attempt the call when lockdown is reported. pcall does NOT
    -- bypass a protected / restricted WoW action.
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        Status("Chat messaging is temporarily locked; no whisper sent.")
        return
    end
    local sender = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(sender) ~= "function" then
        Print("The client chat API is unavailable.")
        return
    end
    -- Send directly on the user's button click, following LFG Forever's
    -- working Ask to Join pattern. A restricted action may still be denied
    -- by the game; ADDON_ACTION_BLOCKED handles diagnostics below.
    state.whisperAttemptActive = true
    state.whisperBlocked = false
    sender(message, "WHISPER", nil, name)
    state.whisperAttemptActive = false
    if state.whisperBlocked then return end
    lastWhisperTarget, lastWhisperTime = name, now
    MarkSent(resultID, info, name)
    if UpdatePages and window and window:IsShown() then UpdatePages() end
    Status("Whisper submitted to " .. name .. " (Sent marks submission, not confirmed delivery).")
end

-- Group composition from the same role-count API used by Blizzard's Browse
-- display and LFG Bulletin Board. Counts are already aggregated by the client;
-- don't guess them from numMembers or individual players' role preferences.
local function GroupComposition(resultID, info)
    local num = Readable(info and info.numMembers)
    local total = type(num) == "number" and num >= 0 and tostring(num) or "?"
    if not C_LFGList or type(C_LFGList.GetSearchResultMemberCounts) ~= "function" then
        return total .. " players  |  roles unavailable"
    end
    local ok, counts
    if info and info._qjCached then
        ok,counts=true,info.roleCounts
    else
        ok,counts=pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
    end
    counts = ok and Readable(counts) or nil
    if type(counts) ~= "table" then
        return total .. " players  |  roles unavailable"
    end
    local tank, heal, damage = Readable(counts.TANK), Readable(counts.HEALER), Readable(counts.DAMAGER)
    if type(tank) ~= "number" or type(heal) ~= "number" or type(damage) ~= "number" then
        return total .. " players  |  roles unavailable"
    end
    -- Blizzard's own tank/healer/DPS icons instead of the written role names.
    -- Keep numeric counts visible, including zero for a missing role.
    local text = ("%s total  %s%d  %s%d  %s%d"):format(
        total, ROLE_ICONS.TANK, tank, ROLE_ICONS.HEALER, heal,
        ROLE_ICONS.DAMAGER, damage)
    local unassigned = Readable(counts.NOROLE)
    if type(unassigned) == "number" and unassigned > 0 then
        text = text .. ("  Other %d"):format(unassigned)
    end
    return text
end

-- Role availability criteria use Blizzard's group role counts; there is no
-- reliable server-provided flag that says "this leader wants one more tank".
-- For dungeons we use the standard 1/1/3 party targets. For common raid sizes
-- these are suggested compositions, not guaranteed recruitment needs.
local ROLE_TARGETS = {
    [5] = {TANK=1, HEALER=1, DAMAGER=3},
    [10] = {TANK=2, HEALER=3, DAMAGER=5},
    [20] = {TANK=3, HEALER=5, DAMAGER=12},
    [40] = {TANK=4, HEALER=10, DAMAGER=26},
}
local function GetMaxMembers(info)
    local ids = Readable(info and info.activityIDs)
    if type(ids) ~= "table" then return nil end
    local maxMembers
    for _, activityID in ipairs(ids) do
        if type(Readable(activityID)) == "number" and C_LFGList and C_LFGList.GetActivityInfoTable then
            local ok, activity = pcall(C_LFGList.GetActivityInfoTable, activityID)
            activity = ok and Readable(activity) or nil
            if type(activity) == "table" then
                local cap = Readable(activity.maxNumPlayers)
                if type(cap) == "number" and cap >= 2 then
                    -- When a listing supports several activities, use the
                    -- largest possible group size, not an arbitrary first.
                    maxMembers = math.max(maxMembers or 0, cap)
                elseif Readable(activity.categoryID) == 2 then
                    maxMembers = math.max(maxMembers or 0, 5)
                end
            end
        end
    end
    return maxMembers
end

local function GetCounts(resultID)
    if not C_LFGList or not C_LFGList.GetSearchResultMemberCounts then return nil end
    local ok, result = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
    result = ok and Readable(result) or nil
    if type(result) ~= "table" then return nil end
    local counts = {}
    for _, role in ipairs({"TANK", "HEALER", "DAMAGER"}) do
        local value = Readable(result[role])
        if type(value) ~= "number" or value < 0 then return nil end
        counts[role] = value
    end
    return counts
end

local CLASS_OPTIONS = {
    {"WARRIOR", "Warrior"}, {"PALADIN", "Paladin"},
    {"HUNTER", "Hunter"}, {"ROGUE", "Rogue"},
    {"PRIEST", "Priest"}, {"SHAMAN", "Shaman"},
    {"MAGE", "Mage"}, {"WARLOCK", "Warlock"}, {"DRUID", "Druid"},
}
local ADVANCED_PLAYSTYLES = {
    {1, "Learning"}, {2, "Relaxed"},
    {3, "Competitive"}, {4, "Carry Offered"},
}
local ADVANCED_MAX_MEMBERS = {
    {0, "Any group size"}, {1, "1 member"}, {2, "2 members"},
    {3, "3 members"}, {4, "4 members"}, {5, "5 members"},
    {10, "10 or fewer"}, {20, "20 or fewer"}, {40, "40 or fewer"},
}

local function MemberClassToken(resultID, index)
    if not C_LFGList then return nil end
    if type(C_LFGList.GetSearchResultPlayerInfo) == "function" then
        local ok, info = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, index)
        info = ok and Readable(info) or nil
        if type(info) == "table" then
            local token = Readable(info.classFilename)
            if type(token) == "string" and token ~= "" then return token:upper() end
        end
    end
    if type(C_LFGList.GetSearchResultMemberInfo) == "function" then
        local ok, _, token = pcall(C_LFGList.GetSearchResultMemberInfo, resultID, index)
        token = ok and Readable(token) or nil
        if type(token) == "string" and token ~= "" then return token:upper() end
    end
    return nil
end

-- Reads actual member classes, caching them until the next native result update.
-- Class exclusions require a complete readable roster. Unknown member classes
-- cannot establish that a filtered-out class is absent.
local function RosterClasses(resultID, numMembers)
    local cached = state.rosterClassCache[resultID]
    if cached and cached.numMembers == numMembers then return cached end
    local roster = {numMembers = numMembers, classes = {}, unknown = false}
    for index = 1, numMembers do
        local class = MemberClassToken(resultID, index)
        if class then roster.classes[class] = true else roster.unknown = true end
    end
    state.rosterClassCache[resultID] = roster
    return roster
end

local function PassesAdvancedFilters(resultID, info)
    local advanced = db and db.advanced or nil
    if not advanced then return true end
    local members = Readable(info.numMembers)
    -- Exclude every selected playstyle, rather than requiring a single style.
    -- A missing/secret playstyle does not equal any explicitly excluded style.
    local excludedPlaystyles = advanced.excludedPlaystyles
    if type(excludedPlaystyles) == "table" then
        local playstyle = Readable(info.generalPlaystyle)
        if type(playstyle) == "number" and excludedPlaystyles[playstyle] then
            return false
        end
    end
    if advanced.maxMembers and advanced.maxMembers > 0 then
        if type(members) ~= "number" or members > advanced.maxMembers then return false end
    end
    if advanced.hasNotes then
        local comment = Readable(info.comment)
        if type(comment) ~= "string" or comment == "" then return false end
    end
    if advanced.whisperable then
        local leader = Readable(info.leaderName)
        if type(leader) ~= "string" or leader == ""
            or Readable(info.hasSelf) ~= false or Readable(info.isDelisted) ~= false then
            return false
        end
    end
    local excluded = advanced.excludedClasses
    if type(excluded) ~= "table" then return true end
    local anyExcluded = false
    for _, value in pairs(excluded) do
        if value == true then anyExcluded = true; break end
    end
    if not anyExcluded then return true end
    if type(members) ~= "number" or members < 1 or members > 40 then return false end
    local roster = RosterClasses(resultID, math.floor(members))
    for class, excludedFlag in pairs(excluded) do
        if excludedFlag and roster.classes[class] then return false end
    end
    if roster.unknown then return false end
    return true
end

local function PassesRoleFilters(resultID, info)
    if not db then return true end
    local filters = db.filters or {}
    local needAny = filters.needTank or filters.needHealer or filters.needDps
    if not needAny and not filters.hasTank and not filters.hasHealer then
        return true
    end
    local members = Readable(info.numMembers)
    local maxMembers = GetMaxMembers(info)
    if type(members) ~= "number" or not maxMembers then
        -- Filtering must not misrepresent unavailable information as a match.
        return false
    end
    if not needAny and not filters.hasTank and not filters.hasHealer then return true end
    local counts = GetCounts(resultID)
    if not counts then return false end
    if filters.hasTank and counts.TANK < 1 then return false end
    if filters.hasHealer and counts.HEALER < 1 then return false end
    if needAny then
        if members >= maxMembers then return false end
        local targets = ROLE_TARGETS[maxMembers]
        if not targets then
            -- An unknown raid/party size has no defensible per-role vacancy.
            return false
        end
        -- Multi-selected "has space for" roles are ORed; the other filters
        -- AND with that result. A player can e.g. show Tank OR Healer vacancies.
        if not ((filters.needTank and counts.TANK < targets.TANK)
            or (filters.needHealer and counts.HEALER < targets.HEALER)
            or (filters.needDps and counts.DAMAGER < targets.DAMAGER)) then
            return false
        end
    end
    return true
end

local function UpdateAdvancedControls()
    local advanced = db and db.advanced or {}
    for token, button in pairs(advancedClassButtons) do
        button:SetChecked(type(advanced.excludedClasses) == "table"
            and advanced.excludedClasses[token] == true or false)
    end
    for field, button in pairs(advancedCheckButtons) do
        button:SetChecked(advanced[field] == true)
    end
    for playstyle, button in pairs(advancedPlaystyleButtons) do
        button:SetChecked(type(advanced.excludedPlaystyles) == "table"
            and advanced.excludedPlaystyles[playstyle] == true or false)
    end
    if advancedMaxMembersDropdown then
        for _, option in ipairs(ADVANCED_MAX_MEMBERS) do
            if option[1] == (advanced.maxMembers or 0) then
                advancedMaxMembersDropdown:OverrideText(option[2]); break
            end
        end
    end
end

local function UpdateFilterButtons()
    local filters = db and db.filters or {}
    for key, button in pairs(filterButtons) do
        button:SetChecked(filters[key] == true)
    end
    UpdateAdvancedControls()
    if sortDropdown then
        local order = db and db.sortOrder or "default"
        local captions = {default = "Sort: Finder order", asc = "Members: fewest", desc = "Members: most"}
        sortDropdown:OverrideText(captions[order] or captions.default)
    end
end

local function RebuildVisibleResults(resetPage)
    if not db then return end
    local out = {}
    for index, id in ipairs(state.cachedResults) do
        local info,verified=ResultInfo(id)
        local pinned=(not verified and type(id)=="number" and id<0)
            or state.pinnedRealIDs[id] == true
        if type(Readable(info)) == "table" then
            local count = Readable(info.numMembers)
            local removed = Readable(info.isDelisted)
            if removed == true then MatchSent(id, info) end
            local ids = Readable(info.activityIDs)
            local match = state.categoryID == nil and state.activityID == nil
            if type(ids) == "table" then
                for _, activityID in ipairs(ids) do
                    if type(Readable(activityID)) == "number" then
                        if state.activityID and activityID == state.activityID then
                            match = true; break
                        elseif state.categoryID and not state.activityID
                            and state.categoryAllIDs and state.categoryAllIDs[activityID] then
                            match = true; break
                        end
                    end
                end
            end
            if (pinned or match) and removed ~= true
                and (count == nil or (type(count) == "number" and count >= 1))
                and (pinned or (PassesRoleFilters(id, info)
                    and PassesAdvancedFilters(id, info))) then
                table.insert(out, {id=id, count=type(count)=="number" and count or nil,
                    original=index,pinned=pinned})
            end
        end
    end
    local order = db.sortOrder
    if order == "asc" or order == "desc" then
        table.sort(out, function(a,b)
            if a.pinned ~= b.pinned then return a.pinned end
            if a.count == nil and b.count == nil then return a.original < b.original end
            if a.count == nil then return false end
            if b.count == nil then return true end
            if a.count ~= b.count then
                if order == "asc" then return a.count < b.count end
                return a.count > b.count
            end
            return a.original < b.original
        end)
    else
        table.sort(out,function(a,b)
            if a.pinned ~= b.pinned then return a.pinned end
            return a.original < b.original
        end)
    end
    state.results = {}
    for _, item in ipairs(out) do table.insert(state.results, item.id) end
    if resetPage ~= false then
        state.page = 1
        if resultsViewport then resultsViewport:SetVerticalScroll(0) end
    end
    UpdatePages()
    if state.totalInCache == 0 then
        Status("No cached listings yet. Select an activity and click Search.")
    elseif #state.results == 0 then
        Status(("No groups match your filters (%d cached). Change filters or Clear."):format(state.totalInCache))
    else
        Status(("Showing %d of %d cached groups. Search updates listings; filters are local.")
            :format(#state.results, state.totalInCache))
    end
end

local function SaveAdvanced(field, value)
    if not db then return end
    db.advanced[field] = value
    UpdateAdvancedControls()
    RebuildVisibleResults(true)
end

local function SaveClassExclusion(token, checked)
    if not db then return end
    db.advanced.excludedClasses[token] = checked == true or nil
    UpdateAdvancedControls()
    RebuildVisibleResults(true)
end

local function SavePlaystyleExclusion(playstyle, checked)
    if not db then return end
    db.advanced.excludedPlaystyles[playstyle] = checked == true or nil
    UpdateAdvancedControls()
    RebuildVisibleResults(true)
end

local function SaveFilter(field, checked)
    if not db then return end
    db.filters[field] = not not checked
    RebuildVisibleResults(true)
end

local function ResetFilters()
    if not db then return end
    db.filters = {}
    db.advanced = {excludedClasses = {}, excludedPlaystyles = {}, maxMembers = 0}
    state.rosterClassCache = {}
    UpdateFilterButtons()
    RebuildVisibleResults(true)
end

local function SetSort(order)
    if not db then return end
    db.sortOrder = order
    UpdateFilterButtons()
    RebuildVisibleResults(true)
end

-- A member's zone is not guaranteed to be in the LFG listing. A right-click
-- prepares a targeted /who; the player must press Enter. This avoids protected
-- addon-driven Who requests and complies with the server's query cooldown.
local function WhoNameKey(name)
    name = Readable(name)
    if type(name) ~= "string" or name == "" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or name:find('[|"\r\n]') then return nil end
    return name:lower()
end

local function LookupMemberWho(name)
    local key = WhoNameKey(name)
    if not key then
        Print("This member's name is not available; an individual /who lookup is not possible.")
        return
    end
    if not ((ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function")
        or type(ChatFrame_OpenChat) == "function") then
        Print("The chat input is unavailable. Use Blizzard's Who tab manually.")
        return
    end
    -- This controls result routing only, not the query itself. Without it,
    -- small /who replies may appear solely in chat and not fire WHO_LIST_UPDATE.
    -- It can also open Blizzard's Who window for the result.
    if C_FriendList and type(C_FriendList.SetWhoToUi) == "function" then
        pcall(C_FriendList.SetWhoToUi, true)
    end
    local cmd = '/who n-"' .. name .. '"'
    state.pendingWho = {name=name, key=key, started=GetTime()}
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        ChatFrameUtil.OpenChat(cmd)
    else
        ChatFrame_OpenChat(cmd)
    end
    Print("Prepared " .. cmd .. ". Press Enter to look up the location; /who can be throttled.")
end

-- Only use native LFG data or a successful, manually initiated WHO response.
-- Unnamed players cannot be looked up; never guess a real identity.
local function MemberDetails(resultID, index)
    local member = { index=index }
    if C_LFGList and type(C_LFGList.GetSearchResultPlayerInfo) == "function" then
        local ok, info = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, index)
        info = ok and Readable(info) or nil
        if type(info) == "table" then
            member.name = Readable(info.name)
            member.level = Readable(info.level)
            member.className = Readable(info.className)
            member.classFilename = Readable(info.classFilename)
            member.specName = Readable(info.specName)
            member.role = Readable(info.assignedRole)
            member.area = Readable(info.areaName)
            member.isLeader = Readable(info.isLeader) == true
            member.readable = true
        end
    end
    if not member.readable and C_LFGList and type(C_LFGList.GetSearchResultMemberInfo) == "function" then
        local ok, role, classFilename, className, specName, isLeader =
            pcall(C_LFGList.GetSearchResultMemberInfo, resultID, index)
        if ok then
            member.role = Readable(role)
            member.classFilename = Readable(classFilename)
            member.className = Readable(className)
            member.specName = Readable(specName)
            member.isLeader = Readable(isLeader) == true
            member.readable = type(member.role) == "string" or type(member.classFilename) == "string"
        end
    end
    -- Preserve the actual returned name separately from the display fallback.
    member.whoName = WhoNameKey(member.name) and member.name or nil
    if type(member.name) ~= "string" or member.name == "" then member.name = "Member " .. index end
    if type(member.level) ~= "number" or member.level < 1 then member.level = nil end
    if type(member.className) ~= "string" or member.className == "" then member.className = "Class unknown" end
    if type(member.classFilename) ~= "string" then member.classFilename = nil end
    if type(member.specName) ~= "string" or member.specName == "" then member.specName = nil end
    if type(member.area) ~= "string" or member.area == "" then member.area = nil end
    if type(member.role) ~= "string" then member.role = "NONE" end
    if not member.area and member.whoName then
        local record = state.whoZones[WhoNameKey(member.whoName)]
        if record and type(record.area) == "string" and GetTime() - record.at <= WHO_ZONE_TTL then
            member.area = record.area
            member.areaFromWho = true
        end
    end
    return member
end

local function SafeMarkup(text)
    -- Player names and client-supplied group descriptions must not inject
    -- WoW texture / hyperlink markup into FontStrings.
    return tostring(text or ""):gsub("|", "||"):gsub("[\r\n]", " ")
end

local function PopulateMemberDetails(row, resultID, info)
    local n = Readable(info and info.numMembers)
    if type(n) ~= "number" or n < 1 then n = 0 end
    n = math.min(40, math.floor(n))
    local comment = Readable(info and info.comment)
    local showComment = type(comment) == "string" and comment ~= ""
    local introHeight = showComment and 53 or 34
    local lines = math.ceil(n / 2)
    local height = introHeight + math.max(1, lines) * 45 + 8
    row.detail:SetHeight(height)
    row.detailsTitle:SetText(("GROUP MEMBERS (%d)  ·  Right-click a named player to look up their area (/who)"):format(n))
    if showComment then
        row.detailsComment:SetText("Notes: " .. SafeMarkup(Truncate(comment, 114)))
        row.detailsComment:Show()
    else
        row.detailsComment:SetText("")
        row.detailsComment:Hide()
    end
    row.detailHint:SetShown(n == 0)
    if n == 0 then row.detailHint:SetText("Member information is not available for this listing.") end
    for index = 1, math.max(n, #row.memberTiles) do
        local tile = row.memberTiles[index]
        if index <= n then
            if not tile then
                tile = CreateFrame("Frame", nil, row.detail, "BackdropTemplate")
                tile:SetSize(368, 43)
                tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
                tile:SetBackdropColor(0.09, 0.11, 0.16, 1)
                tile.icon = tile:CreateTexture(nil, "ARTWORK")
                tile.icon:SetSize(19, 19)
                tile.icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 6, -4)
                tile.title = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                tile.title:SetPoint("TOPLEFT", tile, "TOPLEFT", 29, -3)
                tile.title:SetSize(332, 18)
                tile.title:SetJustifyH("LEFT")
                tile.subtitle = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                tile.subtitle:SetPoint("TOPLEFT", tile, "TOPLEFT", 29, -23)
                tile.subtitle:SetSize(332, 17)
                tile.subtitle:SetJustifyH("LEFT")
                tile:EnableMouse(true)
                tile:SetScript("OnMouseUp", function(self, button)
                    if button == "RightButton" then LookupMemberWho(self.whoName) end
                end)
                tile:SetScript("OnEnter", function(self)
                    if not GameTooltip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.whoName and "Right-click: Look up player location" or
                        "Player name is hidden; /who unavailable")
                    if self.whoName then
                        GameTooltip:AddLine("Prepares /who; press Enter to submit.", 0.8, 0.8, 0.8)
                        GameTooltip:AddLine("Locations are WHO snapshots, not live tracking.", 0.7, 0.7, 0.7)
                    end
                    GameTooltip:Show()
                end)
                tile:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                row.memberTiles[index] = tile
            end
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", row.detail, "TOPLEFT", 5 + ((index - 1) % 2) * 376,
                -(introHeight + math.floor((index - 1) / 2) * 45))
            local member = MemberDetails(resultID, index)
            if member.isLeader and member.name == ("Member " .. index) then
                local leaderName = Readable(info.leaderName)
                if type(leaderName) == "string" and leaderName ~= "" then
                    member.name = leaderName
                    member.whoName = WhoNameKey(leaderName) and leaderName or nil
                end
            end
            tile.whoName = member.whoName
            local coords = type(CLASS_ICON_TCOORDS) == "table" and member.classFilename
                and CLASS_ICON_TCOORDS[member.classFilename] or nil
            if type(coords) == "table" then
                tile.icon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
                tile.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                tile.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                tile.icon:SetTexCoord(0, 1, 0, 1)
            end
            local role = member.role == "DAMAGE" and "DAMAGER" or member.role
            local icon = ROLE_ICONS[role] or ""
            local leaderTag = member.isLeader and " |cffffd100(Leader)|r" or ""
            tile.title:SetText(icon .. " " .. SafeMarkup(Truncate(member.name, 22)) .. leaderTag)
            local level = member.level and ("Lv" .. member.level) or "Lv?"
            local spec = member.specName
            local area = member.area or "Area unknown"
            if member.areaFromWho then area = area .. " (via /who)" end
            -- Some Forever listings use className as a placeholder for specName.
            -- Do not show "Shaman · Shaman" or "Hunter · Hunter".
            if spec and spec:lower():match("^%s*(.-)%s*$")
                == member.className:lower():match("^%s*(.-)%s*$") then
                spec = nil
            end
            local desc = level .. " " .. member.className
            if spec then desc = desc .. " · " .. spec end
            desc = desc .. " · " .. area
            tile.subtitle:SetText(SafeMarkup(Truncate(desc, 55)))
            local classColor = type(RAID_CLASS_COLORS) == "table" and member.classFilename
                and RAID_CLASS_COLORS[member.classFilename] or nil
            if type(classColor) == "table" then
                tile.title:SetTextColor(classColor.r or 1, classColor.g or 1, classColor.b or 1)
            else
                tile.title:SetTextColor(1, 1, 1)
            end
            tile:Show()
        elseif tile then
            tile:Hide()
        end
    end
    row.detail:Show()
    return height
end

UpdatePages = function()
    if not window then return end
    local total = #state.results
    local pages = math.max(1, math.ceil(total / PAGE_SIZE))
    state.page = math.max(1, math.min(state.page, pages))
    pageLabel:SetText(("Page %d / %d  (%d groups)"):format(state.page, pages, total))
    prevButton:SetEnabled(state.page > 1)
    nextButton:SetEnabled(state.page < pages)

    local offset = 0
    for i = 1, PAGE_SIZE do
        local row = rows[i]
        local resultID = state.results[(state.page - 1) * PAGE_SIZE + i]
        row.resultID = resultID
        row.topOffset = offset
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", resultsCanvas, "TOPLEFT", 0, -offset)
        row:SetHeight(34)
        row.detail:Hide()
        row.expandLabel:SetText("+")
        if not resultID then
            row:Hide()
        else
            row:Show()
            local info,verified = ResultInfo(resultID)
            if type(info) ~= "table" then
                row.label:SetText("Expired listing")
                row.activity:SetText("")
                row.playstyle:SetText("")
                row.sentBadge:SetText("")
                row.composition:SetText("")
                row.whisper:Disable()
                row.expand:Disable()
            else
                local name = Readable(info.leaderName)
                local members = Readable(info.numMembers)
                local removed = Readable(info.isDelisted)
                local own = Readable(info.hasSelf)
                local activity = ResultActivityName(info)
                local displayName = type(name) == "string" and name ~= "" and name or "Leader hidden"
                row.label:SetText(Truncate(displayName, 21))
                row.activity:SetText(Truncate(activity, 33))
                local sent = (not verified and state.sentVirtualIDs[resultID] ~= nil)
                    or MatchSent(resultID, info) ~= nil
                row.playstyle:SetText("Playstyle: " .. Truncate(ResultPlaystyle(info), 23))
                -- A narrow green status between composition and Whisper. Cached
                -- results retain the marker but cannot be whispered until verified.
                row.sentBadge:SetText(sent and (not verified and "|cff45df87Sent*|r"
                    or "|cff45df87Sent|r") or "")
                row.composition:SetText(GroupComposition(resultID, info))
                row.whisper:SetEnabled(verified and type(name) == "string" and name ~= ""
                    and type(members) == "number" and members >= 1 and not removed and own == false)
                row.expand:SetEnabled(verified and removed ~= true)
                if verified and state.expandedResultID == resultID and removed ~= true then
                    row.expandLabel:SetText("-")
                    row:SetHeight(34 + PopulateMemberDetails(row, resultID, info))
                end
            end
            offset = offset + row:GetHeight() + 1
        end
    end
    resultsCanvas:SetHeight(math.max(315, offset))
    if ForeverQuickJoinTheme and ForeverQuickJoinTheme.ApplyNew then
        ForeverQuickJoinTheme.ApplyNew()
    end
    -- Keep scroll position in range when collapsing an entry or changing pages.
    local maxScroll = math.max(0, resultsCanvas:GetHeight() - resultsViewport:GetHeight())
    resultsViewport:SetVerticalScroll(math.min(resultsViewport:GetVerticalScroll(), maxScroll))
end

-- A Who result must uniquely identify the selected player; never assign an
-- area just because a query matched a similar name or an unrelated result.
local function MergeWhoLocation()
    local request = state.pendingWho
    if not request then return end
    if GetTime() - request.started > 90 then
        state.pendingWho = nil
        return
    end
    if not C_FriendList or type(C_FriendList.GetNumWhoResults) ~= "function"
        or type(C_FriendList.GetWhoInfo) ~= "function" then return end
    local countOK, count = pcall(C_FriendList.GetNumWhoResults)
    if not countOK or type(Readable(count)) ~= "number" then return end
    local exact, partial, exactCount, partialCount = nil, nil, 0, 0
    local expectedBase = request.key:match("^([^%-]+)") or request.key
    for i = 1, math.min(50, count) do
        local ok, who = pcall(C_FriendList.GetWhoInfo, i)
        who = ok and Readable(who) or nil
        if type(who) == "table" then
            local name = WhoNameKey(who.fullName)
            local area = Readable(who.area)
            if name and type(area) == "string" and area ~= "" then
                if name == request.key then
                    exact, exactCount = area, exactCount + 1
                elseif (name:match("^([^%-]+)") or name) == expectedBase
                    and (not request.key:find("-", 1, true) or not name:find("-", 1, true)) then
                    partial, partialCount = area, partialCount + 1
                end
            end
        end
    end
    local zone = exactCount == 1 and exact or (exactCount == 0 and partialCount == 1 and partial or nil)
    if not zone then return end
    state.whoZones[request.key] = {area=zone, at=GetTime()}
    state.pendingWho = nil
    Print(("/who: %s last seen in %s. This is a snapshot, not continuous tracking."):format(request.name, zone))
    if window and window:IsShown() and state.expandedResultID then UpdatePages() end
end

local function RefreshResults()
    if not C_LFGList or not C_LFGList.GetFilteredSearchResults then return end
    local ok, total, ids = pcall(C_LFGList.GetFilteredSearchResults)
    if ok and ids == nil and total == 0 then ids = {} end
    if not ok or type(Readable(ids)) ~= "table" then
        Status("Couldn't read the search results.")
        return
    end
    state.cachedResults = {}
    state.rosterClassCache = {}
    state.pinnedRealIDs = {}
    local found={}
    for _, id in ipairs(ids) do
        if type(Readable(id)) == "number" then
            table.insert(state.cachedResults, id)
            local info,verified=ResultInfo(id)
            if verified then
                local rec=MatchSent(id,info)
                if rec then
                    found[rec]=true
                    state.pinnedRealIDs[id]=true
                    -- The new live result is preferable to its older snapshot.
                    rec.snapshot=SnapshotSentInfo(info,id)
                end
            end
        end
    end
    -- Search results are scoped and often capped; a missing record is NOT proof
    -- of disbanding. Keep a cached Sent row until the client confirms delisting
    -- or reports a new listing with a different creation time.
    for _,rec in pairs(state.sentByListing) do
        if not found[rec] and rec.snapshot then
            local info,verified=ResultInfo(rec.id)
            if verified then
                if info.isDelisted==true then
                    RemoveSent(rec)
                elseif SentIdentity(rec.id,info)==rec.key then
                    found[rec]=true
                    state.pinnedRealIDs[rec.id]=true
                    state.cachedResults[#state.cachedResults+1]=rec.id
                    rec.snapshot=SnapshotSentInfo(info,rec.id)
                else
                    state.cachedResults[#state.cachedResults+1]=rec.virtualID
                end
            else
                state.cachedResults[#state.cachedResults+1]=rec.virtualID
            end
        end
    end
    state.totalInCache = #state.cachedResults
    RebuildVisibleResults(true)
end

local function GetActivities(categoryID)
    if not C_LFGList or not C_LFGList.GetAvailableActivities or not categoryID then return {} end
    local ok, ids = pcall(C_LFGList.GetAvailableActivities, categoryID)
    if not ok or type(ids) ~= "table" then return {} end
    local arr = {}
    for _, id in ipairs(ids) do
        local info = C_LFGList.GetActivityInfoTable(id)
        if info then
            local level = UnitLevel("player")
            local low, high = info.minLevelSuggestion or 0, info.maxLevelSuggestion or 0
            -- Only show suggested-level activities initially, like Blizzard.
            -- An option below allows users to see every available activity.
            if (db and db.allLevels) or ((low == 0 or level >= low) and (high == 0 or level <= high)) then
                table.insert(arr, { id = id, name = ActivityDisplayName(id) or ("Activity " .. id) })
            end
        end
    end
    table.sort(arr, function(a, b) return a.name:lower() < b.name:lower() end)
    return arr
end

-- Readable, level-filtered activities are the single source of truth for
-- both Search scope and which cached groups the selected category displays.
local function SetAllowedActivities(activities)
    state.searchActivityIDs = {}
    state.categoryAllIDs = {}
    for _, activity in ipairs(activities or {}) do
        if type(activity.id) == "number" then
            table.insert(state.searchActivityIDs, activity.id)
            state.categoryAllIDs[activity.id] = true
        end
    end
end

local function UpdateSearchButton()
    if not searchButton then return end
    searchButton:SetEnabled(state.categoryID ~= nil
        and not state.searching and not state.searchBlocked
        and #state.searchActivityIDs > 0)
end

local function SetCategory(id, name)
    state.categoryID, state.categoryName = id, name
    state.activityID, state.activityName = nil, nil
    state.activities = GetActivities(id)
    SetAllowedActivities(state.activities)
    if categoryDropdown then categoryDropdown:OverrideText(name or "All categories") end
    if activityDropdown then
        activityDropdown:OverrideText("All activities")
        activityDropdown:SetEnabled(id ~= nil)
    end
    UpdateSearchButton()
    if window then RefreshResults() end
end

local function RefreshCategories()
    if not C_LFGList or type(C_LFGList.GetAvailableCategories) ~= "function" then
        Status("Group Finder API unavailable.")
        return
    end
    local ok, ids = pcall(C_LFGList.GetAvailableCategories)
    if not ok or type(ids) ~= "table" then return end
    local categories = {}
    for _, id in ipairs(ids) do
        local info = C_LFGList.GetLfgCategoryInfo(id)
        if info and info.name and #GetActivities(id) > 0 then
            table.insert(categories, { id = id, name = info.name })
        end
    end
    state.categories = categories
    if #categories == 0 then
        SetCategory(nil, nil)
        return
    end
    for _, cat in ipairs(categories) do
        if cat.id == (state.categoryID or 0) then
            -- Updating availability must NOT erase an already completed search.
            -- Refreshing the current category only changes menu choices.
            state.categoryName = cat.name
            state.activities = cat.id == 0 and {} or GetActivities(cat.id)
            SetAllowedActivities(state.activities)
            if categoryDropdown then categoryDropdown:OverrideText(cat.name) end
            local chosenID = state.activityID
            state.activityID, state.activityName = nil, nil
            if chosenID then
                for _, act in ipairs(state.activities) do
                    if act.id == chosenID then
                        state.activityID, state.activityName = act.id, act.name
                        break
                    end
                end
            end
            if activityDropdown then
                activityDropdown:OverrideText(state.activityName or "All activities")
                activityDropdown:SetEnabled(cat.id ~= 0)
            end
            UpdateSearchButton()
            return
        end
    end
    SetCategory(categories[1].id, categories[1].name)
end

-- Only changes local activity and cached-result filtering. An explicit
-- Search button click is always required for a new server request.
local function SetAllLevelRanges(enabled)
    if not db then return end
    db.allLevels = enabled == true
    if allLevelsButton then allLevelsButton:SetChecked(db.allLevels) end
    RefreshCategories()
    RebuildVisibleResults(true)
    UpdatePreview()
end

-- This is invoked by the physical Search button ONLY. A timer or /qj command
-- may update UI but NEVER call the restricted search method. Keep the call as
-- early as possible in this handler, before updating/changing UI controls.
local function SearchFromClick()
    if state.searching or state.searchBlocked or not state.categoryID then return end
    local activities = state.activityID and {state.activityID} or state.searchActivityIDs
    if #activities == 0 then
        Status("Activity list not ready. Use /qj activities, then click Search.")
        return
    end
    if not C_LFGList or type(C_LFGList.Search) ~= "function" then
        Status("Search API unavailable on this client.")
        return
    end
    -- Do NOT put this inside pcall/securecall, an async callback, or a hook.
    -- This matches the exact call shape used by LFG Forever's Search button.
    state.searchAttemptActive = true
    state.searchAttemptAt = GetTime()
    local response = C_LFGList.Search(state.categoryID, 0, 0, nil, false, nil, activities)
    state.searchAttemptActive = false
    if state.searchBlocked then return end
    if response == false then
        Status("WoW refused the search. Previously cached listings remain available.")
        return
    end
    state.searching = true
    UpdateSearchButton()
    Status("Searching selected activity... Existing listings remain visible until results arrive.")
    if state.timeout and state.timeout.Cancel then state.timeout:Cancel() end
    if C_Timer and C_Timer.NewTimer then
        state.timeout = C_Timer.NewTimer(15, function()
            if not state.searching then return end
            state.searching = false
            state.timeout = nil
            UpdateSearchButton()
            Status("Search timed out; click Search to retry. Older cached results remain visible.")
        end)
    end
end

local function FinishSearch(failed, reason)
    state.searching = false
    if state.timeout and state.timeout.Cancel then state.timeout:Cancel() end
    state.timeout = nil
    UpdateSearchButton()
    if failed then
        reason = Readable(reason)
        Status(type(reason) == "string" and reason ~= "" and ("Search failed: " .. Truncate(reason, 105))
            or "Search failed. You can retry; previously cached listings remain available.")
    else
        RefreshResults()
    end
end

local function MakeLabel(parent, text, font, x, y, width, height)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetSize(width, height)
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    return label
end

local SyncDefaultForParty
local function CreateWindow()
    if window then return window end
    window = CreateFrame("Frame", "ForeverQuickJoinWindow", UIParent, "BackdropTemplate")
    window:SetSize(840, 785)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    window:SetBackdropColor(0.035, 0.045, 0.065, 1)
    -- DialogBox background has transparent pixels even at alpha 1. The solid
    -- white texture, tinted dark and fully opaque, closes every pixel.
    window:SetAlpha(1)
    MakeLabel(window, "Forever QuickJoin", "GameFontNormalLarge", 24, -17, 400, 26)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -6)
    close:SetScript("OnClick", function() window:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "ForeverQuickJoinWindow") end

    categoryDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
    categoryDropdown:SetWidth(185)
    categoryDropdown:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -53)
    categoryDropdown:SetDefaultText("Category")
    categoryDropdown:SetupMenu(function(_, root)
        root:SetTag("MENU_FOREVER_QUICKJOIN_CATEGORY")
        for _, cat in ipairs(state.categories) do
            local catID, catName = cat.id, cat.name
            root:CreateRadio(catName,
                function(id) return (state.categoryID or 0) == id end,
                function(id)
                    SetCategory(id == 0 and nil or id, catName)
                    UpdatePreview()
                end, catID)
        end
    end)

    activityDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
    activityDropdown:SetWidth(330)
    activityDropdown:SetPoint("LEFT", categoryDropdown, "RIGHT", 10, 0)
    activityDropdown:SetDefaultText("All activities")
    activityDropdown:SetupMenu(function(_, root)
        root:SetTag("MENU_FOREVER_QUICKJOIN_ACTIVITY")
        root:CreateRadio("All activities",
            function() return state.activityID == nil end,
            function()
                state.activityID, state.activityName = nil, nil
                activityDropdown:OverrideText("All activities")
                RefreshResults()
                UpdatePreview()
            end)
        for _, item in ipairs(state.activities) do
            local activityID, activityName = item.id, item.name
            root:CreateRadio(activityName,
                function(id) return state.activityID == id end,
                function(id)
                    state.activityID, state.activityName = id, activityName
                    activityDropdown:OverrideText(activityName)
                    RefreshResults()
                    UpdatePreview()
                end, activityID)
        end
    end)

    searchButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    searchButton:SetSize(106, 26)
    searchButton:SetPoint("LEFT", activityDropdown, "RIGHT", 10, 0)
    searchButton:SetText("Search")
    searchButton:SetScript("OnClick", SearchFromClick)
    -- Level range is part of basic activity discovery, not an advanced
    -- result filter. Reuse the same saved setting and /qj all shortcut.
    allLevelsButton = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
    allLevelsButton:SetSize(22, 22)
    allLevelsButton:SetPoint("TOPLEFT", window, "TOPLEFT", 25, -91)
    allLevelsButton:SetChecked(db and db.allLevels == true or false)
    MakeLabel(allLevelsButton, "Show all level ranges", "GameFontHighlightSmall", 26, -2, 213, 22)
    allLevelsButton:SetScript("OnClick", function(self)
        SetAllLevelRanges(self:GetChecked())
    end)
    MakeLabel(window, "Search retrieves groups on click. Filters and sorting are in Advanced Filters.",
        "GameFontHighlightSmall", 275, -95, 350, 21)
    advancedButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    advancedButton:SetSize(168, 26)
    advancedButton:SetPoint("TOPLEFT", window, "TOPLEFT", 641, -89)
    advancedButton:SetText("Advanced Filters >>")

    advancedPanel = CreateFrame("Frame", "ForeverQuickJoinAdvancedFilters", window, "BackdropTemplate")
    advancedPanel:SetSize(365, 633)
    advancedPanel:SetFrameStrata("DIALOG")
    advancedPanel:SetFrameLevel(window:GetFrameLevel() + 15)
    advancedPanel:SetClampedToScreen(true)
    advancedPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 20,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    advancedPanel:SetBackdropColor(0.035, 0.045, 0.065, 1)
    advancedPanel:EnableMouse(true)
    local function PositionAdvancedPanel()
        advancedPanel:ClearAllPoints()
        local right = window:GetRight()
        local left = window:GetLeft()
        local screenRight = UIParent and UIParent:GetRight()
        if right and screenRight and screenRight - right >= 380 then
            advancedPanel:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, -75)
        elseif left and left >= 380 then
            advancedPanel:SetPoint("TOPRIGHT", window, "TOPLEFT", -6, -75)
        else
            -- Small screens: put the drawer inside QuickJoin, above results.
            advancedPanel:SetPoint("TOPRIGHT", window, "TOPRIGHT", -11, -102)
        end
    end
    local function ToggleAdvanced(show)
        if show then
            PositionAdvancedPanel()
            advancedPanel:Show()
            advancedButton:SetText("Advanced Filters <<")
        else
            advancedPanel:Hide()
            advancedButton:SetText("Advanced Filters >>")
        end
    end
    advancedButton:SetScript("OnClick", function() ToggleAdvanced(not advancedPanel:IsShown()) end)
    window.QuickJoinHideAdvanced = function() ToggleAdvanced(false) end
    window.QuickJoinRestoreAdvanced = function()
        if db and db.advancedOpen then ToggleAdvanced(true) end
    end
    advancedPanel:SetScript("OnShow", function()
        if db then db.advancedOpen = true end
    end)
    advancedPanel:SetScript("OnHide", function()
        if db then db.advancedOpen = false end
    end)
    MakeLabel(advancedPanel, "ADVANCED FILTERS", "GameFontNormal", 14, -13, 310, 20)
    local advancedClose = CreateFrame("Button", nil, advancedPanel, "UIPanelCloseButton")
    advancedClose:SetPoint("TOPRIGHT", advancedPanel, "TOPRIGHT", -1, -2)
    advancedClose:SetScript("OnClick", function() ToggleAdvanced(false) end)
    -- Advanced-only controls: sorting, role vacancies, class exclusions,
    -- playstyles, and content filters. The level-range checkbox lives below
    -- the category/activity menus on the main window.

    MakeLabel(advancedPanel, "Sort by:", "GameFontNormalSmall", 16, -47, 99, 22)
    sortDropdown = CreateFrame("DropdownButton", nil, advancedPanel, "WowStyle1DropdownTemplate")
    sortDropdown:SetWidth(214)
    sortDropdown:SetPoint("TOPLEFT", advancedPanel, "TOPLEFT", 128, -42)
    sortDropdown:SetDefaultText("Finder order")
    sortDropdown:SetupMenu(function(_, root)
        root:SetTag("MENU_FOREVER_QUICKJOIN_SORT")
        for _, item in ipairs({
            {"default", "Finder order"}, {"asc", "Members: fewest"},
            {"desc", "Members: most"},
        }) do
            local order, label = item[1], item[2]
            root:CreateRadio(label,
                function(key) return db and db.sortOrder == key end,
                function(key) SetSort(key) end, order)
        end
    end)
    local function MakeCheck(field, x, y, label, width)
        local button = CreateFrame("CheckButton", nil, advancedPanel, "UICheckButtonTemplate")
        button:SetSize(22,22)
        button:SetPoint("TOPLEFT", advancedPanel, "TOPLEFT", x,y)
        MakeLabel(button, label, "GameFontHighlightSmall", 26, -2, width or 92, 22)
        button:SetChecked(db and db.filters and db.filters[field] == true or false)
        button:SetScript("OnClick", function(self) SaveFilter(field, self:GetChecked()) end)
        filterButtons[field] = button
    end
    MakeLabel(advancedPanel, "Space for:", "GameFontNormalSmall", 16, -82, 200, 20)
    MakeCheck("needTank", 15, -104, "Tank", 68)
    MakeCheck("needHealer", 128, -104, "Healer", 78)
    MakeCheck("needDps", 249, -104, "DPS", 72)
    MakeLabel(advancedPanel, "Already has:", "GameFontNormalSmall", 16, -139, 200, 20)
    MakeCheck("hasTank", 15, -161, "Tank", 68)
    MakeCheck("hasHealer", 128, -161, "Healer", 78)
    MakeLabel(advancedPanel, "Exclude groups containing these classes:",
        "GameFontNormalSmall", 15, -199, 336, 19)
    local visibleIndex = 0
    for _, option in ipairs(CLASS_OPTIONS) do
        local token, english = option[1], option[2]
        -- The UI must show only Forever's nine classes. Retail class icon
        -- tables can contain Death Knight, Monk, Demon Hunter and Evoker.
        local label = type(LOCALIZED_CLASS_NAMES_MALE) == "table"
            and LOCALIZED_CLASS_NAMES_MALE[token] or english
        if type(label) ~= "string" or label == "" then label = english end
        do
            local col = visibleIndex % 2
            local rowNum = math.floor(visibleIndex / 2)
            local button = CreateFrame("CheckButton", nil, advancedPanel, "UICheckButtonTemplate")
            button:SetSize(22, 22)
            button:SetPoint("TOPLEFT", advancedPanel, "TOPLEFT",
                15 + col * 169, -221 - rowNum * 27)
            MakeLabel(button, label, "GameFontHighlightSmall", 24, -2, 138, 21)
            button:SetScript("OnClick", function(self)
                SaveClassExclusion(token, self:GetChecked())
            end)
            advancedClassButtons[token] = button
            visibleIndex = visibleIndex + 1
        end
    end
    MakeLabel(advancedPanel,
        "Class exclusions require a readable roster; unknown rosters are hidden.",
        "GameFontHighlightSmall", 16, -354, 339, 34)
    MakeLabel(advancedPanel, "Exclude these playstyles:",
        "GameFontNormalSmall", 16, -389, 332, 19)
    for i, option in ipairs(ADVANCED_PLAYSTYLES) do
        local id, label = option[1], option[2]
        local col = (i - 1) % 2
        local rowNum = math.floor((i - 1) / 2)
        local button = CreateFrame("CheckButton", nil, advancedPanel, "UICheckButtonTemplate")
        button:SetSize(22, 22)
        button:SetPoint("TOPLEFT", advancedPanel, "TOPLEFT",
            15 + col * 169, -415 - rowNum * 29)
        MakeLabel(button, label, "GameFontHighlightSmall", 24, -2, 137, 21)
        button:SetScript("OnClick", function(self)
            SavePlaystyleExclusion(id, self:GetChecked())
        end)
        advancedPlaystyleButtons[id] = button
    end
    MakeLabel(advancedPanel, "Max members:", "GameFontNormalSmall", 16, -486, 108, 21)
    advancedMaxMembersDropdown = CreateFrame("DropdownButton", nil,
        advancedPanel, "WowStyle1DropdownTemplate")
    advancedMaxMembersDropdown:SetWidth(215)
    advancedMaxMembersDropdown:SetPoint("TOPLEFT", advancedPanel, "TOPLEFT", 128, -481)
    advancedMaxMembersDropdown:SetupMenu(function(_, root)
        root:SetTag("MENU_FOREVER_QUICKJOIN_ADVANCED_SIZE")
        for _, option in ipairs(ADVANCED_MAX_MEMBERS) do
            local value, label = option[1], option[2]
            root:CreateRadio(label,
                function(key) return db and db.advanced.maxMembers == key end,
                function(key) SaveAdvanced("maxMembers", key) end, value)
        end
    end)
    local function AdvancedCheck(field, label, y)
        local button = CreateFrame("CheckButton", nil, advancedPanel, "UICheckButtonTemplate")
        button:SetSize(22, 22)
        button:SetPoint("TOPLEFT", advancedPanel, "TOPLEFT", 14, y)
        MakeLabel(button, label, "GameFontHighlightSmall", 26, -2, 315, 22)
        button:SetScript("OnClick", function(self) SaveAdvanced(field, self:GetChecked()) end)
        advancedCheckButtons[field] = button
    end
    AdvancedCheck("whisperable", "Only groups I can whisper", -525)
    AdvancedCheck("hasNotes", "Only groups with descriptions", -555)
    local clearAdvanced = CreateFrame("Button", nil, advancedPanel, "UIPanelButtonTemplate")
    clearAdvanced:SetSize(135, 23)
    clearAdvanced:SetPoint("TOPRIGHT", advancedPanel, "TOPRIGHT", -15, -596)
    clearAdvanced:SetText("Clear All Filters")
    clearAdvanced:SetScript("OnClick", ResetFilters)
    advancedPanel:Hide()
    UpdateFilterButtons()
    if db and db.advancedOpen then ToggleAdvanced(true) end

    MakeLabel(window, "GROUP LISTINGS", "GameFontNormal", 26, -198, 570, 20)
    MakeLabel(window, "LEADER", "GameFontNormalSmall", 36, -214, 160, 16)
    MakeLabel(window, "ACTIVITY / PLAYSTYLE", "GameFontNormalSmall", 211, -214, 222, 16)
    MakeLabel(window, "GROUP ROLES", "GameFontNormalSmall", 442, -214, 210, 16)
    MakeLabel(window, "Click a row to view members", "GameFontHighlightSmall", 648, -198, 160, 17)

    -- The list scrolls vertically when an expanded group contains many members.
    -- A fixed viewport prevents the detail panel from overlapping the whisper UI.
    resultsViewport = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    resultsViewport:SetPoint("TOPLEFT", window, "TOPLEFT", 24, -234)
    resultsViewport:SetSize(764, 315)
    resultsCanvas = CreateFrame("Frame", nil, resultsViewport)
    resultsCanvas:SetSize(764, 315)
    resultsViewport:SetScrollChild(resultsCanvas)
    resultsViewport:EnableMouseWheel(true)
    resultsViewport:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, resultsCanvas:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 45)))
    end)

    for i = 1, PAGE_SIZE do
        local row = CreateFrame("Frame", nil, resultsCanvas, "BackdropTemplate")
        row:SetSize(759, 34)
        row:SetPoint("TOPLEFT", resultsCanvas, "TOPLEFT", 0, -(i - 1) * 35)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row:SetBackdropColor(0.10, 0.12, 0.16, 1)
        row.expand = CreateFrame("Button", nil, row)
        row.expand:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.expand:SetSize(634, 34)
        row.expandLabel = MakeLabel(row, "+", "GameFontNormal", 9, -9, 16, 18)
        row.expand:SetScript("OnClick", function()
            if not row.resultID then return end
            if state.expandedResultID == row.resultID then
                state.expandedResultID = nil
                UpdatePages()
            else
                state.expandedResultID = row.resultID
                UpdatePages()
                local maxScroll = math.max(0, resultsCanvas:GetHeight() - resultsViewport:GetHeight())
                resultsViewport:SetVerticalScroll(math.min(row.topOffset or 0, maxScroll))
            end
        end)
        row.expand:SetScript("OnEnter", function()
            if ForeverQuickJoinTheme and ForeverQuickJoinTheme.RowHover then
                ForeverQuickJoinTheme.RowHover(row, true)
            else row:SetBackdropColor(0.17, 0.20, 0.27, 1) end
        end)
        row.expand:SetScript("OnLeave", function()
            if ForeverQuickJoinTheme and ForeverQuickJoinTheme.RowHover then
                ForeverQuickJoinTheme.RowHover(row, false)
            else row:SetBackdropColor(0.10, 0.12, 0.16, 1) end
        end)
        row.label = MakeLabel(row, "", "GameFontHighlightSmall", 26, -1, 153, 16)
        -- Keep Sent immediately left of the Whisper button, NOT below the leader.
        row.sentBadge = MakeLabel(row, "", "GameFontNormalSmall", 599, -8, 40, 22)
        row.activity = MakeLabel(row, "", "GameFontHighlightSmall", 187, -2, 225, 16)
        row.playstyle = MakeLabel(row, "", "GameFontHighlightSmall", 187, -18, 225, 14)
        row.playstyle:SetTextColor(0.72, 0.88, 0.72)
        row.playstyle:SetWordWrap(false)
        row.composition = MakeLabel(row, "", "GameFontHighlightSmall", 416, -8, 181, 22)
        row.detail = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -34)
        row.detail:SetSize(759, 90)
        row.detail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row.detail:SetBackdropColor(0.055, 0.07, 0.10, 1)
        row.detailsTitle = MakeLabel(row.detail, "", "GameFontNormalSmall", 8, -7, 730, 18)
        row.detailsComment = MakeLabel(row.detail, "", "GameFontHighlightSmall", 8, -27, 735, 19)
        row.detailsComment:SetTextColor(.82, .82, .84)
        row.detailHint = MakeLabel(row.detail, "", "GameFontHighlightSmall", 8, -40, 730, 18)
        row.memberTiles = {}
        row.detail:Hide()
        row.whisper = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.whisper:SetSize(117, 24)
        row.whisper:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -5)
        row.whisper:SetText("Whisper to Join")
        row.whisper:SetScript("OnClick", function()
            if row.resultID then SendWhisper(row.resultID) end
        end)
        row:Hide()
        rows[i] = row
    end

    prevButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    prevButton:SetSize(90, 24)
    prevButton:SetPoint("TOPLEFT", window, "TOPLEFT", 25, -562)
    prevButton:SetText("Previous")
    prevButton:SetScript("OnClick", function()
        state.page = state.page - 1
        if resultsViewport then resultsViewport:SetVerticalScroll(0) end
        UpdatePages()
    end)
    nextButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    nextButton:SetSize(90, 24)
    nextButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -25, -562)
    nextButton:SetText("Next")
    nextButton:SetScript("OnClick", function()
        state.page = state.page + 1
        if resultsViewport then resultsViewport:SetVerticalScroll(0) end
        UpdatePages()
    end)
    pageLabel = MakeLabel(window, "Page 1 / 1", "GameFontHighlightSmall", 277, -567, 300, 20)
    pageLabel:SetJustifyH("CENTER")

    MakeLabel(window, "Whisper: {level} {class} {role} {activity} {location} {party} {partycount}",
        "GameFontNormalSmall", 26, -602, 600, 18)
    templateResetButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    templateResetButton:SetSize(178, 23)
    templateResetButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -26, -598)
    templateResetButton:SetText("Reload Whisper Template")
    templateResetButton:SetScript("OnClick", function()
        if not db then return end
        db.templateIsDefault = true
        db.template = DefaultTemplate()
        if messageBox then
            -- SetText may fire OnTextChanged, so guard it from turning the
            -- programmatic reset into a 'custom template' edit.
            state.settingTemplate = true
            messageBox:SetText(db.template)
            state.settingTemplate = false
        end
        UpdatePreview()
        Status(GroupSize() > 0 and "Loaded group-aware default template." or "Loaded solo default template.")
    end)
    messageBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    messageBox:SetSize(758,23)
    messageBox:SetPoint("TOPLEFT", window, "TOPLEFT", 36, -626)
    messageBox:SetAutoFocus(false)
    messageBox:SetMaxLetters(240)
    messageBox:SetText(CurrentTemplate())
    messageBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    messageBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    messageBox:SetScript("OnTextChanged", function(self)
        if db then
            db.template = self:GetText()
            if not state.settingTemplate then db.templateIsDefault = false end
        end
        UpdatePreview()
    end)
    previewTitleLabel = MakeLabel(window, "Preview:", "GameFontNormalSmall", 26, -657, 70, 56)
    previewTitleLabel:SetJustifyV("TOP")
    previewLabel = MakeLabel(window, "", "GameFontHighlightSmall", 100, -657, 700, 56)
    previewLabel:SetJustifyV("TOP")
    locationLabel = MakeLabel(window, "", "GameFontNormalSmall", 26, -717, 785, 20)
    statusLabel = MakeLabel(window, "Waiting for activities...", "GameFontHighlightSmall", 26, -741, 785, 20)

    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", function(_, delta)
        local pages = math.max(1, math.ceil(#state.results / PAGE_SIZE))
        state.page = math.max(1, math.min(pages, state.page - delta))
        if resultsViewport then resultsViewport:SetVerticalScroll(0) end
        UpdatePages()
    end)
    window:SetScript("OnShow", function()
        SyncDefaultForParty()
        RefreshCategories()
        RefreshResults()
    end)
    if ForeverQuickJoinHost and ForeverQuickJoinHost.Attach then
        ForeverQuickJoinHost.Attach(window)
    end
    window.QuickJoinUpdatePreview = UpdatePreview
    window.QuickJoinStatus = Status
    if ForeverQuickJoinParty and ForeverQuickJoinParty.Attach then
        ForeverQuickJoinParty.Attach(window)
    end
    -- Theme module is intentionally loaded last and can restyle all existing
    -- host/party frames without reload or recreating protected UI controls.
    if ForeverQuickJoinTheme and ForeverQuickJoinTheme.Attach then
        ForeverQuickJoinTheme.Attach(window, advancedPanel, rows)
    end
    window:Hide()
    UpdatePages()
    return window
end

-- Only system-managed defaults adapt automatically when party composition
-- changes. User-written messages are never overwritten by roster events.
SyncDefaultForParty = function()
    if db and db.templateIsDefault then
        local template = DefaultTemplate()
        if db.template ~= template then
            db.template = template
            if messageBox then
                state.settingTemplate = true
                messageBox:SetText(template)
                state.settingTemplate = false
            end
        end
    end
    if ForeverQuickJoinParty and ForeverQuickJoinParty.Refresh then
        ForeverQuickJoinParty.Refresh(false)
    end
    if window and window:IsShown() then UpdatePreview() end
end

local function RequestActivities()
    -- Only request activity metadata. Never load or open the Blizzard panel
    -- from addon code; that could taint its native interaction handlers.
    if C_LFGList and C_LFGList.RequestAvailableActivities then
        pcall(C_LFGList.RequestAvailableActivities)
    end
end

local ToggleWindow

local function UpdateMinimapPosition()
    if not minimapButton or not Minimap then return end
    local angle = db and db.minimapAngle or 225
    local radius = 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(math.rad(angle)) * radius, math.sin(math.rad(angle)) * radius)
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    minimapButton = CreateFrame("Button", "ForeverQuickJoinMinimapButton", Minimap)
    minimapButton:SetSize(32,32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20,20)
    icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(52,52)
    border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapButton:SetScript("OnClick", function() ToggleWindow() end)
    minimapButton:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forever QuickJoin", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            if not Minimap or not db or not GetCursorPosition then return end
            local x, y = GetCursorPosition()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            if not x or not y or not mx or not my or not scale or scale == 0 then return end
            x, y = x / scale - mx, y / scale - my
            local angle = math.atan2 or atan2
            if not angle then return end
            db.minimapAngle = math.deg(angle(y,x))
            UpdateMinimapPosition()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        UpdateMinimapPosition()
    end)
    UpdateMinimapPosition()
end

ToggleWindow = function()
    if not db then
        ForeverQuickJoinDB = ForeverQuickJoinDB or {}
        db = ForeverQuickJoinDB
    end
    local win = CreateWindow()
    if win:IsShown() then
        win:Hide()
    else
        RequestActivities()
        win:Show()
        RefreshCategories()
    end
end

SLASH_FOREVERQUICKJOIN1 = "/qj"
SLASH_FOREVERQUICKJOIN2 = "/quickjoin"
SLASH_FOREVERQUICKJOIN3 = "/fqj"
SlashCmdList.FOREVERQUICKJOIN = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        if not db then ForeverQuickJoinDB = ForeverQuickJoinDB or {}; db = ForeverQuickJoinDB end
        db.templateIsDefault = true
        SyncDefaultForParty()
        Print("Whisper template reloaded for " .. (GroupSize() > 0 and "your current party." or "solo play."))
    elseif msg == "list" then
        if not window then ToggleWindow() elseif not window:IsShown() then window:Show() end
        if ForeverQuickJoinHost then ForeverQuickJoinHost.OpenList() end
    elseif msg == "find" then
        if not window then ToggleWindow() elseif not window:IsShown() then window:Show() end
        if ForeverQuickJoinHost then ForeverQuickJoinHost.OpenFind() end
    elseif msg == "roles" or msg == "party" then
        if not window then ToggleWindow() elseif not window:IsShown() then window:Show() end
        if ForeverQuickJoinParty then ForeverQuickJoinParty.Open() end
    elseif msg == "refresh" or msg == "sync" then
        RefreshResults()
        Print("Re-read the Group Finder's cached listings (no network search).")
    elseif msg == "activities" then
        RequestActivities()
        RefreshCategories()
        Print("Requested a new activity list.")
    elseif msg == "all" then
        if not db then ForeverQuickJoinDB = ForeverQuickJoinDB or {}; db = ForeverQuickJoinDB end
        SetAllLevelRanges(not db.allLevels)
        Print(db.allLevels and "Showing activities at all levels." or "Showing suggested-level activities only.")
    elseif msg == "retry" then
        state.searchBlocked = false
        UpdateSearchButton()
        Print("Search re-enabled. Click the Search button once. No background retry.")
    elseif msg == "status" then
        local chatLocked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
        Print(("finder; cached: %d; visible: %d; category: %s; searching: %s; blocked: %s; chat lockdown: %s")
            :format(state.totalInCache, #state.results, tostring(state.categoryID or "all"),
                tostring(state.searching), tostring(state.searchBlocked), tostring(chatLocked or false)))
    elseif msg == "" then
        ToggleWindow()
    else
        Print("Commands: /qj, /qj list, /qj find, /qj roles, /qj activities, /qj all, /qj retry, /qj status, /qj reset.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
events:RegisterEvent("ROLE_CHANGED_INFORM")
events:RegisterEvent("UNIT_LEVEL")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("UPDATE_CHAT_COLOR")
events:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
events:RegisterEvent("LFG_LIST_SEARCH_FAILED")
events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
events:RegisterEvent("WHO_LIST_UPDATE")
-- Search is attempted ONLY from the player's Search button click.
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, arg, detail)
    if event == "ADDON_LOADED" and arg == addonName then
        ForeverQuickJoinDB = type(ForeverQuickJoinDB) == "table" and ForeverQuickJoinDB or {}
        db = ForeverQuickJoinDB
        local previousDefault = type(db.template) ~= "string"
            or db.template == PREVIOUS_DEFAULT_MESSAGE
            or db.template == OLD_LOCATION_DEFAULT
            or db.template == DEFAULT_MESSAGE
            or db.template == PARTY_DEFAULT_MESSAGE
        if previousDefault then
            db.templateIsDefault = true
        elseif db.templateIsDefault ~= true then
            -- Preserve custom text, even when it contains the {party} token.
            db.templateIsDefault = false
        end
        if db.templateIsDefault then db.template = DefaultTemplate() end
        if type(db.allLevels) ~= "boolean" then db.allLevels = false end
        if type(db.filters) ~= "table" then db.filters = {} end
        if type(db.advanced) ~= "table" then db.advanced = {} end
        if type(db.advanced.excludedClasses) ~= "table" then
            db.advanced.excludedClasses = {}
        end
        -- Remove obsolete retail classes and retired controls from saved data.
        local validClasses = {}
        for _, option in ipairs(CLASS_OPTIONS) do validClasses[option[1]] = true end
        for token in pairs(db.advanced.excludedClasses) do
            if not validClasses[token] then db.advanced.excludedClasses[token] = nil end
        end
        if type(db.advanced.excludedPlaystyles) ~= "table" then
            db.advanced.excludedPlaystyles = {}
        end
        for id, checked in pairs(db.advanced.excludedPlaystyles) do
            if type(id) ~= "number" or id < 1 or id > 4 or checked ~= true then
                db.advanced.excludedPlaystyles[id] = nil
            end
        end
        -- The old playstyle picker INCLUDED one style. Do not invert its meaning:
        -- discard that obsolete selection rather than silently excluding it.
        db.advanced.playstyle = nil
        db.advanced.includeUnknown = nil
        if type(db.advanced.maxMembers) ~= "number"
            or db.advanced.maxMembers < 0 or db.advanced.maxMembers > 40 then
            db.advanced.maxMembers = 0
        end
        db.filters.hideFull = nil -- Removed in v0.5.1.
        if db.sortOrder ~= "asc" and db.sortOrder ~= "desc" then db.sortOrder = "default" end
        if type(db.minimapAngle) ~= "number" then db.minimapAngle = 225 end
        CreateMinimapButton()
    elseif event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        SyncDefaultForParty()
        Print("v0.7.0 loaded. /qj, /qj list, or the minimap button opens QuickJoin.")
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg ~= addonName then return end
        local detailText = type(Readable(detail)) == "string" and detail or ""
        local recentSearch = state.searchAttemptAt and (GetTime() - state.searchAttemptAt) < 2
        if state.searchAttemptActive or (recentSearch and detailText:find("Search", 1, true)) then
            state.searchBlocked = true
            state.searching = false
            if state.timeout and state.timeout.Cancel then state.timeout:Cancel() end
            state.timeout = nil
            UpdateSearchButton()
            Status("WoW blocked Search(). No automatic retry. Cached listings remain available.")
            Print("The client denied QuickJoin's Search(). Use /qj retry to re-enable after checking restrictions.")
        elseif state.whisperAttemptActive then
            state.whisperBlocked = true
            Status("WoW blocked this whisper. No confirmed message sent.")
            Print("WoW blocked the whisper in the current client state.")
        end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED_INDOORS" or event == "UPDATE_CHAT_COLOR" then
        if window and window:IsShown() then UpdatePreview() end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED"
        or event == "ROLE_CHANGED_INFORM" or event == "PLAYER_LEVEL_UP"
        or event == "UNIT_LEVEL" then
        SyncDefaultForParty()
    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if window and window:IsShown() then RefreshCategories() end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        FinishSearch(false)
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        FinishSearch(true, arg)
    elseif event == "WHO_LIST_UPDATE" then
        MergeWhoLocation()
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        if type(Readable(arg)) == "number" then
            state.rosterClassCache[arg] = nil
            local ok, info = pcall(C_LFGList.GetSearchResultInfo, arg)
            if ok and type(Readable(info)) == "table" then MatchSent(arg, info) end
        else
            state.rosterClassCache = {}
        end
        if window and window:IsShown() then
            -- Re-evaluate filters after Blizzard updates a member count.
            -- Preserve the page so the list does not jump while browsing.
            RebuildVisibleResults(false)
        end
    end
end)
