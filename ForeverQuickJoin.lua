-- Forever QuickJoin 0.6.0 -- host inbox, listing tools, and whisper-colored message only.
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

local db, window, categoryDropdown, activityDropdown, searchButton
local sortDropdown, locationLabel, minimapButton, clearFilterButton, templateResetButton
local filterButtons = {}
local statusLabel, pageLabel, messageBox, previewLabel, previewTitleLabel, prevButton, nextButton
local rows = {}
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
    totalInCache = 0,
    searching = false,
    searchBlocked = false,
    searchAttemptActive = false,
    searchAttemptAt = nil,
    searchActivityIDs = {},
    whisperAttemptActive = false,
    whisperBlocked = false,
}
local lastWhisperTarget, lastWhisperTime

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
    end
end

-- Since Forever 1.60.1, the search-result APIs can return *secret* values
-- during chat-messaging lockdown. Do not compare/format/index these values.
local function Readable(value)
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
    local parts = {
        level = tostring(Readable(UnitLevel("player")) or "?"),
        class = class,
        role = GetRole(),
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
    Status("Whisper attempted to " .. name .. ". Check chat for delivery.")
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
    local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
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

local function UpdateFilterButtons()
    local filters = db and db.filters or {}
    for key, button in pairs(filterButtons) do
        button:SetChecked(filters[key] == true)
    end
    if sortDropdown then
        local order = db and db.sortOrder or "default"
        local captions = {default = "Sort: Finder order", asc = "Members: fewest", desc = "Members: most"}
        sortDropdown:OverrideText(captions[order] or captions.default)
    end
end

local UpdatePages
local function RebuildVisibleResults(resetPage)
    if not db then return end
    local out = {}
    for index, id in ipairs(state.cachedResults) do
        local ok, info = pcall(C_LFGList.GetSearchResultInfo, id)
        if ok and type(Readable(info)) == "table" then
            local count = Readable(info.numMembers)
            local removed = Readable(info.isDelisted)
            local ids = Readable(info.activityIDs)
            local match = state.categoryID == nil and state.activityID == nil
            if type(ids) == "table" then
                for _, activityID in ipairs(ids) do
                    if type(Readable(activityID)) == "number" then
                        if state.activityID and activityID == state.activityID then
                            match = true; break
                        elseif state.categoryID and not state.activityID then
                            local activity = C_LFGList.GetActivityInfoTable(activityID)
                            if activity and activity.categoryID == state.categoryID then
                                match = true; break
                            elseif state.categoryAllIDs and state.categoryAllIDs[activityID] then
                                match = true; break
                            end
                        end
                    end
                end
            end
            if match and removed ~= true
                and (count == nil or (type(count) == "number" and count >= 1))
                and PassesRoleFilters(id, info) then
                table.insert(out, {id=id, count=type(count)=="number" and count or nil, original=index})
            end
        end
    end
    local order = db.sortOrder
    if order == "asc" or order == "desc" then
        table.sort(out, function(a,b)
            if a.count == nil and b.count == nil then return a.original < b.original end
            if a.count == nil then return false end
            if b.count == nil then return true end
            if a.count ~= b.count then
                if order == "asc" then return a.count < b.count end
                return a.count > b.count
            end
            return a.original < b.original
        end)
    end
    state.results = {}
    for _, item in ipairs(out) do table.insert(state.results, item.id) end
    if resetPage ~= false then state.page = 1 end
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

local function SaveFilter(field, checked)
    if not db then return end
    db.filters[field] = not not checked
    RebuildVisibleResults(true)
end

local function ResetFilters()
    if not db then return end
    db.filters = {}
    UpdateFilterButtons()
    RebuildVisibleResults(true)
end

local function SetSort(order)
    if not db then return end
    db.sortOrder = order
    UpdateFilterButtons()
    RebuildVisibleResults(true)
end

UpdatePages = function()
    if not window then return end
    local total = #state.results
    local pages = math.max(1, math.ceil(total / PAGE_SIZE))
    state.page = math.max(1, math.min(state.page, pages))
    pageLabel:SetText(("Page %d / %d  (%d groups)"):format(state.page, pages, total))
    prevButton:SetEnabled(state.page > 1)
    nextButton:SetEnabled(state.page < pages)

    for i = 1, PAGE_SIZE do
        local row = rows[i]
        local resultID = state.results[(state.page - 1) * PAGE_SIZE + i]
        row.resultID = resultID
        if not resultID then
            row:Hide()
        else
            row:Show()
            local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
            if not ok or not info then
                row.label:SetText("Expired listing")
                row.activity:SetText("")
                row.composition:SetText("")
                row.whisper:Disable()
            else
                local name = Readable(info.leaderName)
                local members = Readable(info.numMembers)
                local removed = Readable(info.isDelisted)
                local own = Readable(info.hasSelf)
                local activity = ResultActivityName(info)
                local displayName = type(name) == "string" and name ~= "" and name or "Leader hidden"
                row.label:SetText(Truncate(displayName, 23))
                row.activity:SetText(Truncate(activity, 33))
                row.composition:SetText(GroupComposition(resultID, info))
                row.whisper:SetEnabled(type(name) == "string" and name ~= ""
                    and type(members) == "number" and members >= 1 and not removed and own == false)
            end
        end
    end
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
    for _, id in ipairs(ids) do
        if type(Readable(id)) == "number" then
            table.insert(state.cachedResults, id)
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
    state.searchActivityIDs = {}
    if categoryDropdown then categoryDropdown:OverrideText(name or "All categories") end
    if activityDropdown then
        activityDropdown:OverrideText("All activities")
        activityDropdown:SetEnabled(id ~= nil)
    end
    state.categoryAllIDs = nil
    if id and C_LFGList and C_LFGList.GetAvailableActivities then
        local ok, fullIDs = pcall(C_LFGList.GetAvailableActivities, id)
        if ok and type(fullIDs) == "table" then
            state.categoryAllIDs = {}
            for _, activityID in ipairs(fullIDs) do state.categoryAllIDs[activityID] = true end
        end
    end
    if id and C_LFGList and C_LFGList.GetAvailableActivities then
        local ok, available = pcall(C_LFGList.GetAvailableActivities, id)
        if ok and type(available) == "table" then
            for _, activityID in ipairs(available) do
                if type(Readable(activityID)) == "number" then
                    table.insert(state.searchActivityIDs, activityID)
                end
            end
        end
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
            if cat.id ~= 0 then
                local ok, raw = pcall(C_LFGList.GetAvailableActivities, cat.id)
                state.categoryAllIDs = {}
                if ok and type(raw) == "table" then
                    for _, activityID in ipairs(raw) do state.categoryAllIDs[activityID] = true end
                end
            else
                state.categoryAllIDs = nil
            end
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
            state.searchActivityIDs = {}
            if cat.id ~= 0 and C_LFGList and C_LFGList.GetAvailableActivities then
                local ok, available = pcall(C_LFGList.GetAvailableActivities, cat.id)
                if ok and type(available) == "table" then
                    for _, activityID in ipairs(available) do
                        if type(Readable(activityID)) == "number" then
                            table.insert(state.searchActivityIDs, activityID)
                        end
                    end
                end
            end
            UpdateSearchButton()
            return
        end
    end
    SetCategory(categories[1].id, categories[1].name)
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
    MakeLabel(window, "Search queries the server only on click. Filters and sorting work on cached results.",
        "GameFontHighlightSmall", 25, -98, 780, 19)

    local function MakeCheck(field, x, y, label, width)
        local button = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        button:SetSize(22,22)
        button:SetPoint("TOPLEFT", window, "TOPLEFT", x,y)
        MakeLabel(button, label, "GameFontHighlightSmall", 26, -2, width or 92, 22)
        button:SetChecked(db and db.filters and db.filters[field] == true or false)
        button:SetScript("OnClick", function(self) SaveFilter(field, self:GetChecked()) end)
        filterButtons[field] = button
        return button
    end
    MakeLabel(window, "Space for:", "GameFontNormalSmall", 25, -134, 102, 22)
    MakeCheck("needTank", 127, -131, "Tank", 70)
    MakeCheck("needHealer", 250, -131, "Healer", 75)
    MakeCheck("needDps", 377, -131, "DPS", 70)
    clearFilterButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    clearFilterButton:SetSize(100,24)
    clearFilterButton:SetPoint("TOPLEFT", window, "TOPLEFT", 525, -129)
    clearFilterButton:SetText("Clear Filters")
    clearFilterButton:SetScript("OnClick", ResetFilters)

    MakeLabel(window, "Already has:", "GameFontNormalSmall", 25, -168, 102, 22)
    MakeCheck("hasTank", 127, -164, "Tank", 70)
    MakeCheck("hasHealer", 250, -164, "Healer", 75)
    MakeLabel(window, "Sort by:", "GameFontNormalSmall", 500, -166, 80, 22)
    sortDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
    sortDropdown:SetWidth(185)
    sortDropdown:SetPoint("TOPLEFT", window, "TOPLEFT", 575, -162)
    sortDropdown:SetDefaultText("Sort: Finder order")
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
    UpdateFilterButtons()

    MakeLabel(window, "GROUP LISTINGS", "GameFontNormal", 26, -198, 570, 20)
    MakeLabel(window, "LEADER", "GameFontNormalSmall", 36, -214, 160, 16)
    MakeLabel(window, "ACTIVITY", "GameFontNormalSmall", 211, -214, 205, 16)
    MakeLabel(window, "GROUP ROLES", "GameFontNormalSmall", 442, -214, 210, 16)

    for i = 1, PAGE_SIZE do
        local row = CreateFrame("Frame", nil, window, "BackdropTemplate")
        row:SetSize(790, 34)
        row:SetPoint("TOPLEFT", window, "TOPLEFT", 24, -(234 + (i - 1) * 35))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row:SetBackdropColor(0.10, 0.12, 0.16, 1)
        row.label = MakeLabel(row, "", "GameFontHighlightSmall", 10, -8, 168, 22)
        row.activity = MakeLabel(row, "", "GameFontHighlightSmall", 187, -8, 225, 22)
        row.composition = MakeLabel(row, "", "GameFontHighlightSmall", 416, -8, 246, 22)
        row.whisper = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.whisper:SetSize(117, 24)
        row.whisper:SetPoint("RIGHT", row, "RIGHT", -6, 0)
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
    prevButton:SetScript("OnClick", function() state.page = state.page - 1; UpdatePages() end)
    nextButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    nextButton:SetSize(90, 24)
    nextButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -25, -562)
    nextButton:SetText("Next")
    nextButton:SetScript("OnClick", function() state.page = state.page + 1; UpdatePages() end)
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
    previewTitleLabel = MakeLabel(window, "Preview:", "GameFontNormalSmall", 26, -655, 70, 24)
    previewLabel = MakeLabel(window, "", "GameFontHighlightSmall", 98, -655, 702, 55)
    previewLabel:SetJustifyV("TOP")
    locationLabel = MakeLabel(window, "", "GameFontNormalSmall", 26, -717, 785, 20)
    statusLabel = MakeLabel(window, "Waiting for activities...", "GameFontHighlightSmall", 26, -741, 785, 20)

    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", function(_, delta)
        local pages = math.max(1, math.ceil(#state.results / PAGE_SIZE))
        state.page = math.max(1, math.min(pages, state.page - delta))
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
    elseif msg == "refresh" or msg == "sync" then
        RefreshResults()
        Print("Re-read the Group Finder's cached listings (no network search).")
    elseif msg == "activities" then
        RequestActivities()
        RefreshCategories()
        Print("Requested a new activity list.")
    elseif msg == "all" then
        if not db then ForeverQuickJoinDB = ForeverQuickJoinDB or {}; db = ForeverQuickJoinDB end
        db.allLevels = not db.allLevels
        RefreshCategories()
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
        Print("Commands: /qj, /qj list, /qj find, /qj activities, /qj all, /qj retry, /qj status, /qj reset.")
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
        db.filters.hideFull = nil -- Removed in v0.5.1.
        if db.sortOrder ~= "asc" and db.sortOrder ~= "desc" then db.sortOrder = "default" end
        if type(db.minimapAngle) ~= "number" then db.minimapAngle = 225 end
        CreateMinimapButton()
    elseif event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        SyncDefaultForParty()
        Print("v0.6.0 loaded. /qj, /qj list, or the minimap button opens QuickJoin.")
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
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        if window and window:IsShown() then
            -- Re-evaluate filters after Blizzard updates a member count.
            -- Preserve the page so the list does not jump while browsing.
            RebuildVisibleResults(false)
        end
    end
end)
