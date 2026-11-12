-- Forever QuickJoin 0.7.3 - Find/List/Applications navigation and always-on applicant capture.
-- Whisper history is session-only; no private message contents go to SavedVariables.
local addonName = ...
local Host = {}
ForeverQuickJoinHost = Host

local ROLE_ORDER = { TANK=1, HEALER=2, DAMAGER=3, UNKNOWN=4 }
local ROLE_NAMES = { TANK="Tank", HEALER="Healer", DAMAGER="DPS", UNKNOWN="Unknown" }
local ROLE_ICONS = {
    TANK="|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:17:17:0:-1:64:64:0:19:22:41|t",
    HEALER="|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:17:17:0:-1:64:64:20:39:1:20|t",
    DAMAGER="|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:17:17:0:-1:64:64:20:39:22:41|t",
    UNKNOWN="|TInterface\\Icons\\INV_Misc_QuestionMark:16:16|t",
}
local MAX_APPLICANTS, MAX_MESSAGES, ROWS_PER_PAGE = 100, 35, 10
local DENIAL = "Sorry, we can't take you for this group. Good luck!"
local applicants, byName, selected = {}, {}, nil
local inboxPage, missedProtected = 1, 0
local panel, window, findTab, hostTab, applicationsTab, listingButton
local listingStatusLabel, statusLabel, inboxLabel, profileLabel, detailLabel, chatLog
local queueRows, roleButtons = {}, {}
local replyInput, replyButton, inviteButton, declineButton, dismissButton, whoButton
local prevPage, nextPage, pageLabel
local chatAttempt, chatBlocked = false, false
local lookingUp = nil

local function Readable(value)
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then return nil end
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end
local function Text(value)
    value = Readable(value)
    return type(value) == "string" and value ~= "" and value or nil
end
local function Status(value)
    if statusLabel then statusLabel:SetText(value or "") end
