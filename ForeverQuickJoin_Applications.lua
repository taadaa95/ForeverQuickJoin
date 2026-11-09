-- Forever QuickJoin v0.7.3: session-only contacted groups and leader replies.
-- All queries/searches remain explicitly user initiated. No whispers are saved.
local Apps = {}
ForeverQuickJoinApplications = Apps

local MAX_ENTRIES, MAX_MESSAGES, PAGE_SIZE = 100, 40, 8
local entries, byRecord = {}, setmetatable({}, {__mode="k"})
local selected, currentPage, nextSerial = nil, 1, 0
local window, panel, listTitle, detailsTitle, detailsInfo, conversation, pageLabel
local listRows, previousButton, nextButton, replyButton = {}, nil, nil, nil

local function Readable(value)
    if type(canaccessvalue)=="function" and not canaccessvalue(value) then return nil end
    if type(issecretvalue)=="function" and issecretvalue(value) then return nil end
    return value
end
local function Plain(value)
    value=Readable(value)
    return type(value)=="string" and value~="" and value or nil
end
local function NameKey(value)
    value=Plain(value)
    return value and value:lower():gsub("^%s+",""):gsub("%s+$","") or nil
end
local function Display(value)
    value=Plain(value) or ""
    -- Do not execute user-provided WoW color links or texture escapes.
    return value:gsub("|","||")
end
local function Clock()
    return type(GetTime)=="function" and GetTime() or 0
end
local function Age(seconds)
    if type(seconds)~="number" or seconds<0 then return "unknown" end
    seconds=math.floor(seconds)
    if seconds<60 then return seconds.."s" end
    if seconds<3600 then return math.floor(seconds/60).."m" end
    if seconds<86400 then return math.floor(seconds/3600).."h" end
    return math.floor(seconds/86400).."d"
end
local function Button(parent,label,x,y,w,h,callback)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    b:SetSize(w,h)
    b:SetText(label)
    b:SetScript("OnClick",callback)
    return b
end
local function Label(parent,value,x,y,w,h,font)
    local f=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    f:SetSize(w,h)
    f:SetJustifyH("LEFT")
    f:SetJustifyV("TOP")
    f:SetText(value or "")
    return f
end
local function CountUnread()
    local unread=0
    for _,entry in ipairs(entries) do unread=unread+(entry.unread or 0) end
    return unread
