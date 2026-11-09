-- Forever QuickJoin 0.7.1 -- sharp role artwork and streamlined role correction.
-- This does not change Blizzard's protected group roles or inspect talents/specs.
local Party = {}
ForeverQuickJoinParty = Party

local ROLE_ORDER = {"TANK", "HEALER", "DAMAGER"}
local ROLE_NAME = {TANK="Tank", HEALER="Healer", DAMAGER="DPS", UNKNOWN="Unknown"}
local ROLE_ICON = {
    TANK="|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:14:14:0:-1:64:64:0:19:22:41|t",
    HEALER="|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:14:14:0:-1:64:64:20:39:1:20|t",
    DAMAGER="|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES.blp:14:14:0:-1:64:64:20:39:22:41|t",
    UNKNOWN="",
}
-- The old PORTRAITROLES sheet allocates only ~19px per icon, which blurs
-- when enlarged. Blizzard's larger 256x64 UI-LFG-ICON-ROLES sheet gives
-- each role a native 64x64 region, rendered here at 28px.
local ROLE_ICON_LARGE = {
    TANK="|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:28:28:0:-1:256:64:128:192:0:64|t",
    HEALER="|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:28:28:0:-1:256:64:192:256:0:64|t",
    DAMAGER="|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:28:28:0:-1:256:64:64:128:0:64|t",
}
-- Original WoW classes with more than one traditional group role.
-- Forever customizations cannot reliably be inferred from class or spec;
-- overrides remain available for EVERY class.
local NEEDS_DPS_CONFIRMATION = {PRIEST=true, SHAMAN=true, DRUID=true, PALADIN=true, WARRIOR=true}
local overrides = {} -- per-session only; never saved to SavedVariables
local summary, summaryTitle, summaryCounts, summaryNotice, reviewButton, manager, managerStatus
local memberRows, managerPage, pageLabel, prevButton, nextButton = {}, 1
local currentMembers, previousWasGroup = {}, false
local attachedWindow
local PAGE_SIZE = 7

local function Readable(value)
    if type(canaccessvalue)=="function" and not canaccessvalue(value) then return nil end
    if type(issecretvalue)=="function" and issecretvalue(value) then return nil end
    return value
end
local function Safe(func, ...)
    if type(func)~="function" then return nil end
    local ok, a, b = pcall(func, ...)
    if not ok then return nil end
    return Readable(a), Readable(b)
end
local function NormalRole(value)
    if value=="TANK" or value=="HEALER" or value=="DAMAGER" then return value end
    return "UNKNOWN"
end
local function LfgRoleSelection()
    local api = C_LFGListRoles and C_LFGListRoles.GetRoles
    local values = Safe(api)
    if type(values)~="table" then return nil end
    local count = (values.tank and 1 or 0) + (values.healer and 1 or 0) + (values.dps and 1 or 0)
    if count ~= 1 then return nil end
    if values.tank then return "TANK" end
    if values.healer then return "HEALER" end
    return "DAMAGER"
end
local function MemberFor(unit, isSelf)
    local name, realm = Safe(UnitName, unit)
    local className, classFile = Safe(UnitClass, unit)
    local level = Safe(UnitLevel, unit)
    local guid = Safe(UnitGUID, unit)
    local assigned = NormalRole(Safe(UnitGroupRolesAssigned, unit))
    if type(name)~="string" or name=="" then name = "Unknown member" end
    if type(realm)=="string" and realm~="" then name = name .. "-" .. realm end
    local key = type(guid)=="string" and guid~="" and ("guid:"..guid)
        or (name~="Unknown member" and "name:"..name:lower()) or ("unit:"..unit)
    className = type(className)=="string" and className or "Unknown class"
    classFile = type(classFile)=="string" and classFile or "UNKNOWN"
    -- WoW's native assignments may be missing. For the player's *own* role,
    -- a single selected LFG role is an additional signal, but remains reviewable.
    if assigned=="UNKNOWN" and isSelf then assigned = LfgRoleSelection() or "UNKNOWN" end
    local override = overrides[key]
    local effective, confirmed, source, review, reason
    if override then
        effective = override.role
        source = "QuickJoin confirmed"
        confirmed = override.assignedAtConfirmation == assigned
        review = not confirmed
        reason = review and "WoW role changed — confirm again" or nil
    else
        effective = assigned
        source = "WoW-assigned"
        if effective=="UNKNOWN" then
            -- Never assign a party member's role solely from their class.
            -- Forever can introduce custom role-capable specializations.
            confirmed=false
            review=true
            reason="No assigned role"
        elseif effective=="DAMAGER" and (NEEDS_DPS_CONFIRMATION[classFile] or classFile=="UNKNOWN") then
            confirmed=false
            review=true
            reason="DPS needs confirmation"
        else
            confirmed=true
            review=false
        end
    end
    return {
        key=key, unit=unit, name=name, className=className, classFile=classFile,
        level=type(level)=="number" and level>0 and tostring(level) or "?",
        assigned=assigned, role=effective, confirmed=confirmed==true,
        review=review==true, source=source, reason=reason, isSelf=isSelf,
    }
