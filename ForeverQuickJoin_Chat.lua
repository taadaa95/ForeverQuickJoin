-- Forever QuickJoin: LFG Chat + Invite, integrated into the main addon (v0.9.4).
-- Group finder filters and UI remain owned by ForeverQuickJoin.
-- No addon messages, background whispers, automated invitations, or server searches.
-- Chat bodies are session-only and are never written to SavedVariables.
local ADDON = ...
local PREFIX = "|cff69c3ffQuickJoin Chat|r: "
local TTL, LIMIT, ROW_COUNT = 600, 160, 6
local data, byKey, counters, channels = {}, {}, {channel = 0, say = 0, yell = 0, classified = 0, rejected = 0, secret = 0}, {}
local root, findContent, chatPanel, canvas, viewport, status, instructions, pageInfo
local listingTab, chatTab, listingRows, oldHeading
local chatRows = {}
local selected = "listings"
local mainIsFind = true
local suppressThemeHook = false
local lastAction = {}
local currentFilter = "all"
local categoryDropdown, activityDropdown, playstyleDropdown
local selection = {category = nil, activity = "All activities", multiple = false}
local hiddenFinder = {}
local inviteRecords, recentInviteName = {}, nil
local joinAttempts, joinLastAttempt, joinState = 0, 0, "not checked"
local inboxSortReason = "Native inboxes sort by most recent activity"



local function Print(v)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(v)) end
end