end
local function UpdateTab()
    if ForeverQuickJoinHost and ForeverQuickJoinHost.SetApplicationCount then
        ForeverQuickJoinHost.SetApplicationCount(#entries,CountUnread())
    end
end
local function AddMessage(entry,direction,message)
    entry.messages[#entry.messages+1]={direction=direction,message=message,at=Clock()}
    if #entry.messages>MAX_MESSAGES then table.remove(entry.messages,1) end
end
local function Refresh()
    UpdateTab()
    if not panel or not panel:IsShown() then return end
    listTitle:SetText(("CONTACTED GROUPS (%d) · Unread replies: %d"):format(#entries,CountUnread()))
    local totalPages=math.max(1,math.ceil(#entries/PAGE_SIZE))
    currentPage=math.max(1,math.min(currentPage,totalPages))
    pageLabel:SetText(("%d / %d"):format(currentPage,totalPages))
    previousButton:SetEnabled(currentPage>1)
    nextButton:SetEnabled(currentPage<totalPages)
    for i,row in ipairs(listRows) do
        local entry=entries[(currentPage-1)*PAGE_SIZE+i]
        row.entry=entry
        if not entry then
            row:Hide()
        else
            row:Show()
            local status=entry.ended and "Listing ended" or (entry.replies>0 and "Replied" or "Sent")
            local name=entry.title~="" and entry.title or entry.activity
            row.title:SetText(Display(name):sub(1,50))
            row.info:SetText(Display(entry.leader):sub(1,24).."  ·  "..
                (entry.unread>0 and ("|cffffd45f"..entry.unread.." new|r") or
                    (entry.ended and "|cffaaaaaaEnded|r" or
                    (entry.replies>0 and "|cff69e3a2Replied|r" or "|cff69e3a2Sent|r"))))
            row:SetBackdropColor(selected==entry and .16 or .085,
                selected==entry and .21 or .105,selected==entry and .28 or .14,1)
        end
    end
    if not selected then
        detailsTitle:SetText("Select a contacted group")
        detailsInfo:SetText("Replies are attached only to a matching group leader.")
        replyButton:Disable()
        conversation:Clear()
        return
    end
    detailsTitle:SetText(Display(selected.title~="" and selected.title or selected.activity))
    local status=selected.ended and "Listing ended" or
        (selected.replies>0 and "Replied" or "Sent (delivery unconfirmed)")
    detailsInfo:SetText(Display(selected.leader).." · "..status..
        " · "..selected.sentCount.." whisper"..(selected.sentCount==1 and "" or "s"))
    replyButton:Enable()
    conversation:Clear()
    for _,message in ipairs(selected.messages) do
        local direction=message.direction=="in" and "|cff8be7a9Leader|r" or "|cff9fc7ffYou|r"
        conversation:AddMessage(direction..": "..Display(message.message),.91,.93,.96)
    end
    if conversation.ScrollToBottom then conversation:ScrollToBottom() end
end

local function UpdateFinderBadge()
    if window and window:IsShown() and window.QuickJoinUpdateSent then
        window.QuickJoinUpdateSent()
    end
end

local function PruneOldest()
    while #entries>MAX_ENTRIES do
        local removed=table.remove(entries)
        if selected==removed then selected=nil end
        if removed.record then byRecord[removed.record]=nil end
    end
end

-- Called only after QuickJoin successfully submitted a click-initiated whisper.
function Apps.TrackSent(record,info,message)
    if type(record)~="table" or type(info)~="table" then return end
    local leader=Plain(record.leader)
    local outgoing=Plain(message)
    if not leader or not outgoing then return end
    local entry=byRecord[record]
    if not entry then
        nextSerial=nextSerial+1
        entry={serial=nextSerial,record=record,leader=leader,
            nameKey=NameKey(leader),activity="",title="",sentCount=0,
            replies=0,unread=0,messages={},sentAt=Clock(),ended=false}
        byRecord[record]=entry
        table.insert(entries,1,entry)
    else
        entry.ended=false
    end
    local title=Plain(info.name)
    entry.title=title or entry.title
    local activityID=Readable(info.activityIDs)
    if type(activityID)=="table" then activityID=Readable(activityID[1]) end
    if type(activityID)=="number" then
        entry.activity="Activity "..activityID
        if type(C_LFGList)=="table" and type(C_LFGList.GetActivityInfoTable)=="function" then
            local ok,activity=pcall(C_LFGList.GetActivityInfoTable,activityID)
            activity=ok and Readable(activity) or nil
            if type(activity)=="table" then
                entry.activity=Plain(activity.fullName) or Plain(activity.shortName)
                    or Plain(activity.name) or entry.activity
            end
        end
    end
    entry.sentCount=entry.sentCount+1
    AddMessage(entry,"out",outgoing)
    PruneOldest()
    Refresh()
    UpdateFinderBadge()
end

function Apps.ListingEnded(record)
    local entry=record and byRecord[record]
    if entry then
        entry.ended=true
        Refresh()
    end
end

function Apps.StatusFor(record)
    local entry=record and byRecord[record]
    if not entry then return nil end
    if entry.replies>0 then return "Replied" end
    return "Sent"
end

local function FindEntry(sender)
    local key=NameKey(sender)
    if not key then return nil end
    -- Exact realm-qualified identity wins.
    for _,entry in ipairs(entries) do
        if entry.nameKey==key and not entry.ended then return entry end
    end
    -- If only one active leader matches a base name, an incomplete realm
    -- suffix is safe; otherwise do not attach the message to a group.
    local base=key:match("^([^%-]+)")
    if not base then return nil end
    local candidate,identity=nil,nil
    for _,entry in ipairs(entries) do
        if not entry.ended and entry.nameKey
            and entry.nameKey:match("^([^%-]+)")==base then
            if identity and identity~=entry.nameKey then return nil end
            candidate,identity=entry,entry.nameKey
        end
    end
    return candidate
end

local function Receive(message,sender)
    message,sender=Plain(message),Plain(sender)
    if not message or not sender then return end
    local match=FindEntry(sender)
    if not match then return end
    AddMessage(match,"in",message)
    match.replies=match.replies+1
    if selected==match and panel and panel:IsShown() then
        match.unread=0
    else
        match.unread=match.unread+1
    end
    Refresh()
    UpdateFinderBadge()
end

local function Outgoing(message,recipient)
    message,recipient=Plain(message),Plain(recipient)
    if not message or not recipient then return end
    local match=FindEntry(recipient)
    if not match then return end
    local last=match.messages[#match.messages]
    -- QuickJoin's own click is already recorded by TrackSent. Ignore the
    -- corresponding WHISPER_INFORM confirmation so it is not doubled.
    if last and last.direction=="out" and last.message==message
        and Clock()-last.at<3 then return end
    AddMessage(match,"out",message)
    Refresh()
end

function Apps.Attach(parent)
    if panel then return end
    window=parent
    panel=CreateFrame("Frame","ForeverQuickJoinApplicationsPanel",window,"BackdropTemplate")
    panel:SetPoint("TOPLEFT",window,"TOPLEFT",12,-51)
    panel:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-12,12)
    panel:SetFrameLevel(window:GetFrameLevel()+10)
    panel:EnableMouse(true)
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true,tileSize=32,edgeSize=20,insets={left=0,right=0,top=0,bottom=0}})
    panel:SetBackdropColor(.035,.045,.065,1)
    Label(panel,"MY APPLICATIONS",17,10,460,28,"GameFontNormalLarge")
    Label(panel,"Whispers and replies from group leaders. Session-only; no automatic searches.",
        17,156,780,22)
    listTitle=Label(panel,"CONTACTED GROUPS (0)",16,193,770,23,"GameFontNormal")
    local left=CreateFrame("Frame",nil,panel,"BackdropTemplate")
    left:SetPoint("TOPLEFT",panel,"TOPLEFT",15,-226)
    left:SetSize(306,444)
    left:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    left:SetBackdropColor(.073,.09,.12,1)
    local right=CreateFrame("Frame",nil,panel,"BackdropTemplate")
    right:SetPoint("TOPLEFT",panel,"TOPLEFT",330,-226)
    right:SetSize(465,444)
    right:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    right:SetBackdropColor(.073,.09,.12,1)
    for i=1,PAGE_SIZE do
        local row=CreateFrame("Button",nil,left,"BackdropTemplate")
        row:SetPoint("TOPLEFT",left,"TOPLEFT",7,-(8+(i-1)*49))
        row:SetSize(291,45)
        row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        row:SetBackdropColor(.085,.105,.14,1)
        row.title=Label(row,"",9,5,272,20,"GameFontNormalSmall")
        row.info=Label(row,"",9,24,272,17,"GameFontHighlightSmall")
        row:SetScript("OnClick",function(self)
            selected=self.entry
            if selected then selected.unread=0 end
            Refresh()
        end)
        row:Hide()
        listRows[i]=row
    end
    previousButton=Button(left,"<",9,413,49,25,function()currentPage=currentPage-1;Refresh()end)
    pageLabel=Label(left,"1 / 1",108,416,100,20)
    nextButton=Button(left,">",241,413,49,25,function()currentPage=currentPage+1;Refresh()end)
    detailsTitle=Label(right,"Select a contacted group",12,10,440,25,"GameFontNormal")
    detailsInfo=Label(right,"",12,40,440,50,"GameFontHighlightSmall")
    conversation=CreateFrame("ScrollingMessageFrame",nil,right)
    conversation:SetPoint("TOPLEFT",right,"TOPLEFT",12,-105)
    conversation:SetSize(440,264)
    conversation:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    conversation:SetMaxLines(120)
    conversation:SetFading(false)
    conversation:EnableMouseWheel(true)
    conversation:SetScript("OnMouseWheel",function(self,delta)
        if delta>0 then self:ScrollUp() else self:ScrollDown() end
    end)
    replyButton=Button(right,"Reply to leader",12,397,154,29,function()
        if not selected or not Plain(selected.leader) then return end
        local recipient=selected.leader:gsub('[\r\n"]',"")
        if type(ChatFrame_OpenChat)=="function" then
            ChatFrame_OpenChat("/w "..recipient.." ")
        end
    end)
    Label(right,"Reply prepares chat; press Enter to send.",177,402,277,25)
    Label(panel,"Sent means submitted, not delivered. No reply is inferred from silence.",
        17,683,780,22,"GameFontHighlightSmall")
    panel:Hide()
    UpdateTab()
end

function Apps.Open()
    if not panel then return end
    panel:Show()
    Refresh()
end
function Apps.Hide()
    if panel then panel:Hide() end
end
function Apps.Counts() return #entries,CountUnread() end

local listener=CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
listener:SetScript("OnEvent",function(_,event,message,sender)
    if event=="CHAT_MSG_WHISPER" then Receive(message,sender)
    elseif event=="CHAT_MSG_WHISPER_INFORM" then Outgoing(message,sender) end
end)