end
local function Scan()
    local people={MemberFor("player",true)}
    local n = Safe(GetNumGroupMembers)
    if type(n)~="number" or n<2 then return people, false end
    n=math.min(40,math.floor(n))
    local isRaid = Safe(IsInRaid)==true
    if isRaid then
        local selfKey=people[1].key
        for i=1,n do
            local unit="raid"..i
            if Safe(UnitExists,unit)==true then
                local isSelf = Safe(UnitIsUnit,unit,"player")
                local member=MemberFor(unit, false)
                if isSelf~=true and member.key~=selfKey then
                    people[#people+1]=member
                end
            end
        end
    else
        for i=1,math.min(n-1,4) do
            local unit="party"..i
            if Safe(UnitExists,unit)==true then
                local isSelf=Safe(UnitIsUnit,unit,"player")
                if isSelf~=true then people[#people+1]=MemberFor(unit,false) end
            end
        end
    end
    return people,true
end
local function Snapshot(prune)
    local members, grouped = Scan()
    if prune then
        if previousWasGroup and not grouped then
            -- Rejoining later is a new group session, even for the same player.
            overrides={}
            members,grouped=Scan()
        elseif grouped then
            local present={}
            for _,m in ipairs(members) do present[m.key]=true end
            for key in pairs(overrides) do if not present[key] then overrides[key]=nil end end
        end
        previousWasGroup=grouped
    end
    currentMembers=members
    return members,grouped
end
function Party.RoleFor(unit)
    -- GROUP_ROSTER_UPDATE / ROLE_CHANGED_INFORM refresh this snapshot. Reuse
    -- it for message generation: otherwise a 40-player raid would re-scan the
    -- entire roster for every one of its 39 members.
    local members=currentMembers
    if #members==0 then members=Snapshot(false) end
    for _,m in ipairs(members) do
        if m.unit==unit or (unit=="player" and m.isSelf) then
            return m.role,m.review,m.confirmed
        end
    end
    members=Snapshot(false)
    for _,m in ipairs(members) do
        if m.unit==unit or (unit=="player" and m.isSelf) then
            return m.role,m.review,m.confirmed
        end
    end
    return "UNKNOWN",true,false
end
function Party.NeedsReview()
    local members,grouped=Snapshot(false)
    if not grouped then return 0 end
    local count=0
    for _,m in ipairs(members) do if m.review then count=count+1 end end
    local total=Safe(GetNumGroupMembers)
    if type(total)=="number" then count=count+math.max(0,math.floor(total)-#members) end
    return count
end
local function Label(parent,text,x,y,w,h,font)
    local label=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    label:SetSize(w,h)
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    return label
end
local function Button(parent,text,x,y,w,h,handler)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    b:SetSize(w,h)
    b:SetText(text)
    b:SetScript("OnClick",handler)
    return b
end
local function Counts(members)
    local totals={TANK=0,HEALER=0,DAMAGER=0,UNKNOWN=0}
    local review=0
    for _,m in ipairs(members) do
        totals[m.role]=(totals[m.role] or 0)+1
        if m.review then review=review+1 end
    end
    return totals,review
end
local function RefreshView()
    local members,grouped=Snapshot(false)
    local count,review=Counts(members)
    local announced=Safe(GetNumGroupMembers)
    announced=grouped and type(announced)=="number" and math.floor(announced) or #members
    local missing=math.max(0,announced-#members)
    count.UNKNOWN=count.UNKNOWN+missing
    review=review+missing
    if summaryTitle then
        if grouped then
            summaryTitle:SetText("Party detected ("..announced..")"..(review>0 and " !" or ""))
            summaryTitle:SetTextColor(review>0 and 1 or .75, review>0 and .77 or 1, review>0 and .32 or .73)
        else
            summaryTitle:SetText("Solo — role: "..(ROLE_NAME[members[1].role] or "Unknown"))
        end
        summaryCounts:SetText(ROLE_ICON_LARGE.TANK.." "..count.TANK.."    "
            ..ROLE_ICON_LARGE.HEALER.." "..count.HEALER.."    "
            ..ROLE_ICON_LARGE.DAMAGER.." "..count.DAMAGER
            ..(count.UNKNOWN>0 and ("   Unassigned: "..count.UNKNOWN) or ""))
        summaryNotice:SetText(review>0 and (review.." role"..(review==1 and "" or "s").." need review")
            or (grouped and "Roles confirmed" or "Current character"))
        summaryNotice:SetTextColor(review>0 and 1 or .65, review>0 and .77 or .85, review>0 and .35 or .7)
        reviewButton:SetText(review>0 and "Review / Fix Roles" or "Change Roles")
    end
    if not manager or not manager:IsShown() then return end
    local pages=math.max(1,math.ceil(#members/PAGE_SIZE))
    managerPage=math.max(1,math.min(managerPage,pages))
    if pageLabel then pageLabel:SetText(("Page %d / %d"):format(managerPage,pages)) end
    if prevButton then prevButton:SetEnabled(managerPage>1) end
    if nextButton then nextButton:SetEnabled(managerPage<pages) end
    if managerStatus then
        managerStatus:SetText(("Party %d; %d to review%s. Corrections do not modify Blizzard roles."):format(announced,review,missing>0 and (" ("..missing.." roster unavailable)") or ""))
    end
    for i,row in ipairs(memberRows) do
        local m=members[(managerPage-1)*PAGE_SIZE+i]
        row.member=m
        if not m then row:Hide() else
            row:Show()
            row.title:SetText((m.isSelf and "You: " or "")..m.name.."  •  Lv"..m.level.." "..m.className)
            if m.role=="TANK" then
                row.roleIcon:SetTexCoord(0.5,0.75,0,1)
                row.roleIcon:Show()
            elseif m.role=="HEALER" then
                row.roleIcon:SetTexCoord(0.75,1,0,1)
                row.roleIcon:Show()
            elseif m.role=="DAMAGER" then
                row.roleIcon:SetTexCoord(0.25,0.5,0,1)
                row.roleIcon:Show()
            else
                -- Unassigned roles require selection; do not show an incorrect icon.
                row.roleIcon:Hide()
            end
            local hint= m.reason and (m.reason.."  |  ") or ""
            row.info:SetText(hint.."WoW: "..(ROLE_NAME[m.assigned] or "Unknown").."  |  "..m.source)
            row.info:SetTextColor(m.review and 1 or .7,m.review and .75 or .88,m.review and .35 or .76)
            for _,role in ipairs(ROLE_ORDER) do
                local selected=m.role==role
                row.roleButtons[role]:SetText((selected and "[" or "")..ROLE_NAME[role]
                    ..(selected and "]" or ""))
            end
            -- Auto is an action, not a selectable role. Never turn it into '?'.
            row.roleButtons.AUTO:SetText("Auto")
        end
    end
end
local function NotifyChanged()
    RefreshView()
    if attachedWindow and attachedWindow.QuickJoinUpdatePreview then attachedWindow.QuickJoinUpdatePreview() end
end
local function Override(member,role)
    if not member then return end
    overrides[member.key]={role=NormalRole(role),assignedAtConfirmation=member.assigned}
    NotifyChanged()
end
function Party.Open()
    if manager then
        managerPage=1
        manager:Show()
        RefreshView()
    end
end
function Party.Refresh(prune)
    Snapshot(prune==true)
    RefreshView()
end
function Party.Attach(window)
    if summary then return end
    attachedWindow=window
    -- A full-width status area replaces the two removed filter rows. Keep it
    -- above the hosting panel so the party composition is visible on BOTH tabs.
    summary=CreateFrame("Frame",nil,window,"BackdropTemplate")
    summary:SetPoint("TOPLEFT",window,"TOPLEFT",25,-117)
    summary:SetSize(789,76)
    summary:SetFrameLevel(window:GetFrameLevel()+30)
    summary:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=1,right=1,top=1,bottom=1}})
    summary:SetBackdropColor(.07,.09,.12,1)
    summaryTitle=Label(summary,"Party detected",15,8,340,25,"GameFontNormalLarge")
    summaryNotice=Label(summary,"",354,11,230,21,"GameFontNormalSmall")
    summaryCounts=Label(summary,"",15,39,584,32,"GameFontNormalLarge")
    reviewButton=Button(summary,"Change Roles",614,22,158,35,Party.Open)

    manager=CreateFrame("Frame","ForeverQuickJoinRoleManager",window,"BackdropTemplate")
    manager:SetPoint("TOPLEFT",window,"TOPLEFT",33,-68)
    manager:SetSize(774,654)
    manager:SetFrameLevel(window:GetFrameLevel()+50)
    manager:EnableMouse(true)
    manager:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=24,insets={left=0,right=0,top=0,bottom=0}})
    manager:SetBackdropColor(.035,.045,.065,1)
    Label(manager,"PARTY ROLE MANAGER",22,16,460,28,"GameFontNormalLarge")
    Button(manager,"Close",653,17,90,27,function() manager:Hide() end)
    Label(manager,"Detect members automatically. Correct roles here; no changes are sent to Blizzard.",22,50,720,24)
    managerStatus=Label(manager,"",22,78,720,24,"GameFontNormalSmall")
    for i=1,PAGE_SIZE do
        local y=111+(i-1)*65
        local row=CreateFrame("Frame",nil,manager,"BackdropTemplate")
        row:SetPoint("TOPLEFT",manager,"TOPLEFT",21,-y)
        row:SetSize(731,60)
        row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        row:SetBackdropColor(.085,.105,.14,1)
        row.roleIcon=row:CreateTexture(nil,"ARTWORK")
        row.roleIcon:SetSize(33,33)
        row.roleIcon:SetPoint("TOPLEFT",row,"TOPLEFT",12,-12)
        row.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        row.roleIcon:Hide()
        row.title=Label(row,"",57,5,333,25,"GameFontNormal")
        row.info=Label(row,"",57,30,333,23,"GameFontHighlightSmall")
        row.roleButtons={}
        for j,role in ipairs(ROLE_ORDER) do
            row.roleButtons[role]=Button(row,ROLE_NAME[role],395+(j-1)*96,15,88,29,function()
                Override(row.member,role)
            end)
        end
        row.roleButtons.AUTO=Button(row,"Auto",682,15,44,29,function()
            if row.member then overrides[row.member.key]=nil; NotifyChanged() end
        end)
        row:Hide()
        memberRows[i]=row
    end
    prevButton=Button(manager,"<",23,574,48,25,function() managerPage=managerPage-1;RefreshView() end)
    pageLabel=Label(manager,"Page 1 / 1",81,580,125,20)
    nextButton=Button(manager,">",213,574,48,25,function() managerPage=managerPage+1;RefreshView() end)
    -- Deliberately no bulk confirmation/reset buttons. Select a role on the
    -- relevant player row; Auto clears an individual override.
    Label(manager,"Pick Tank, Healer or DPS for each uncertain member. Auto clears an override; unknown roles must be assigned.",22,613,726,21,"GameFontHighlightSmall")
    manager:Hide()
    RefreshView()
end

local watcher=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","GROUP_ROSTER_UPDATE","PLAYER_ROLES_ASSIGNED","ROLE_CHANGED_INFORM","UNIT_LEVEL","PLAYER_LEVEL_UP"}) do
    watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent",function(_,event)
    Party.Refresh(event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_LOGIN")
end)