local function Readable(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    if type(canaccessvalue) == "function" and not canaccessvalue(v) then return nil end
    return v
end

local function SafeString(v)
    v = Readable(v)
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

local function ForDisplay(v, limit)
    v = (v or ""):gsub("[\r\n]", " "):gsub("|", "||")
    if limit and #v > limit then return v:sub(1, limit - 3) .. "..." end
    return v
end

local function Now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function Has(s, word)
    local escaped = word:gsub("([^%w%s])", "%%%1")
    return s:find("%f[%w]" .. escaped .. "%f[%W]") ~= nil
end

local function HasAny(s, words)
    for _, w in ipairs(words) do if Has(s, w) then return true end end
    return false
end

local instances = {
    {"Scarlet Monastery", {"sm", "sm cath", "sm gy", "sm arm", "sm lib", "scarlet monastery", "cathedral"}},
    {"Shadowfang Keep", {"sfk", "shadowfang"}},
    {"Deadmines", {"deadmines", "vc", "vancleef", "dm westfall"}},
    {"Wailing Caverns", {"wc", "wailing caverns"}},
    {"Ragefire Chasm", {"rfc", "ragefire"}},
    {"Blackfathom Deeps", {"bfd", "blackfathom"}},
    {"Stockades", {"stocks", "stockades", "stockade"}},
    {"Gnomeregan", {"gnomer", "gnomeregan"}},
    {"Razorfen Kraul", {"rfk", "razorfen kraul"}},
    {"Razorfen Downs", {"rfd", "razorfen downs"}},
    {"Uldaman", {"ulda", "uldaman"}},
    {"Zul'Farrak", {"zf", "zulfarrak", "zul farrak"}},
    {"Maraudon", {"mara", "maraudon"}},
    {"Sunken Temple", {"sunken temple", "temple of atal", "atal hakkar"}},
    {"Blackrock Depths", {"brd", "blackrock depths"}},
    {"Blackrock Spire", {"lbrs", "ubrs", "blackrock spire"}},
    {"Dire Maul", {"dire maul", "dme", "dmw", "dmn", "dm east", "dm north"}},
    {"Stratholme", {"strat", "stratholme"}},
    {"Scholomance", {"scholo", "scholomance"}},
    {"Onyxia", {"ony", "onyxia"}},
    {"Molten Core", {"mc", "molten core"}},
    {"Zul'Gurub", {"zg", "zulgurub", "zul gurub"}},
    {"Blackwing Lair", {"bwl", "blackwing lair"}},
    {"Ahn'Qiraj", {"aq20", "aq40", "ahn qiraj"}},
    {"Naxxramas", {"naxx", "naxxramas"}},
    {"Hall of Thanes", {"hall of thanes", "hot"}},
    {"Ruins of Lordaeron", {"ruins of lordaeron", "rol"}},
    {"Excavation Site", {"excavation site"}},
    {"City of Dalaran", {"city of dalaran"}},
    {"The Drowned City", {"drowned city"}},
    {"Alcaz Prison", {"alcaz prison"}},
    {"Blackmaw Hold", {"blackmaw hold"}},
    {"Shaper's Terrace", {"shapers terrace", "shaper's terrace"}},
    {"Hyjal Summit", {"hyjal summit"}},
    {"Barrow Deeps", {"barrow deeps"}},
    {"Krol'dok Stronghold", {"kroldok stronghold", "krol'dok stronghold"}},
}

-- A dungeon token by itself is only a hint: normal conversation about SM or WC
-- is not a recruiting post. Require independent recruitment language or roles.
local raidActivities = {
    ["Onyxia"] = true, ["Molten Core"] = true, ["Zul'Gurub"] = true,
    ["Blackwing Lair"] = true, ["Ahn'Qiraj"] = true, ["Naxxramas"] = true,
    ["Hyjal Summit"] = true,
}

local function NormalizeWords(s)
    if type(s) ~= "string" then return "" end
    return s:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("[^%w%s]", " ")
        :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function Classify(message)
    local s = message:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|h.-|h", " "):gsub("[%p]", function(ch)
        if ch == "'" or ch == "-" then return ch end
        return " "
    end)
    s = s:gsub("%s+", " ")
    if HasAny(s, {"wts", "wtb", "wtt", "selling", "buying", "boosting", "carry", "boosts", "portal", "summons"})
       and not HasAny(s, {"lfg", "lfm", "looking for group"}) then return nil end
    if HasAny(s, {"guild", "guildmates", "recruiting for guild", "join our guild"})
       and not HasAny(s, {"lfg", "lfm", "lf1m", "lf2m", "lf3m"}) then return nil end

    local needs = HasAny(s, {"need tank", "need healer", "need heal", "need heals", "need dps", "looking for tank", "looking for healer", "looking for dps", "group for", "forming group"})
    needs = needs or s:find("%f[%w]need%s+%d*%s*tank%f[%W]") or s:find("%f[%w]need%s+%d*%s*heal%w*%f[%W]")
        or s:find("%f[%w]need%s+%d*%s*dps%f[%W]")
        or s:find("%f[%w]lf%s+%d*%s*tank%f[%W]") or s:find("%f[%w]lf%s+%d*%s*heal%w*%f[%W]")
        or s:find("%f[%w]lf%s+%d*%s*dps%f[%W]")
        or s:find("%-%s*%d+%s*tank%f[%W]") or s:find("%-%s*%d+%s*dps%f[%W]")
    local lfm = HasAny(s, {"lfm", "lf1m", "lf2m", "lf3m", "lf4m", "lf5m", "looking for more", "looking for members"}) or needs
    local lfg = HasAny(s, {"lfg", "looking for group", "looking for a group", "anyone running", "anyone doing"})
        or s:find("%f[%w]tank%s+lf%f[%W]") or s:find("%f[%w]dps%s+lf%f[%W]")
        or s:find("%f[%w]heal%w*%s+lf%f[%W]")
    local activity = "Unspecified"
    local category = "unspecified"
    local found = false
    for _, entry in ipairs(instances) do
        for _, word in ipairs(entry[2]) do
            if Has(s, word) then
                activity = entry[1]
                category = raidActivities[activity] and "raid" or "dungeon"
                found = true
                break
            end
        end
        if found then break end
    end
    if not found and Has(s, "dm") then activity = "DM (ambiguous)"; category="dungeon"; found = true end
    if not found and HasAny(s,{"dungeon", "dungeons", "instance", "instances"}) then
        activity="Any dungeon"; category="dungeon"
    elseif not found and HasAny(s,{"raid", "raids"}) then
        activity="Any raid"; category="raid"
    end
    if not found and (HasAny(s,{"quest", "quests", "questing", "elite", "escorts", "group quest", "zone", "grinding"})
        or s:find("%f[%w]q%s*%d+%f[%W]")) then
        activity="Quests / Zones"
        category="quest"
    end
    if not lfm and not lfg then
        -- Allow a dungeon name + clear role vacancies even without 'LFM'.
        local roleVacancy = s:find("%f[%w]%d+%s*tanks?%f[%W]")
            or s:find("%f[%w]%d+%s*healers?%f[%W]")
            or s:find("%f[%w]%d+%s*dps%f[%W]")
        if not (found and roleVacancy) then return nil end
        lfm = true
    end
    local roles = {}
    if HasAny(s, {"tank", "tanks"}) then roles[#roles+1] = "Tank" end
    if HasAny(s, {"heal", "heals", "healer", "healers"}) then roles[#roles+1] = "Healer" end
    if Has(s, "dps") then roles[#roles+1] = "DPS" end
    return { kind = lfm and "LFM" or "LFG", activity = activity,
        category = category, roles = table.concat(roles, ", ") }
end

local function NormalizeChannel(channelName, channelBaseName)
    local n = SafeString(channelBaseName) or SafeString(channelName) or "Public"
    n = n:gsub("^%d+%.%s*", "")
    n = n:match("^(.-)%s+%-%s+") or n
    return n
end

local function Prune()
    local now = Now()
    local changed = false
    for i = #data, 1, -1 do
        if now - data[i].time >= TTL then
            byKey[data[i].key] = nil
            table.remove(data, i)
            changed = true
        end
    end
    return changed
end

local Refresh, RefreshListingButtons
local function AddPost(message, sender, channel, synthetic)
    message, sender = SafeString(message), SafeString(sender)
    if not message or not sender then counters.secret = counters.secret + 1; return end
    if sender == SafeString(UnitName and UnitName("player")) then return end
    local classified = Classify(message)
    if not classified then counters.rejected = counters.rejected + 1; return end
    counters.classified = counters.classified + 1
    local key = sender:lower() .. "\031" .. message:lower():gsub("%s+", " ")
    local entry = byKey[key]
    if entry then
        entry.time = Now()
        entry.channel = channel
        entry.repeats = entry.repeats + 1
    else
        entry = { key = key, sender = sender, text = message, channel = channel,
            time = Now(), kind = classified.kind, activity = classified.activity,
            category = classified.category, roles = classified.roles, repeats = 1,
            synthetic = synthetic == true, whisper = false }
        byKey[key] = entry
        table.insert(data, entry)
    end
    -- One entry per repeated post; most recent first.
    for i, e in ipairs(data) do if e == entry then table.remove(data, i); break end end
    table.insert(data, 1, entry)
    while #data > LIMIT do
        local removed = table.remove(data)
        byKey[removed.key] = nil
    end
    if Refresh then Refresh() end
end

-- Treat the native Find Groups category/activity dropdowns as authoritative.
-- The base addon owns selectedActivityIDs as a private local. A single selection
-- is displayed by name. For multiple selections we conservatively keep the
-- category filter instead of inventing a set of unknown activity IDs.
local function SelectedCategory()
    local caption = NormalizeWords(selection.category or "")
    if caption:find("dungeon",1,true) then return "dungeon" end
    if caption:find("raid",1,true) then return "raid" end
    if caption:find("quest",1,true) or caption:find("zone",1,true) then return "quest" end
    return "all"
end

local function SelectedActivity()
    local caption=SafeString(selection.activity) or "All activities"
    if selection.multiple or caption:lower():find("all activities",1,true) then return nil end
    caption=caption:gsub("%s*%([^)]*%)%s*$", "")
    return NormalizeWords(caption)
end

local function IsActivityMatch(entry,activity)
    if not activity then return true end
    if activity==NormalizeWords(entry.activity) then return true end
    local raw=NormalizeWords(entry.text)
    -- Full official names and short aliases are accepted. A specific selected
    -- dungeon must not match a generic 'LFM need healer' advertisement.
    for _, known in ipairs(instances) do
        if NormalizeWords(known[1])==activity then
            for _, alias in ipairs(known[2]) do
                local needle=NormalizeWords(alias)
                if needle~="" and Has(raw,needle) then return true end
            end
            return false
        end
    end
    return activity~="" and Has(raw,activity) ~= false
end

local function EnabledCategory(e)
    if not e or (currentFilter~="all" and e.kind~=currentFilter) then return false end
    local cat=SelectedCategory()
    if cat~="all" and cat~=e.category then
        -- A named custom activity can appear in a quest/zone chat message even
        -- when our classifier doesn't know its category (and vice versa).
        if not (SelectedActivity() and IsActivityMatch(e,SelectedActivity())) then return false end
    end
    return IsActivityMatch(e,SelectedActivity())
end

local function VisibleEntries()
    local shown={}
    for _,e in ipairs(data) do if EnabledCategory(e) then shown[#shown+1]=e end end
    return shown
end

local function ActionStatus(msg)
    if status then status:SetText(msg) end
    Print(msg)
end

local function CanInvite()
    if type(IsInGroup) == "function" and IsInGroup() then
        local leader = (type(UnitIsGroupLeader)=="function" and UnitIsGroupLeader("player"))
            or (type(IsPartyLeader)=="function" and IsPartyLeader())
        if not leader then return false end
    end
    return true
end

local function NameKey(name)
    return (SafeString(name) or ""):lower()
end

local function StatusOfInvite(name)
    local record=inviteRecords[NameKey(name)]
    if not record then return nil end
    if Now()-(record.started or 0)>600 then
        inviteRecords[NameKey(name)]=nil
        return nil
    end
    if record.state=="pending" and Now()-record.started>=5 then
        record.state="unconfirmed"
    end
    return record.state
end

local function AttemptInvite(name, entry)
    name=SafeString(name)
    if not name then ActionStatus("Player name unavailable; cannot invite."); return false end
    if not CanInvite() then ActionStatus("You must be party/raid leader to invite players."); return false end
    if type(InCombatLockdown)=="function" and InCombatLockdown() then
        ActionStatus("Leave combat before inviting."); return false
    end
    local fn=(C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if type(fn)~="function" then ActionStatus("Invite API unavailable."); return false end
    if type(C_PartyInfo)=="table" and type(C_PartyInfo.IsPartyFull)=="function"
        and Readable(C_PartyInfo.IsPartyFull())==true then
        ActionStatus("Your party is full; no invitation attempted."); return false
    end
    local key=NameKey(name)
    inviteRecords[key]={target=name,started=Now(),state="pending"}
    recentInviteName=key
    -- Called directly by the player's Invite button only (never from a timer).
    local sentResult=fn(name)
    if sentResult==false then
        inviteRecords[key].state="failed"
        ActionStatus("The client rejected the invitation to "..name..".")
        if Refresh then Refresh() end
        return false
    end
    if entry then entry.inviteTarget=name end
    ActionStatus("Invitation requested for "..name.."; waiting for a client response.")
    if Refresh then Refresh() end
    if C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(5.1,function()
            local record=inviteRecords[key]
            if record and record.state=="pending" then
                record.state="unconfirmed"
                if Refresh then Refresh() end
                if root and root:IsShown() then RefreshListingButtons() end
            end
        end)
    end
    return true
end

-- A client acknowledgement or error is more trustworthy than InviteUnit's
-- return value, which does NOT mean the target got an invitation.
local FAIL_MESSAGE_KEYS={"ERR_ALREADY_IN_GROUP_S","ERR_INVITED_ALREADY_IN_GROUP_SS",
    "ERR_BAD_PLAYER_NAME_S","ERR_PLAYER_BUSY_S","ERR_NOT_LEADER",
    "ERR_GROUP_FULL","ERR_INVITE_SELF","ERR_INVITE_IN_COMBAT",
    "ERR_INVITE_PARTY_BUSY","ERR_ALREADY_INVITED_TO_GROUP_S",
    "ERR_CROSS_REALM_RAID_INVITE","ERR_PARTY_TARGET_AMBIGUOUS"}
local function MatchesTemplate(template,message)
    if type(template)~="string" or type(message)~="string" then return false end
    local token="QQQINVITENAMEQQQ"
    local pattern=template:gsub("%%[%d%.%-%+]*[sd]",token)
    pattern=pattern:gsub("([^%w%s])","%%%1"):gsub(token,".+")
    return message:match("^"..pattern.."$")~=nil
end
local function HandleInviteFeedback(message)
    message=SafeString(message)
    if not message then return end
    local key=recentInviteName
    local rec=key and inviteRecords[key]
    if not rec or Now()-rec.started>15 then return end
    local name=rec.target
    local shortName=name:match("^[^-]+") or name
    local mentioned=message:lower():find(name:lower(),1,true)
        or message:lower():find(shortName:lower(),1,true)
    local success=MatchesTemplate(_G.ERR_INVITE_PLAYER_S,message)
    local failed=false
    for _,constant in ipairs(FAIL_MESSAGE_KEYS) do
        if MatchesTemplate(_G[constant],message) then failed=true; break end
    end
    local lower=message:lower()
    if not success and mentioned and (lower:find("you have invited",1,true)
        or lower:find("invitation sent",1,true)) then success=true end
    if not failed and (mentioned or (type(name)=="string" and name~="")) then
        if lower:find("already in a group",1,true)
            or lower:find("cannot find player",1,true)
            or lower:find("not the party leader",1,true)
            or lower:find("party is full",1,true)
            or lower:find("busy right now",1,true) then
            failed=mentioned or lower:find("party is full",1,true)
        end
    end
    if failed then
        rec.state="failed"
        ActionStatus("Invitation failed for "..name..": "..ForDisplay(message,150))
    elseif success and mentioned then
        rec.state="confirmed"
        ActionStatus("Client acknowledged an invitation to "..name.." (acceptance not guaranteed).")
    else
        return
    end
    if Refresh then Refresh() end
    if root and root:IsShown() then RefreshListingButtons() end
end

local function RoleName()
    local role=ForeverQuickJoinParty and ForeverQuickJoinParty.RoleFor
        and Readable(ForeverQuickJoinParty.RoleFor("player"))
    if role=="TANK" then return "Tank" end
    if role=="HEALER" then return "Healer" end
    if role=="DAMAGER" then return "DPS" end
    if role=="UNKNOWN" then return "Unassigned" end
    local fn=C_LFGListRoles and C_LFGListRoles.GetRoles
    if type(fn)=="function" then
        local ok,v=pcall(fn)
        v=ok and Readable(v) or nil
        if type(v)=="table" then
            if Readable(v.tank)==true and Readable(v.healer)~=true and Readable(v.dps)~=true then return "Tank" end
            if Readable(v.healer)==true and Readable(v.tank)~=true and Readable(v.dps)~=true then return "Healer" end
        end
    end
    return "DPS"
end

local function MakeChatWhisper(entry)
    if entry.kind=="LFG" then
        return "I saw your LFG post for "..entry.activity..". Are you still looking for a group?"
    end
    local level=tonumber(Readable(type(UnitLevel)=="function" and UnitLevel("player"))) or 0
    local class=SafeString(type(UnitClass)=="function" and UnitClass("player")) or "player"
    local name=SafeString(type(UnitName)=="function" and UnitName("player")) or "player"
    local zone=SafeString(type(GetZoneText)=="function" and GetZoneText()) or "Unknown location"
    local role=RoleName()
    local partyNames={}
    local total=tonumber(Readable(type(GetNumGroupMembers)=="function" and GetNumGroupMembers())) or 1
    local inRaid=type(IsInRaid)=="function" and IsInRaid()
    if total>1 then
        local count=inRaid and total or math.min(total-1,4)
        for i=1,count do
            local unit=(inRaid and "raid" or "party")..i
            local same=type(UnitIsUnit)=="function" and Readable(UnitIsUnit(unit,"player"))
            if same~=true then
                local member=SafeString(type(UnitName)=="function" and UnitName(unit))
                if member then partyNames[#partyNames+1]=member end
            end
        end
    end
    local template=(type(ForeverQuickJoinDB)=="table" and SafeString(ForeverQuickJoinDB.template))
        or "Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!"
    local values={level=tostring(level),class=class,name=name,role=role,
        activity=entry.activity,location=zone,party=table.concat(partyNames, "; "),partycount=tostring(total)}
    local message=template:gsub("{([%w_]+)}",function(k)
        k=k:lower()
        return values[k] or "{"..k.."}"
    end)
    return message:gsub("^%s+",""):gsub("%s+$","")
end

local function AttemptWhisper(entry)
    if not entry or not SafeString(entry.sender) or entry.synthetic then return end
    if type(C_ChatInfo)=="table" and type(C_ChatInfo.InChatMessagingLockdown)=="function"
        and C_ChatInfo.InChatMessagingLockdown() then
        ActionStatus("Chat messaging is locked; no whisper sent."); return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(send) ~= "function" then ActionStatus("Chat API unavailable."); return end
    local msg=MakeChatWhisper(entry)
    if #msg>255 then
        ActionStatus("Whisper exceeds 255 bytes; shorten your Group Listings template.")
        return
    end
    send(msg, "WHISPER", nil, entry.sender) -- direct player click
    entry.whisper = true
    lastAction.whisper = entry.sender
    ActionStatus("Whisper submitted to " .. entry.sender .. " (not delivery confirmation).")
    if Refresh then Refresh() end
end

local function Button(parent, title, x, y, w, h, fn)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(w, h)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    button:SetText(title)
    button:SetScript("OnClick", fn)
    return button
end

local function Label(parent, title, x, y, w, h, font)
    local label = parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    label:SetSize(w,h)
    label:SetJustifyH("LEFT")
    label:SetText(title)
    return label
end

local function RefreshButtonState(button, active)
    button:SetEnabled(not active)
    if button.GetFontString then
        local font = button:GetFontString()
        if font and font.SetTextColor then font:SetTextColor(active and 0.55 or 1, active and 0.95 or 0.85, active and 0.55 or 0.7) end
    end
end

RefreshListingButtons = function()
    if not listingRows then return end
    for _, row in ipairs(listingRows) do
        if row.qjChatInvite then
            row.qjLeaderGrouped=false
            local id = Readable(row.resultID)
            local name, valid = nil, false
            if type(id)=="number" and C_LFGList and type(C_LFGList.GetSearchResultInfo)=="function" then
                local ok, info = pcall(C_LFGList.GetSearchResultInfo, id)
                if ok and type(Readable(info))=="table" then
                    name = SafeString(info.leaderName)
                    local own = Readable(info.hasSelf)
                    local gone = Readable(info.isDelisted)
                    local count = Readable(info.numMembers)
                    valid = name ~= nil and own == false and gone == false
                        and type(count)=="number" and count == 1
                    row.qjLeaderGrouped = type(count)=="number" and count>1
                end
            end
            row.qjChatInvite:SetEnabled(valid)
            row.qjChatInvite.target = valid and name or nil
            local inviteState = name and StatusOfInvite(name)
            local buttonText=inviteState=="pending" and "..."
                or inviteState=="confirmed" and "Sent"
                or inviteState=="failed" and "Failed"
                or inviteState=="unconfirmed" and "?"
                or inviteState=="joined" and "Joined"
                or (row.qjLeaderGrouped and "In grp" or "Invite")
            row.qjChatInvite:SetText(buttonText)
            local label = row.qjChatInvite.GetFontString and row.qjChatInvite:GetFontString()
            if label and label.SetTextColor then
                label:SetTextColor(inviteState=="confirmed" and .25 or 1,
                    inviteState=="confirmed" and 1 or .84,inviteState=="confirmed" and .45 or .62)
            end
        end
    end
end

local function InstallListingRows(rows)
    listingRows = rows
    for _, row in ipairs(rows) do
        if row.whisper and not row.qjChatInvite then
            -- Allocate space for Invite by slightly narrowing the roles column;
            -- the original Sent/Reply marker remains the Whisper indicator.
            if row.composition then row.composition:SetWidth(140) end
            if row.sentBadge then
                row.sentBadge:ClearAllPoints()
                row.sentBadge:SetPoint("TOPLEFT",row,"TOPLEFT",559,-8)
                row.sentBadge:SetWidth(38)
            end
            row.whisper:ClearAllPoints()
            row.whisper:SetSize(105,24)
            row.whisper:SetPoint("TOPRIGHT",row,"TOPRIGHT",-57,-5)
            local invite=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
            invite:SetSize(51,24)
            invite:SetPoint("TOPRIGHT",row,"TOPRIGHT",-4,-5)
            invite:SetText("Invite")
            invite:SetScript("OnClick",function(self)
                if not self.target then return end
                AttemptInvite(self.target)
                RefreshListingButtons()
            end)
            invite:SetScript("OnEnter",function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                    GameTooltip:AddLine("Invite the listing leader",1,.83,0)
                    GameTooltip:AddLine("Only solo leaders can be invited. Sent means the client acknowledged the invite; ? means unconfirmed; Failed indicates a reported error.",1,1,1,true)
                    GameTooltip:Show()
                end
            end)
            invite:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
            row.qjChatInvite=invite
        end
    end
    RefreshListingButtons()
end

-- Native controls are discovered by parent and creation order, not by a
-- global patch to a Blizzard dropdown or the protected search API.
local function DropdownCaption(drop)
    if not drop then return nil end
    local function Value(source)
        if not source then return nil end
        local fn=source.GetText
        if type(fn)=="function" then
            local ok,v=pcall(fn,source)
            if ok then return SafeString(v) end
        end
    end
    local result=Value(drop.Text) or Value(drop.text) or Value(drop.DropdownText) or Value(drop)
    if result then return result end
    if type(drop.GetRegions)=="function" then
        for _,region in ipairs({drop:GetRegions()}) do
            result=Value(region)
            if result then return result end
        end
    end
    if type(drop.GetChildren)=="function" then
        for _,child in ipairs({drop:GetChildren()}) do
            result=Value(child.Text) or Value(child)
            if result then return result end
            if type(child.GetRegions)=="function" then
                for _,region in ipairs({child:GetRegions()}) do
                    result=Value(region)
                    if result then return result end
                end
            end
        end
    end
end

local function CaptureCategory(caption)
    if not SafeString(caption) then return end
    selection.category=caption
    if chatPanel then chatPanel.scrollOffset=0 end
    if Refresh then Refresh() end
end
local function CaptureActivity(caption)
    if not SafeString(caption) then return end
    selection.activity=caption
    selection.multiple=caption:lower():find("activities selected",1,true)~=nil
    if chatPanel then chatPanel.scrollOffset=0 end
    if Refresh then Refresh() end
end

local function InstallNativeControls()
    local drops={}
    if not findContent or type(findContent.GetChildren)~="function" then return end
    for _,child in ipairs({findContent:GetChildren()}) do
        if child.GetObjectType and child:GetObjectType()=="DropdownButton" then
            drops[#drops+1]=child
        end
    end
    categoryDropdown,activityDropdown,playstyleDropdown=drops[1],drops[2],drops[3]
    if categoryDropdown then
        local caption=DropdownCaption(categoryDropdown)
        if caption then CaptureCategory(caption) end
        if type(hooksecurefunc)=="function" then
            hooksecurefunc(categoryDropdown,"OverrideText",function(_,txt) CaptureCategory(txt) end)
        end
    end
    if activityDropdown then
        local caption=DropdownCaption(activityDropdown)
        if caption then CaptureActivity(caption) end
        if type(hooksecurefunc)=="function" then
            hooksecurefunc(activityDropdown,"OverrideText",function(_,txt) CaptureActivity(txt) end)
        end
    end
    if playstyleDropdown then
        playstyleDropdown:Hide()
        if type(playstyleDropdown.HookScript)=="function" then
            playstyleDropdown:HookScript("OnShow",function(self) self:Hide() end)
        end
    end
end

local function FinderBelowNav(item)
    if item==oldHeading or not item or type(item.GetPoint)~="function" then return false end
    local _,_,_,_,y=item:GetPoint(1)
    -- The original My Applications action is at y=205: keep it available on
    -- both finder pages. Category/activity controls remain visible as well.
    if type(y)=="number" and y<=-230 then return true end
    if item.GetObjectType and item:GetObjectType()=="ScrollFrame"
        and item.GetWidth and item:GetWidth()==764 then return true end
    return false
end

local function HideOriginalResults(hide)
    if not findContent then return end
    local function Process(frame)
        if not frame then return end
        if hide then
            if hiddenFinder[frame]==nil then
                hiddenFinder[frame]=frame:IsShown()==true
            end
            frame:Hide()
        else
            local visible=hiddenFinder[frame]
            if visible~=nil then
                hiddenFinder[frame]=nil
                if visible then frame:Show() end
            end
        end
    end
    if hide then
        if type(findContent.GetChildren)=="function" then
            for _,child in ipairs({findContent:GetChildren()}) do
                if FinderBelowNav(child) then Process(child) end
            end
        end
        if type(findContent.GetRegions)=="function" then
            for _,region in ipairs({findContent:GetRegions()}) do
                if FinderBelowNav(region) then Process(region) end
            end
        end
    else
        for frame,wasShown in pairs(hiddenFinder) do
            hiddenFinder[frame]=nil
            if wasShown then frame:Show() end
        end
    end
    if oldHeading then oldHeading:Hide() end
end

local function FixResultsLayout(window)
    if not window or not findContent then return end
    -- The role ribbon is y=117..193; the tabs are now y=205..229. Native
    -- result headers and the scroll viewport move down by 26px, and the scroll
    -- viewport is correspondingly shorter so the pager stays in place.
    if type(findContent.GetRegions)=="function" then
        for _,region in ipairs({findContent:GetRegions()}) do
            local caption=region.GetText and region:GetText()
            local x=caption=="LEADER" and 36
                or caption=="ACTIVITY / PLAYSTYLE" and 211
                or caption=="GROUP ROLES" and 442
            if x then
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT",findContent,"TOPLEFT",x,-240)
            end
        end
    end
    if type(findContent.GetChildren)=="function" then
        for _,child in ipairs({findContent:GetChildren()}) do
            if child.GetObjectType and child:GetObjectType()=="ScrollFrame"
                and child.GetWidth and child:GetWidth()==764 then
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT",window,"TOPLEFT",24,-261)
                child:SetSize(764,288)
                break
            end
        end
    end
end

-- Both native inbox modules now order messages by recent activity.
-- No debug.getupvalue or debug.setupvalue introspection is required.

local function JoinedChannel()
    if type(GetChannelName)~="function" then return false end
    local id=Readable(GetChannelName("LookingForGroup"))
    return type(id)=="number" and id>0
end
local function TryJoinLFG(force)
    if JoinedChannel() then joinState="joined";return true end
    local pref=type(ForeverQuickJoinDB)=="table"
        and ForeverQuickJoinDB.chatAutoJoin~=false
    if not force and not pref then joinState="disabled";return false end
    if not force and joinAttempts>=2 then return false end
    if type(JoinPermanentChannel)~="function" then
        joinState="JoinPermanentChannel unavailable";return false
    end
    if type(InCombatLockdown)=="function" and InCombatLockdown() then
        joinState="waiting for combat end"; return false
    end
    joinAttempts=joinAttempts+1
    joinLastAttempt=Now()
    joinState="attempted; checking"
    local frameId=ChatFrame1 and ChatFrame1.GetID and ChatFrame1:GetID() or nil
    -- This is the standard client API for joining a public chat channel.
    -- It does not send a whisper, group request or protected LFG search.
    local ok=pcall(JoinPermanentChannel,"LookingForGroup",nil,frameId)
    if not ok then joinState="client blocked join";return false end
    if JoinedChannel() then joinState="joined" end
    if C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(2,function()
            if JoinedChannel() then joinState="joined"
            else joinState="not joined (use /qjchat join or /join LookingForGroup)" end
            if Refresh then Refresh() end
        end)
    end
    return true
end

local function UpdateAppearance()
    if not root then return end
    if listingTab and chatTab then
        local _, translucent = ForeverQuickJoinTheme and ForeverQuickJoinTheme.Current and ForeverQuickJoinTheme.Current()
        local activeAlpha = translucent and 0.45 or 1
        for _, row in ipairs(chatRows) do
            if row.SetBackdropColor then row:SetBackdropColor(.09,.11,.16,activeAlpha) end
        end
    end
end

local function SetMode(mode)
    if not root then return end
    selected=mode
    if not mainIsFind then return end
    -- Keep the category/activity selectors visible on both finder views;
    -- hide only the native list/results area when LFG Chat is selected.
    if findContent then findContent:Show() end
    HideOriginalResults(mode=="chat")
    if chatPanel then chatPanel:SetShown(mode=="chat") end
    if listingTab then RefreshButtonState(listingTab,mode=="listings") end
    if chatTab then RefreshButtonState(chatTab,mode=="chat") end
    if mode=="listings" then RefreshListingButtons() end
    if mode=="chat" and joinAttempts==0 then TryJoinLFG(false) end
    if Refresh then Refresh() end
end

Refresh = function()
    if not chatPanel or not viewport then return end
    Prune()
    local showing = VisibleEntries()
    local seen = counters.channel+counters.say+counters.yell
    local label = string.format("%d matching | %d received | %d non-recruitment | %s / %s",
        #showing,seen,counters.rejected,selection.category or "All categories",
        selection.multiple and "multiple activities (category only)" or selection.activity or "All activities")
    if pageInfo then pageInfo:SetText(ForDisplay(label,115)) end
    if instructions then
        if seen==0 then
            instructions:SetText("No public messages yet. Auto-join LFG: "..joinState..". General/Trade are monitored when your character receives them. /qjchat diag")
        elseif #showing==0 then
            if #data>0 then
                instructions:SetText("Recruitment posts were detected, but none match the selected category/activity. Change the selection above or use /qjchat diag.")
            else
                instructions:SetText("Public chat is arriving, but no recruiting language matched. Use /qjchat diag or /qjchat test.")
            end
        else
            instructions:SetText("Live public chat only; posts expire after 10 min. Invite Sent requires client acknowledgement; LFM posters may already lead a group.")
        end
    end
    canvas:SetHeight(viewport:GetHeight())
    for i, row in ipairs(chatRows) do
        local e = showing[i + (chatPanel.scrollOffset or 0)]
        row.entry = e
        if e then
            row:Show()
            local age = math.floor(math.max(0, Now()-e.time)/60)
            row.name:SetText(ForDisplay(e.sender,25)..(e.synthetic and " |cffffff77[TEST]|r" or ""))
            row.kind:SetText(e.kind)
            row.activity:SetText(ForDisplay(e.activity,31))
            row.info:SetText(ForDisplay(e.channel,24).."  |  "..age.."m  |  "..(e.roles~="" and e.roles or "Roles unspecified")..(e.repeats>1 and "  x"..e.repeats or ""))
            row.message:SetText(ForDisplay(e.text,115))
            row.whisper:SetEnabled(not e.synthetic)
            row.invite:SetEnabled(not e.synthetic and e.kind=="LFG")
            row.whisper:SetText(e.whisper and "W sent" or "Whisper to Join")
            local inviteState=StatusOfInvite(e.sender)
            row.invite:SetText(inviteState=="pending" and "Inviting..."
                or inviteState=="confirmed" and "Invite Sent"
                or inviteState=="failed" and "Failed"
                or inviteState=="unconfirmed" and "Unconfirmed"
                or inviteState=="joined" and "Joined" or "Invite")
            row.whisper:GetFontString():SetTextColor(e.whisper and .30 or 1,e.whisper and 1 or .83,e.whisper and .48 or .7)
            row.invite:GetFontString():SetTextColor(inviteState=="confirmed" and .30 or 1,
                inviteState=="confirmed" and 1 or .83,inviteState=="confirmed" and .48 or .7)
        else row:Hide() end
    end
    if status and status:GetText()=="" then status:SetText("LFG Chat ready; /qjchat test inserts sample posts.") end
end


-- Right-click menu for public LFG Chat sender names, matching Group Listings.
-- Name validation prevents using chat text as slash commands or Blizzard markup.
local function ContextPlayerName(value)
    value=Readable(value)
    if type(value)~="string" or value=="" or #value>96 then return nil end
    if value:find('[|"/%c%s]') then return nil end
    return value
end

local function PrepareSenderChat(command)
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat)=="function" then
        ChatFrameUtil.OpenChat(command)
        return true
    elseif type(ChatFrame_OpenChat)=="function" then
        ChatFrame_OpenChat(command)
        return true
    end
    Print("Blizzard's chat edit box is unavailable.")
    return false
end

local function OpenSenderContextMenu(owner,entry)
    if type(entry)~="table" or entry.synthetic then return end
    local name=ContextPlayerName(entry.sender)
    if not name then
        Print("This LFG Chat post does not expose a usable player name.")
        return
    end
    if not MenuUtil or type(MenuUtil.CreateContextMenu)~="function" then
        Print("The client does not provide the player context menu API.")
        return
    end
    if GameTooltip then GameTooltip:Hide() end
    -- Rows are recycled when scrolling; capture this exact validated sender.
    MenuUtil.CreateContextMenu(owner,function(_,menu)
        menu:CreateTitle(name)
        menu:CreateButton("Prepare /who",function()
            if C_FriendList and type(C_FriendList.SetWhoToUi)=="function" then
                pcall(C_FriendList.SetWhoToUi,true)
            end
            if PrepareSenderChat('/who n-"'..name..'"') then
                Print("/who prepared for "..name..". Press Enter to submit.")
            end
        end)
        menu:CreateButton("Prepare Whisper",function()
            if PrepareSenderChat("/w "..name.." ") then
                Print("Whisper prepared for "..name..". Type a message and press Enter.")
            end
        end)
    end)
end

local function InstallSenderHitbox(row)
    -- The sender is a FontString, so put a transparent right-click button
    -- over the name only; the regular Whisper and Invite buttons are untouched.
    local hitbox=CreateFrame("Button",nil,row)
    hitbox:SetPoint("TOPLEFT",row,"TOPLEFT",8,-3)
    hitbox:SetSize(180,21)
    hitbox:RegisterForClicks("RightButtonUp")
    if type(hitbox.SetFrameLevel)=="function" and type(row.GetFrameLevel)=="function" then
        hitbox:SetFrameLevel(row:GetFrameLevel()+2)
    end
    hitbox:SetScript("OnClick",function(self,button)
        if button=="RightButton" then OpenSenderContextMenu(self,row.entry) end
    end)
    hitbox:SetScript("OnEnter",function(self)
        local e=row.entry
        if type(e)~="table" or e.synthetic or not ContextPlayerName(e.sender)
            or not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:AddLine("Right-click: /who or whisper")
        GameTooltip:AddLine("Actions only prepare chat; press Enter to send.",.8,.8,.8)
        GameTooltip:Show()
    end)
    hitbox:SetScript("OnLeave",function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.senderHitbox=hitbox
end

local function InstallChatPanel(window)
    if chatPanel then return end
    chatPanel = CreateFrame("Frame", nil, window)
    chatPanel:SetPoint("TOPLEFT",window,"TOPLEFT",26,-239)
    chatPanel:SetSize(786,538)
    chatPanel:SetFrameLevel(findContent:GetFrameLevel()+12)
    chatPanel:EnableMouse(true)
    Label(chatPanel,"LFG CHAT — recruitment posts seen by your character",0,1,620,20,"GameFontNormal")
    pageInfo=Label(chatPanel,"",0,24,750,20)
    instructions=Label(chatPanel,"",0,46,760,34)
    instructions:SetWordWrap(true)
    viewport=CreateFrame("ScrollFrame",nil,chatPanel)
    viewport:SetPoint("TOPLEFT",chatPanel,"TOPLEFT",0,-91)
    viewport:SetSize(760,400)
    canvas=CreateFrame("Frame",nil,viewport)
    canvas:SetSize(760,400)
    viewport:SetScrollChild(canvas)
    chatPanel.scrollOffset=0
    viewport:SetScript("OnMouseWheel",function(_,delta)
        local n = #VisibleEntries()
        chatPanel.scrollOffset=math.max(0,math.min(math.max(0,n-ROW_COUNT),chatPanel.scrollOffset-delta))
        Refresh()
    end)
    viewport:EnableMouseWheel(true)
    for i=1,ROW_COUNT do
        local row=CreateFrame("Frame",nil,canvas,"BackdropTemplate")
        row:SetPoint("TOPLEFT",canvas,"TOPLEFT",0,-(i-1)*66)
        row:SetSize(745,64)
        row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        row:SetBackdropColor(.09,.11,.16,1)
        row.name=Label(row,"",8,4,179,19,"GameFontHighlight")
        InstallSenderHitbox(row)
        row.kind=Label(row,"",195,4,36,19,"GameFontNormal")
        row.activity=Label(row,"",239,4,275,19)
        row.info=Label(row,"",8,24,505,16)
        row.message=Label(row,"",8,43,515,17)
        row.whisper=Button(row,"Whisper to Join",532,7,103,24,function(self)
            if row.entry then AttemptWhisper(row.entry) end
        end)
        row.invite=Button(row,"Invite",641,7,95,24,function(self)
            if row.entry then AttemptInvite(row.entry.sender,row.entry) end
        end)
        chatRows[i]=row
    end
    local newer=Button(chatPanel,"Newer",0,493,91,23,function()
        chatPanel.scrollOffset=math.max(0,(chatPanel.scrollOffset or 0)-ROW_COUNT); Refresh()
    end)
    local older=Button(chatPanel,"Older",98,493,91,23,function()
        chatPanel.scrollOffset=math.min(math.max(0,#VisibleEntries()-ROW_COUNT),(chatPanel.scrollOffset or 0)+ROW_COUNT); Refresh()
    end)
    Button(chatPanel,"All",350,493,66,23,function() currentFilter="all";chatPanel.scrollOffset=0;Refresh() end)
    Button(chatPanel,"LFM",422,493,66,23,function() currentFilter="LFM";chatPanel.scrollOffset=0;Refresh() end)
    Button(chatPanel,"LFG",494,493,66,23,function() currentFilter="LFG";chatPanel.scrollOffset=0;Refresh() end)
    Button(chatPanel,"Diagnostics",591,493,147,23,function() SlashCmdList["QJCHAT"]("diag") end)
    status=Label(chatPanel,"LFG Chat listening for public messages...",0,521,755,18)
    chatPanel:Hide()
    Refresh()
end

local function Install(window,drawer,rows)
    if root then return end
    root=window
    findContent=_G.ForeverQuickJoinFindContent
    if not findContent then Print("Finder frame unavailable; LFG Chat was not initialized."); return end
    -- Hide the original caption without an opaque cover (transparency preserved).
    if findContent.GetRegions then
        for _, region in ipairs({findContent:GetRegions()}) do
            if region.GetObjectType and region:GetObjectType()=="FontString"
                and region.GetText and region:GetText()=="GROUP LISTINGS" then
                oldHeading=region; oldHeading:Hide()
            end
        end
    end
    -- Nav is a sibling of the Finder, so selecting Chat can hide every original
    -- finder control (including pager and template) without hiding the nav.
    listingTab=Button(window,"Group Listings",26,205,146,24,function() SetMode("listings") end)
    chatTab=Button(window,"LFG Chat",178,205,124,24,function() SetMode("chat") end)
    listingTab:SetFrameLevel(findContent:GetFrameLevel()+8)
    chatTab:SetFrameLevel(findContent:GetFrameLevel()+8)
    InstallNativeControls()
    FixResultsLayout(window)
    InstallListingRows(rows)
    InstallChatPanel(window)
    window:HookScript("OnShow",function() if mainIsFind then SetMode(selected) end end)
    if ForeverQuickJoinHost and type(hooksecurefunc)=="function" then
        hooksecurefunc(ForeverQuickJoinHost,"OpenFind",function()
            mainIsFind=true
            listingTab:Show();chatTab:Show()
            SetMode("listings")
        end)
        hooksecurefunc(ForeverQuickJoinHost,"OpenList",function()
            mainIsFind=false
            listingTab:Hide();chatTab:Hide();chatPanel:Hide()
        end)
        hooksecurefunc(ForeverQuickJoinHost,"OpenApplications",function()
            mainIsFind=false
            listingTab:Hide();chatTab:Hide();chatPanel:Hide()
        end)
    end
    -- ApplyNew is called at the end of every base listing refresh.
    if ForeverQuickJoinTheme and type(hooksecurefunc)=="function" then
        hooksecurefunc(ForeverQuickJoinTheme,"ApplyNew",function()
            RefreshListingButtons()
            UpdateAppearance()
            if oldHeading then oldHeading:Hide() end
            if playstyleDropdown then playstyleDropdown:Hide() end
            if mainIsFind and selected=="chat" then HideOriginalResults(true) end
        end)
        ForeverQuickJoinTheme.ApplyNew()
    end
    SetMode("listings")
    Print("LFG Chat ready. Select Find Groups > LFG Chat. Diagnostics: /qjchat diag.")
end

local watcher=CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("CHAT_MSG_CHANNEL")
watcher:RegisterEvent("CHAT_MSG_SAY")
watcher:RegisterEvent("CHAT_MSG_YELL")
watcher:RegisterEvent("CHAT_MSG_SYSTEM")
watcher:RegisterEvent("UI_INFO_MESSAGE")
watcher:RegisterEvent("UI_ERROR_MESSAGE")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:SetScript("OnEvent",function(_,event,...)
    if event=="PLAYER_LOGIN" then
        if type(ForeverQuickJoinDB)~="table" then ForeverQuickJoinDB={} end
        -- Other QuickJoin modules load first; the main window is created lazily.
        if C_Timer and type(C_Timer.NewTicker)=="function" then
            C_Timer.NewTicker(30,function()
                if Prune() and Refresh then Refresh() end
            end)
        end
        if ForeverQuickJoinTheme and type(hooksecurefunc)=="function" then
            hooksecurefunc(ForeverQuickJoinTheme,"Attach",Install)
        else
            Print("LFG Chat could not initialize: QuickJoin theme hook is unavailable.")
        end
    elseif event=="PLAYER_ENTERING_WORLD" then
        if C_Timer and type(C_Timer.After)=="function" then
            C_Timer.After(3,function() TryJoinLFG(false) end)
        else
            TryJoinLFG(false)
        end
    elseif event=="PLAYER_REGEN_ENABLED" then
        if joinState=="waiting for combat end" then TryJoinLFG(false) end
    elseif event=="UI_INFO_MESSAGE" or event=="UI_ERROR_MESSAGE" then
        local id,msg=...
        HandleInviteFeedback(msg)
    elseif event=="CHAT_MSG_SYSTEM" then
        local msg=...
        HandleInviteFeedback(msg)
    elseif event=="GROUP_ROSTER_UPDATE" then
        if type(GetNumGroupMembers)=="function" and type(UnitName)=="function" then
            local n=tonumber(Readable(GetNumGroupMembers())) or 0
            local raid=type(IsInRaid)=="function" and IsInRaid()
            for i=1,math.min(n,40) do
                local token=(raid and "raid" or "party")..i
                local name=SafeString(UnitName(token))
                local rec=name and inviteRecords[NameKey(name)]
                if rec then rec.state="joined" end
            end
        end
        if Refresh then Refresh() end
        if RefreshListingButtons then RefreshListingButtons() end
    elseif event=="CHAT_MSG_CHANNEL" or event=="CHAT_MSG_SAY" or event=="CHAT_MSG_YELL" then
        local msg, sender, _, channelName, _, _, _, _, baseName = ...
        -- Do not attempt to inspect secret Forever chat values.
        if not SafeString(msg) or not SafeString(sender) then counters.secret=counters.secret+1;return end
        local channel
        if event=="CHAT_MSG_CHANNEL" then
            counters.channel=counters.channel+1
            channel=NormalizeChannel(channelName,baseName)
        elseif event=="CHAT_MSG_SAY" then
            counters.say=counters.say+1; channel="Say"
        else
            counters.yell=counters.yell+1; channel="Yell"
        end
        channels[channel]=(channels[channel] or 0)+1
        AddPost(msg,sender,channel,false)
        if Refresh then Refresh() end
    elseif event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN" then
        local blamed, action=...
        if blamed==ADDON then
            local rec=recentInviteName and inviteRecords[recentInviteName]
            local actionText=SafeString(action) or ""
            -- The same addon owns protected searches and listing management;
            -- only an invite-related error belongs to this feature.
            if rec and Now()-rec.started<5 and actionText:lower():find("invite",1,true) then
                rec.state="failed"
                ActionStatus("WoW blocked the invitation to " .. rec.target .. ".")
            end
        end
    end
end)

SLASH_QJCHAT1="/qjchat"
SlashCmdList["QJCHAT"]=function(msg)
    msg=(msg or ""):lower():match("^%s*(.-)%s*$")
    if msg=="diag" or msg=="status" or msg=="" then
        Prune()
        Print(("Diagnostics: channel=%d say=%d yell=%d accepted=%d rejected=%d secret=%d active=%d"):format(
            counters.channel,counters.say,counters.yell,counters.classified,counters.rejected,counters.secret,#data))
        for channel,n in pairs(channels) do Print("Channel "..channel..": "..n.." messages") end
        if type(GetChannelName)=="function" then
            local id=Readable(GetChannelName("LookingForGroup"))
            Print((type(id)=="number" and id>0) and ("LookingForGroup joined: channel "..id)
                or "LookingForGroup is not joined. Optional: /join LookingForGroup")
        end
        Print("Selected: "..tostring(selection.category).." / "..tostring(selection.activity)
            ..(selection.multiple and " (multi-select: category-only chat filter)" or ""))
        Print("Auto-join: "..joinState.." (tries="..joinAttempts..")  Inbox: "..inboxSortReason)
        Print("Test classifier/UI using /qjchat test. Public channel posts cannot be read retroactively.")
    elseif msg=="test" then
        AddPost("LFM SM Cath need healer and 1 DPS", "QuickJoinTestA", "TEST (local)",true)
        AddPost("32 Warlock LFG Scarlet Monastery", "QuickJoinTestB", "TEST (local)",true)
        AddPost("SM cath need tank", "QuickJoinTestC", "TEST (local)",true)
        Print("Inserted three local examples. Select Find Groups > LFG Chat. Sample-player action buttons are disabled.")
    elseif msg=="join" then
        joinAttempts=0
        TryJoinLFG(true)
        Print("Join status: "..joinState)
    elseif msg=="autojoin on" or msg=="autojoin off" then
        ForeverQuickJoinDB=ForeverQuickJoinDB or {}
        ForeverQuickJoinDB.chatAutoJoin=msg=="autojoin on"
        Print("Auto-join LookingForGroup "..(ForeverQuickJoinDB.chatAutoJoin and "enabled" or "disabled"))
        if ForeverQuickJoinDB.chatAutoJoin then TryJoinLFG(false) end
    elseif msg=="clear" then
        data={};byKey={}; if chatPanel then chatPanel.scrollOffset=0 end
        if Refresh then Refresh() end
        Print("Session chat board cleared.")
    else
        Print("Commands: /qjchat diag, test, clear, join, autojoin on/off")
    end
end