end
local function Label(parent, value, x, y, w, h, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    label:SetSize(w, h)
    label:SetJustifyH("LEFT")
    label:SetText(value or "")
    return label
end
local function Button(parent, label, x, y, w, h, handler)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    button:SetSize(w, h)
    button:SetText(label)
    button:SetScript("OnClick", handler)
    return button
end
local function Sanitized(value)
    -- FontString/ScrollingMessageFrame accepts Blizzard markup. Never interpret
    -- user-provided whisper text as embedded textures or links.
    return tostring(value or ""):gsub("|", "||")
end
local function TimeNow()
    return type(GetTime) == "function" and GetTime() or 0
end
local function SameName(a,b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    a,b = a:lower(), b:lower()
    if a == b then return true end
    -- Only strip a realm when the *other* name does not specify one.
    if not a:find("-",1,true) then return a == b:match("^[^-]+") end
    if not b:find("-",1,true) then return b == a:match("^[^-]+") end
    return false
end
local function ClassifiedRole(message)
    local lower = message:lower()
    -- Recruitment ads and requests for roles describe OTHER players.
    if lower:find("lfm",1,true) or lower:find("need%s+")
        or lower:find("looking%s+for%s+tank") or lower:find("looking%s+for%s+heal")
        or lower:find("looking%s+for%s+a%s+tank") or lower:find("looking%s+for%s+a%s+heal") then return nil end
    local padded = " " .. lower:gsub("[^%a]", " ") .. " "
    local intent = padded:find(" lfg ",1,true) or padded:find(" inv ",1,true)
        or padded:find(" invite ",1,true) or padded:find(" here ",1,true)
        or padded:find(" can ",1,true) or padded:find(" i am ",1,true)
        or padded:find(" im ",1,true) or padded:find(" i m ",1,true)
        or padded:find(" role ",1,true)
    if not intent then return nil end
    local tank = padded:find(" tank ",1,true) or padded:find(" tanking ",1,true)
    local healer = padded:find(" healer ",1,true) or padded:find(" heals ",1,true)
        or padded:find(" healing ",1,true) or padded:find(" heal ",1,true)
    local dps = padded:find(" dps ",1,true) or padded:find(" damage ",1,true)
    local n = (tank and 1 or 0) + (healer and 1 or 0) + (dps and 1 or 0)
    if n ~= 1 then return nil end
    if tank then return "TANK" end
    if healer then return "HEALER" end
    return "DAMAGER"
end
local function UserColor()
    local color = ChatTypeInfo and ChatTypeInfo.WHISPER
    if type(color) == "table" and type(color.r) == "number"
        and type(color.g) == "number" and type(color.b) == "number" then
        return color.r, color.g, color.b
    end
    return 1, .5, 1
end
local function AddLine(entry, direction, message)
    entry.messages[#entry.messages+1] = {direction=direction, text=message, timestamp=TimeNow()}
    while #entry.messages > MAX_MESSAGES do table.remove(entry.messages, 1) end
    entry.updatedAt = TimeNow()
    if direction == "in" and selected ~= entry then entry.unread = entry.unread + 1 end
end
local function PlayerInfo(entry, guid)
    if not guid or type(GetPlayerInfoByGUID) ~= "function" then return end
    local ok, localClass, classToken, _, _, _, _, _, level = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return end
    entry.class = Text(classToken) or entry.class
    entry.localizedClass = Text(localClass) or entry.localizedClass
    level = Readable(level)
    if type(level) == "number" and level > 0 then entry.level = level end
end
local function Drop(entry)
    if not entry then return end
    byName[entry.key] = nil
    for i, member in ipairs(applicants) do
        if member == entry then table.remove(applicants, i); break end
    end
    if selected == entry then selected = nil end
end
local function RecordIncoming(message, name, guid)
    -- Applicant capture is always enabled while QuickJoin is loaded.
    -- Whisper content remains session-only and is never persisted.
    -- Forever can mark the sender and whisper text as secret during restricted
    -- client states. A secret name cannot be used as a table key or compared.
    name, message = Text(name), Text(message)
    if not name or not message then
        missedProtected = missedProtected + 1
        if Host.Redraw then Host.Redraw() end
        return
    end
    local key = name:lower()
    local entry = byName[key]
    if not entry then
        if #applicants >= MAX_APPLICANTS then
            local oldest = applicants[1]
            for _, candidate in ipairs(applicants) do
                if candidate.updatedAt < oldest.updatedAt then oldest = candidate end
            end
            Drop(oldest)
        end
        entry = {key=key, name=name, role="UNKNOWN", roleSource="unknown", messages={}, unread=0,
            updatedAt=TimeNow(), class=nil, level=nil, zone=nil, spec=nil}
        applicants[#applicants+1] = entry
        byName[key] = entry
    end
    -- Role classification is intentionally conservative and self-reported.
    -- Unknown roles must remain unknown; never equate class with role.
    if entry.roleSource ~= "manual" then
        local recognized = ClassifiedRole(message)
        if recognized then
            entry.role, entry.roleSource = recognized, "message"
        end
    end
    PlayerInfo(entry, Readable(guid))
    AddLine(entry, "in", message)
    if Host.Redraw then Host.Redraw() end
end
local function RecordOutgoing(message, name)
    message, name = Text(message), Text(name)
    if not name or not message then return end
    local entry = byName[name:lower()]
    if entry then
        AddLine(entry, "out", message)
        if Host.Redraw then Host.Redraw() end
    end
end
local function Sorted()
    local out = {}
    for _,entry in ipairs(applicants) do out[#out+1] = entry end
    table.sort(out, function(a,b)
        local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
        if ra ~= rb then return ra < rb end
        if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
        return a.name < b.name
    end)
    return out
end
local function DrawChat()
    if not chatLog then return end
    chatLog:Clear()
    if not selected then
        chatLog:AddMessage("Choose an applicant on the left to see their whispers.", .7, .7, .7)
        return
    end
    for _, item in ipairs(selected.messages) do
        local r,g,b = UserColor()
        local prefix = item.direction == "in" and "Them: " or "You: "
        if item.direction == "out" then r,g,b = .72,.87,1 end
        chatLog:AddMessage(prefix .. Sanitized(item.text),r,g,b)
    end
    if chatLog.ScrollToBottom then chatLog:ScrollToBottom() end
end
local function DrawInfo()
    local e = selected
    if not profileLabel then return end
    if not e then
        profileLabel:SetText("No applicant selected")
        detailLabel:SetText("Class, level and role are populated when available.\nLocation requires a manual /who; spec is not exposed by whisper events.")
    else
        profileLabel:SetText((ROLE_ICONS[e.role] or ROLE_ICONS.UNKNOWN).." "..e.name)
        local class = e.localizedClass or e.class or "Unknown class"
        local lvl = e.level and ("Level "..e.level) or "Level unknown"
        local roleText = ROLE_NAMES[e.role] or "Unknown"
        local source = e.roleSource == "manual" and "manual" or (e.roleSource == "message" and "self-reported" or "unverified")
        detailLabel:SetText(("%s  |  %s  |  %s (%s)\nLocation: %s  |  Spec: unknown"):format(
            lvl, class, roleText, source, e.zone or "unknown - use Lookup /who"))
    end
    for role,button in pairs(roleButtons) do
        button:SetEnabled(e ~= nil)
        if e and e.role == role then
            local label = button:GetFontString()
            if label then label:SetTextColor(1, .86, .30) end
        else
            local label = button:GetFontString()
            if label then label:SetTextColor(1, 1, 1) end
        end
    end
    for _,button in ipairs({replyButton,inviteButton,declineButton,dismissButton,whoButton}) do
        if button then button:SetEnabled(e ~= nil) end
    end
    DrawChat()
end
local function DrawQueue()
    if not inboxLabel then return end
    local sorted = Sorted()
    local counts = {TANK=0, HEALER=0, DAMAGER=0, UNKNOWN=0}
    for _, e in ipairs(sorted) do counts[e.role] = (counts[e.role] or 0) + 1 end
    inboxLabel:SetText(("APPLICANTS (%d)     %s%d  %s%d  %s%d  ?%d"):format(#sorted,
        ROLE_ICONS.TANK,counts.TANK,ROLE_ICONS.HEALER,counts.HEALER,
        ROLE_ICONS.DAMAGER,counts.DAMAGER,counts.UNKNOWN))
    local totalPages = math.max(1, math.ceil(#sorted / ROWS_PER_PAGE))
    inboxPage = math.max(1, math.min(inboxPage,totalPages))
    pageLabel:SetText(("%d / %d"):format(inboxPage,totalPages))
    prevPage:SetEnabled(inboxPage > 1)
    nextPage:SetEnabled(inboxPage < totalPages)
    for i,row in ipairs(queueRows) do
        local e = sorted[(inboxPage-1)*ROWS_PER_PAGE+i]
        row.entry = e
        if not e then
            row:Hide()
        else
            row:Show()
            row.text:SetText((ROLE_ICONS[e.role] or ROLE_ICONS.UNKNOWN) .. " "
                .. Sanitized(e.name) .. (e.unread>0 and ("  |cffffd100+"..e.unread.."|r") or ""))
            row:SetBackdropColor(e==selected and .18 or .10, e==selected and .22 or .12,
                e==selected and .33 or .16, 1)
            if e.class and type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[e.class] then
                row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                local c=CLASS_ICON_TCOORDS[e.class]
                row.classIcon:SetTexCoord(c[1],c[2],c[3],c[4])
            else
                row.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                row.classIcon:SetTexCoord(0,1,0,1)
            end
        end
    end
    if selected and byName[selected.key] ~= selected then selected=nil end
end
function Host.Redraw()
    if not panel then return end
    DrawQueue()
    DrawInfo()
end
local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown()
end
local function SendReply(name, message)
    if not Text(name) or not Text(message) then return false end
    if #message > 255 then Status("Message exceeds WoW's 255-byte whisper limit."); return false end
    if ChatLocked() then Status("Whisper locked by the client. No message sent."); return false end
    local sender = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(sender) ~= "function" then Status("Whisper API unavailable."); return false end
    chatAttempt, chatBlocked = true, false
    sender(message, "WHISPER", nil, name) -- direct click, no pcall or timer
    chatAttempt = false
    if chatBlocked then Status("WoW blocked the whisper. Applicant remains queued."); return false end
    return true -- API accepted a send attempt; actual delivery is unconfirmed
end
local function TryWho()
    if not selected then return end
    local name = selected.name
    if not Text(name) then return end
    if not (ChatFrameUtil and ChatFrameUtil.OpenChat) and type(ChatFrame_OpenChat) ~= "function" then
        Status("Chat command entry unavailable. Use Blizzard's Who window manually.")
        return
    end
    -- A direct C_FriendList.SendWho() call is protected in Forever even from
    -- an addon button. We only prepare the command; player presses Enter.
    local command = '/who "' .. name:gsub('"', '') .. '"'
    lookingUp = name
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(command)
    else
        ChatFrame_OpenChat(command)
    end
    Status("/who prepared; press Enter in chat. Location appears if WoW returns it.")
end
local function MergeWhoResults()
    if not C_FriendList or type(C_FriendList.GetNumWhoResults)~="function"
        or type(C_FriendList.GetWhoInfo)~="function" then return end
    local ok, count = pcall(C_FriendList.GetNumWhoResults)
    if not ok or type(count)~="number" then return end
    for i=1,math.min(50,count) do
        local infoOK, info = pcall(C_FriendList.GetWhoInfo, i)
        if infoOK and type(Readable(info)) == "table" then
            local name = Text(info.fullName)
            if name then
                for _, e in ipairs(applicants) do
                    if SameName(e.name,name) then
                        local class = Text(info.filename)
                        local level = Readable(info.level)
                        e.zone = Text(info.area) or e.zone
                        e.class = class or e.class
                        e.localizedClass = Text(info.classStr) or e.localizedClass
                        if type(level)=="number" and level>0 then e.level=level end
                    end
                end
            end
        end
    end
    lookingUp = nil
    Host.Redraw()
end
local function CurrentEntry()
    if not C_LFGList or type(C_LFGList.GetActiveEntryInfo)~="function" then return nil end
    local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
    return ok and type(Readable(entry))=="table" and entry or nil
end
local function UpdateListingUI()
    if not listingStatusLabel then return end
    local entry = CurrentEntry()
    if not entry then
        listingStatusLabel:SetText("No active listing")
        return
    end
    local name = "active group"
    local ids = Readable(entry.activityIDs)
    local id = type(ids)=="table" and Readable(ids[1]) or nil
    if type(id)=="number" and C_LFGList
        and type(C_LFGList.GetActivityInfoTable)=="function" then
        local ok, info = pcall(C_LFGList.GetActivityInfoTable,id)
        if ok and type(Readable(info))=="table" then
            name = Text(info.shortName) or Text(info.fullName)
                or Text(info.name) or name
        end
    end
    listingStatusLabel:SetText("Active: "..name)
end
-- Forever's listing APIs are restricted. Our custom CreateListing/UpdateListing
-- button was blocked even after user interaction (ADDON_ACTION_BLOCKED), so
-- do NOT invoke them here or call Blizzard's protected buttons via :Click().
-- Instead, let Blizzard's own secure Listing tab execute those operations.
local function OpenNativeListing()
    if type(InCombatLockdown)=="function" and InCombatLockdown() then
        Status("Blizzard's Listing tab cannot open during combat.")
        return
    end
    if type(LFGVanilla_ToggleFrame)~="function" then
        if type(GroupFinderVanillaStyle_LoadUI)=="function" then
            GroupFinderVanillaStyle_LoadUI()
        end
    end
    if type(LFGVanilla_ToggleFrame)~="function" then
        Status("Blizzard Listing UI unavailable. Open the normal Group Finder instead.")
        return
    end
    -- Native tab 1 = Listing; tab 2 = Browse; tab 3 = Who.
    -- This matches the handoff used by LFG Forever's window.lua.
    LFGVanilla_ToggleFrame(1)
    if window and type(window.Hide)=="function" then window:Hide() end
end
local function ClearSelected()
    if not selected then return end
    Drop(selected)
    Host.Redraw()
end
local function ReplySelected()
    if not selected or not replyInput then return end
    local msg = replyInput:GetText()
    if not Text(msg) then Status("Type a message first."); return end
    if SendReply(selected.name,msg) then
        replyInput:SetText("")
        Status("Reply sent to chat API; delivery not confirmed.")
    end
end
local function InviteSelected()
    if not selected then return end
    local name = selected.name
    local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    if type(invite)~="function" then Status("Party invite API unavailable.");return end
    if type(IsInGroup)=="function" and IsInGroup() and type(UnitIsGroupLeader)=="function"
        and not UnitIsGroupLeader("player") then
        Status("You must be the party leader to invite. Applicant kept in queue.")
        return
    end
    invite(name) -- direct physical click; may open a Blizzard confirmation dialog
    Status("Invite attempted for "..name..". Applicant remains until they join or you dismiss.")
end
local function DeclineSelected()
    if not selected then return end
    local name=selected.name
    if SendReply(name,DENIAL) then
        Drop(selected)
        Host.Redraw()
        Status("Decline message submitted for "..name.."; removed from queue (delivery unconfirmed).")
    end
end
local function GroupMemberJoined()
    local raid = type(IsInRaid)=="function" and IsInRaid()
    local n = type(GetNumGroupMembers)=="function" and GetNumGroupMembers() or 0
    if type(n)~="number" then return end
    for i=1,math.min(raid and n or n-1,40) do
        local token = (raid and "raid" or "party")..i
        local name = type(UnitName)=="function" and Readable(UnitName(token))
        local selfUnit = type(UnitIsUnit)=="function" and Readable(UnitIsUnit(token,"player"))
        if Text(name) and selfUnit~=true then
            local e=byName[name:lower()]
            if e then Drop(e) end
        end
    end
    Host.Redraw()
end
function Host.Attach(parent)
    if panel then return end
    window = parent
    -- Compact three-tab navigation fits beside the theme selector.
    findTab = Button(window,"Find Groups",475,16,102,25,function() Host.OpenFind() end)
    hostTab = Button(window,"List Group",580,16,96,25,function() Host.OpenList() end)
    applicationsTab = Button(window,"Applications",679,16,119,25,function()
        Host.OpenApplications()
    end)
    findTab:Disable()
    panel = CreateFrame("Frame","ForeverQuickJoinHostingPanel",window,"BackdropTemplate")
    panel:SetPoint("TOPLEFT",window,"TOPLEFT",12,-51)
    panel:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-12,12)
    if type(window.GetFrameLevel)=="function" then panel:SetFrameLevel(window:GetFrameLevel()+10) end
    panel:EnableMouse(true)
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,
        edgeSize=20,insets={left=0,right=0,top=0,bottom=0}})
    panel:SetBackdropColor(.035,.045,.065,1)
    Label(panel,"LIST GROUP & APPLICANT INBOX",17,10,400,26,"GameFontNormalLarge")
    -- Creation, editing and removal happen in Blizzard's own secure Listing tab.
    -- QuickJoin keeps its full applicant inbox and handles whispers/invites.
    -- Put the listing handoff in the title row instead of directly above the
    -- party summary. This gives the summary a visible gap without moving the
    -- inbox or clipping it on short screens.
    listingButton=Button(panel,"Open Blizzard Listing",580,10,211,27,OpenNativeListing)
    listingStatusLabel=Label(panel,"No active listing",371,14,202,24,"GameFontHighlightSmall")
    statusLabel=Label(panel,"Create, edit or delist in Blizzard; manage whispers and applicants here.",17,155,780,24)
    inboxLabel=Label(panel,"APPLICANTS (0)",17,201,770,24,"GameFontNormal")
    -- Opaque, visible left queue / right one-applicant conversation.
    local left=CreateFrame("Frame",nil,panel,"BackdropTemplate")
    left:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-231)
    left:SetSize(306,445)
    left:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    left:SetBackdropColor(.075,.09,.12,1)
    local right=CreateFrame("Frame",nil,panel,"BackdropTemplate")
    right:SetPoint("TOPLEFT",panel,"TOPLEFT",330,-231)
    right:SetSize(465,445)
    right:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    right:SetBackdropColor(.075,.09,.12,1)
    for i=1,ROWS_PER_PAGE do
        local row=CreateFrame("Button",nil,left,"BackdropTemplate")
        row:SetPoint("TOPLEFT",left,"TOPLEFT",7,-(8+(i-1)*40))
        row:SetSize(291,36)
        row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        row:SetBackdropColor(.10,.12,.16,1)
        row.classIcon=row:CreateTexture(nil,"ARTWORK")
        row.classIcon:SetSize(19,19)
        row.classIcon:SetPoint("LEFT",row,"LEFT",4,0)
        row.text=Label(row,"",29,5,256,26,"GameFontHighlightSmall")
        row:SetScript("OnClick",function(self)
            selected=self.entry
            if selected then selected.unread=0 end
            Host.Redraw()
        end)
        row:SetScript("OnEnter",function(self)
            if self.entry and GameTooltip then
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:AddLine(self.entry.name,1,.82,0)
                GameTooltip:AddLine((ROLE_NAMES[self.entry.role] or "Unknown") .. " role ("..self.entry.roleSource..")")
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        queueRows[i]=row
    end
    prevPage=Button(left,"<",9,419,50,24,function() inboxPage=inboxPage-1;Host.Redraw() end)
    pageLabel=Label(left,"1 / 1",113,421,100,24)
    nextPage=Button(left,">",241,419,50,24,function() inboxPage=inboxPage+1;Host.Redraw() end)
    profileLabel=Label(right,"No applicant selected",12,8,437,25,"GameFontNormal")
    detailLabel=Label(right,"",12,34,440,49,"GameFontHighlightSmall")
    Label(right,"Assign role:",12,91,85,20,"GameFontNormalSmall")
    for i,item in ipairs({{"TANK","Tank"},{"HEALER","Heal"},{"DAMAGER","DPS"},{"UNKNOWN","?"}}) do
        local role,name=item[1],item[2]
        roleButtons[role]=Button(right,(ROLE_ICONS[role] or "").." "..name,92+(i-1)*89,87,86,26,function()
            if selected then
                selected.role,selected.roleSource=role,"manual"
                Host.Redraw()
            end
        end)
    end
    Label(right,"WHISPER CONVERSATION (selected player only)",12,121,435,20,"GameFontNormalSmall")
    chatLog=CreateFrame("ScrollingMessageFrame",nil,right)
    chatLog:SetPoint("TOPLEFT",right,"TOPLEFT",12,-147)
    chatLog:SetSize(440,203)
    chatLog:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    chatLog:SetMaxLines(100)
    chatLog:SetFading(false)
    chatLog:EnableMouseWheel(true)
    chatLog:SetScript("OnMouseWheel",function(self,delta)
        if delta>0 then self:ScrollUp() else self:ScrollDown() end
    end)
    replyInput=CreateFrame("EditBox",nil,right,"InputBoxTemplate")
    replyInput:SetPoint("TOPLEFT",right,"TOPLEFT",13,-361)
    replyInput:SetSize(340,25)
    replyInput:SetAutoFocus(false)
    replyInput:SetMaxLetters(250)
    replyInput:SetScript("OnEnterPressed",function(self) ReplySelected();self:ClearFocus() end)
    replyInput:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    replyButton=Button(right,"Reply",359,361,92,25,ReplySelected)
    inviteButton=Button(right,"Invite",13,405,92,26,InviteSelected)
    declineButton=Button(right,"Decline + Remove",113,405,131,26,DeclineSelected)
    dismissButton=Button(right,"Dismiss",251,405,90,26,ClearSelected)
    whoButton=Button(right,"Lookup /who",348,405,104,26,TryWho)
    Label(panel,"Roles from whisper text are self-reported. Confirm unknown roles manually; /who is user-initiated.",17,691,788,20)
    panel:Hide()
    UpdateListingUI()
    Host.Redraw()
end
function Host.SetApplicationCount(total,unread)
    if not applicationsTab then return end
    local count=type(unread)=="number" and unread or 0
    applicationsTab:SetText(count>0 and ("Apps ("..count..")") or "Applications")
end
function Host.OpenList()
    if not window then return end
    window:Show()
    if window.QuickJoinHideAdvanced then window.QuickJoinHideAdvanced() end
    if ForeverQuickJoinApplications then ForeverQuickJoinApplications.Hide() end
    if window.QuickJoinSetFinderVisible then window.QuickJoinSetFinderVisible(false) end
    if ForeverQuickJoinParty and ForeverQuickJoinParty.SetSummaryVisible then
        ForeverQuickJoinParty.SetSummaryVisible(true)
    end
    panel:Show()
    findTab:Enable();hostTab:Disable();applicationsTab:Enable()
    UpdateListingUI()
    Host.Redraw()
end
function Host.OpenFind()
    if not window then return end
    window:Show()
    panel:Hide()
    if ForeverQuickJoinApplications then ForeverQuickJoinApplications.Hide() end
    if window.QuickJoinSetFinderVisible then window.QuickJoinSetFinderVisible(true) end
    if ForeverQuickJoinParty and ForeverQuickJoinParty.SetSummaryVisible then
        ForeverQuickJoinParty.SetSummaryVisible(true)
    end
    findTab:Disable();hostTab:Enable();applicationsTab:Enable()
end
function Host.OpenApplications()
    if not window then return end
    window:Show()
    if window.QuickJoinHideAdvanced then window.QuickJoinHideAdvanced() end
    panel:Hide()
    if window.QuickJoinSetFinderVisible then window.QuickJoinSetFinderVisible(false) end
    if ForeverQuickJoinParty and ForeverQuickJoinParty.SetSummaryVisible then
        ForeverQuickJoinParty.SetSummaryVisible(false)
    end
    if ForeverQuickJoinApplications then ForeverQuickJoinApplications.Open() end
    findTab:Enable();hostTab:Enable();applicationsTab:Disable()
end
local watcher=CreateFrame("Frame")
for _,event in ipairs({"CHAT_MSG_WHISPER","CHAT_MSG_WHISPER_INFORM","WHO_LIST_UPDATE",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE","LFG_LIST_AVAILABILITY_UPDATE",
    "GROUP_ROSTER_UPDATE","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN"}) do
    watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent",function(_,event,...)
    if event=="CHAT_MSG_WHISPER" then
        local message, name, _,_,_,_,_,_,_,_,_, guid = ...
        RecordIncoming(message,name,guid)
    elseif event=="CHAT_MSG_WHISPER_INFORM" then
        local message, name = ...
        RecordOutgoing(message,name)
    elseif event=="WHO_LIST_UPDATE" then
        MergeWhoResults()
    elseif event=="LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        if panel then UpdateListingUI() end
    elseif event=="LFG_LIST_AVAILABILITY_UPDATE" then
        if panel and panel:IsShown() then UpdateListingUI() end
    elseif event=="GROUP_ROSTER_UPDATE" then
        GroupMemberJoined()
    elseif (event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN") then
        local blockedAddon, detail = ...
        if blockedAddon ~= addonName then return end
        if chatAttempt then
            chatBlocked=true
            Status("WoW blocked the whisper; applicant remains in queue.")
        end
    end
end)
