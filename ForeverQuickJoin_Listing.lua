-- ForeverQuickJoin_Listing - integrated group-listing creator for WoW Forever.
-- Loaded as part of ForeverQuickJoin; no companion addon required.
-- Never automate listing submissions, copy protected text, change security flags,
-- or call Blizzard's protected button handlers. Posting is always a physical click.
local addonName = ...
local ADDON = "Forever QuickJoin"
local PREFIX = "|cff69c3ffQuickJoin Listing|r: "
local frame, parentPanel, existingButton, originalClick, creator, editorSlot
local navOverlay, applicantsNav, topHostingTab, topApplicationsTab, finderContent
local topFindTab, mainSelected = nil, "find"
local tabIndicators = {}
local finderPlaystyleDropdown, finderPlaystyleChecks
local finderHelpLabel
local creatorCategoryDropdown, creatorStyleDropdown
local applicationBackButton, roleManagerOpacityHooked = nil, false
local finderAlignmentInstalled = false
local underlayHidden, underlayIsHidden = {}, false
-- View isolation and backdrop transparency are separate concerns. Keep the old
-- applicant controls hidden, but never cover Manage Listing in an opaque
-- texture: the main addon's theme menu owns transparency.
local previewBackdrops = {}
local parentBackdropSaved = nil
local lastVisualState = nil
local statusText, activeLabel, categoryText, selectedLabel, playstyleText
local searchInput, friendlyCheck, createButton, updateButton, delistButton
local activityDropdown, allLevelsCheck
local categories, activities, selectedIDs, selectedSet = {}, {}, {}, {}
local categoryIndex, selectedCategory, selectedStyle = 1, nil, 2
local showAllLevels = false
local isOpen, editorState, restorePending, restoreFailed = false, nil, false, false
-- v3: native input template sizes the EditBox on load, not on reparent. The
-- scroll viewport and its child must both be resized when docked.
local initialized, callCounter, lastAttempt = false, 0, nil
local delistArmed = false
local lastStyleWarningFor = nil
local persistentStyleWarning = nil
local exportPanel, exportEdit, exportScroll
local db

local function Secret(v)
    if type(issecretvalue)=="function" then
        local ok,r=pcall(issecretvalue,v)
        if ok and r then return true end
    end
    if type(canaccessvalue)=="function" then
        local ok,r=pcall(canaccessvalue,v)
        if ok and not r then return true end
    end
    return false
end
local function Clean(v,n)
    if Secret(v) then return "<protected>" end
    local t=type(v)
    if t=="nil" then return "nil" end
    if t=="table" then return "<table>" end
    if t=="function" then return "<function>" end
    local ok,text=pcall(tostring,v)
    if not ok or type(text)~="string" then return "<unprintable>" end
    text=text:gsub("[\r\n]"," "):gsub("|","||")
    if #text>(n or 170) then text=text:sub(1,n or 170).."..." end
    return text
end
local function Clock()
    local stamp="?"
    if type(date)=="function" then
        local ok,v=pcall(date,"%H:%M:%S")
        if ok and type(v)=="string" then stamp=v end
    end
    return stamp
end
local function Log(kind,message)
    db=type(ForeverQuickJoinListingDB)=="table" and ForeverQuickJoinListingDB or {}
    ForeverQuickJoinListingDB=db
    if type(db.lines)~="table" then db.lines={} end
    local line="["..Clock().."] ["..kind.."] "..Clean(message,650)
    db.lines[#db.lines+1]=line
    while #db.lines>260 do table.remove(db.lines,1) end
    if statusText then
        local display=(persistentStyleWarning and kind=="VERIFY")
            and ("STYLE WARNING: "..persistentStyleWarning) or (kind..": "..Clean(message,105))
        statusText:SetText(display)
    end
end
local function Notice(s)
    Log("NOTICE",s)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX..Clean(s,240)) end
end
local function TryRead(label,fn,...)
    if type(fn)~="function" then return nil,false end
    local ok,val=pcall(fn,...)
    if not ok then Log("READ ERROR",label.." => "..Clean(val));return nil,false end
    if Secret(val) then Log("PROTECTED",label.." returned a protected value"); return nil,false end
    return val,true
end
local function Combat()
    return type(InCombatLockdown)=="function" and InCombatLockdown()==true
end
local function Function(name)
    if type(C_LFGList)=="table" and type(C_LFGList[name])=="function" then return C_LFGList[name] end
end
local function CurrentEntry()
    local val,ok=TryRead("GetActiveEntryInfo",Function("GetActiveEntryInfo"))
    return ok and type(val)=="table" and val or nil
end
local function HasEntry()
    local val,ok=TryRead("HasActiveEntryInfo",Function("HasActiveEntryInfo"))
    if ok then return val==true end
    return CurrentEntry()~=nil
end
local function DescriptionKind(entry)
    if type(entry)~="table" then return "no listing" end
    local text=entry.comment
    if Secret(text) then return "protected text" end
    if type(text)=="string" then
        if text=="" then return "empty" end
        if text:match("^|K[%w]+|k$") then return "protected Kstring" end
        return "present (redacted)"
    end
    return text==nil and "empty/missing" or "opaque"
end
local function IDString(ids)
    if type(ids)~="table" then return "{}" end
    local output={}
    for i=1,math.min(#ids,15) do output[#output+1]=Clean(ids[i],16) end
    return "{"..table.concat(output,",").."}"
end
local function IDsMatch(a,b)
    if type(a)~="table" or type(b)~="table" or #a~=#b then return false end
    local m={}
    for _,id in ipairs(a) do m[id]=(m[id] or 0)+1 end
    for _,id in ipairs(b) do
        if not m[id] or m[id]==0 then return false end
        m[id]=m[id]-1
    end
    return true
end
local function Snapshot(reason)
    local entry=CurrentEntry()
    local ids=entry and entry.activityIDs
    local eligible=type(ids)=="table" and not Secret(ids)
    local active=entry~=nil
    Log("VERIFY",reason.." active="..tostring(active).." ids="..(eligible and IDString(ids) or "<unavailable>")
        .." style="..Clean(entry and entry.generalPlaystyle)
        .." description="..DescriptionKind(entry)
        .." matchesLastAttempt="..(lastAttempt and eligible and tostring(IDsMatch(ids,lastAttempt.ids)) or "n/a"))
    if activeLabel then
        activeLabel:SetText(active and ("ACTIVE: "..(eligible and tostring(#ids).." activities" or "listing")
            .."  |  Playstyle: "..Clean(entry and entry.generalPlaystyle)) or "No active listing")
    end
    -- Some Forever client builds silently reset generalPlaystyle to 0 on an
    -- UpdateListing even when the submitted payload includes this field. Warn
    -- explicitly; never claim preservation unless verified by active state.
    if active and lastAttempt and lastAttempt.kind=="UPDATE" and lastAttempt.expectedStyle
        and type(entry.generalPlaystyle)=="number" and entry.generalPlaystyle~=lastAttempt.expectedStyle
        and lastStyleWarningFor~=lastAttempt.id then
        lastStyleWarningFor=lastAttempt.id
        persistentStyleWarning="Update #"..lastAttempt.id.." requested "..lastAttempt.expectedStyle
            ..", active listing reports "..entry.generalPlaystyle.."; check Blizzard UI."
        Log("STYLE WARNING",persistentStyleWarning)
    end
    if creator and creator:IsShown() then
        if createButton then if active then createButton:Disable() else createButton:Enable() end end
        if updateButton then if active then updateButton:Enable() else updateButton:Disable() end end
        if delistButton then if active then delistButton:Enable() else delistButton:Disable() end end
    end
end
local function DelayedSnapshot(op)
    if C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(1.5,function() Snapshot("1.5s after "..op) end)
    end
end
local function Label(parent,text,x,y,w,h,font)
    local fs=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    fs:SetSize(w,h)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end
local function Button(parent,text,x,y,w,h,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    b:SetSize(w,h)
    b:SetText(text)
    b:SetScript("OnClick",fn)
    return b
end
local function Field(parent,x,y,w,h)
    local f=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    f:SetSize(w,h)
    f:SetAutoFocus(false)
    f:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
    f:SetScript("OnEnterPressed",function(self)self:ClearFocus()end)
    return f
end
local function Backdrop(parent,x,y,w,h)
    local f=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    f:SetSize(w,h)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3}})
    f:SetBackdropColor(.07,.09,.12,1)
    previewBackdrops[#previewBackdrops+1]=f
    return f
end
local function NativeEditor()
    local listing=type(LFGListingFrame)=="table" and LFGListingFrame
    local view=listing and listing.ActivityView
    local scroll=view and view.Comment
    local edit=scroll and scroll.EditBox
    if scroll and edit and type(scroll.GetParent)=="function" then return scroll,edit end
end
local function FrameName(obj)
    if not obj then return "nil" end
    local ok,v=pcall(function()return obj.GetName and obj:GetName()end)
    return ok and type(v)=="string" and v or "<unnamed>"
end
local function EditorDimensions(scroll, edit)
    local instructions=edit and edit.Instructions
    local function Measure(f,method)
        if not f or type(f[method])~="function" then return nil end
        local ok,value=pcall(f[method],f)
        if ok and type(value)=="number" and value>0 then return value end
    end
    return {scrollW=Measure(scroll,"GetWidth"),scrollH=Measure(scroll,"GetHeight"),
        editW=Measure(edit,"GetWidth"),instructionsW=Measure(instructions,"GetWidth")}
end
local function Dim(v)
    return type(v)=="number" and string.format("%.1f",v) or "unknown"
end
-- Re-anchor both the Blizzard ScrollFrame and its underlying EditBox inside
-- our 360x132 panel. This is geometry only: do NOT SetText/Paste, replace
-- the editor, bypass protection flags, or copy the protected description.
local function SizeDockedEditor()
    if not editorState or not editorSlot then return false end
    local scroll,edit=editorState.scroll,editorState.edit
    local slotW,slotH=editorSlot:GetWidth(),editorSlot:GetHeight()
    if type(slotW)~="number" or type(slotH)~="number" or slotW<100 or slotH<85 then
        Log("LAYOUT","Invalid editor slot size; cannot fit native editor")
        return false
    end
    local viewW=math.floor(slotW-24)
    local viewH=math.floor(slotH-54)
    local inputW=viewW-20 -- account for the input scroll frame's native scrollbar
    if viewW<70 or viewH<25 or inputW<50 then return false end
    scroll:ClearAllPoints()
    scroll:SetSize(viewW,viewH)
    scroll:SetPoint("TOPLEFT",editorSlot,"TOPLEFT",12,-32)
    edit:SetWidth(inputW)
    if edit.Instructions and type(edit.Instructions.SetWidth)=="function" then
        edit.Instructions:SetWidth(inputW)
    end
    -- Frame clipping is optional on older Forever builds. The ScrollFrame
    -- clips text itself; clipping the slot also contains native border art.
    local clipResult="unavailable"
    if type(editorSlot.SetClipsChildren)=="function" then
        local ok,err=pcall(editorSlot.SetClipsChildren,editorSlot,true)
        clipResult=ok and "enabled" or "rejected"
        if not ok then Log("LAYOUT","optional frame clipping unavailable: "..Clean(err)) end
    end
    local actual=EditorDimensions(scroll,edit)
    local fits=(not actual.editW or actual.editW<=viewW)
        and (not actual.scrollW or actual.scrollW<=slotW-12)
    Log("LAYOUT","slot="..Dim(slotW).."x"..Dim(slotH)
        .." viewport="..Dim(actual.scrollW).."x"..Dim(actual.scrollH)
        .." inputWidth="..Dim(actual.editW).." target="..inputW
        .." clipping="..clipResult.." fit="..tostring(fits))
    if not fits then
        Log("LAYOUT WARNING","WoW did not honor a bounded native editor width; restoring original UI")
    end
    return fits
end
local function RestoreEditor(reason)
    if not editorState then restorePending=false;return true end
    if Combat() then
        restorePending=true
        Log("RESTORE","Deferred until out of combat: "..reason)
        return false
    end
    local prior=editorState
    local ok,err=pcall(function()
        prior.scroll:SetParent(prior.parent)
        -- Restore geometry as well as parent/anchors so Blizzard's own editor
        -- does not inherit our narrow preview dimensions.
        if prior.dimensions.scrollW and prior.dimensions.scrollH then
            prior.scroll:SetSize(prior.dimensions.scrollW,prior.dimensions.scrollH)
        end
        if prior.dimensions.editW then prior.edit:SetWidth(prior.dimensions.editW) end
        if prior.dimensions.instructionsW and prior.edit.Instructions then
            prior.edit.Instructions:SetWidth(prior.dimensions.instructionsW)
        end
        prior.scroll:ClearAllPoints()
        for _,point in ipairs(prior.points) do prior.scroll:SetPoint(unpack(point)) end
        if prior.shown then prior.scroll:Show() else prior.scroll:Hide() end
    end)
    local success=ok and prior.scroll:GetParent()==prior.parent
    if success then
        editorState=nil
        restorePending=false
        restoreFailed=false
        Log("RESTORE","Restored native editor parent, dimensions, and "..#prior.points.." anchors: "..reason)
    else
        restorePending=true
        restoreFailed=true
        Log("RESTORE","FAILED "..Clean(err)..". Try /reload out of combat; reason="..reason)
    end
    return success
end
local function LoadNativeEditor()
    if NativeEditor() then return true end
    if Combat() then Notice("Cannot load the listing UI during combat.");return false end
    if type(GroupFinderVanillaStyle_LoadUI)=="function" then
        local ok,err=pcall(GroupFinderVanillaStyle_LoadUI)
        if not ok then Log("EDITOR","LoadUI error: "..Clean(err)) end
    end
    if NativeEditor() then return true end
    Notice("Blizzard's native editor is unavailable. Open the normal WoW listing UI and retry.")
    return false
end
local function DockEditor()
    if editorState then return true end
    if not creator or not editorSlot then return false end
    if Combat() then Notice("Cannot dock Blizzard's editor during combat.");return false end
    if not LoadNativeEditor() then return false end
    local scroll,edit=NativeEditor()
    if not scroll then return false end
    local previous={scroll=scroll,edit=edit,parent=scroll:GetParent(),shown=scroll:IsShown(),
        points={},dimensions=EditorDimensions(scroll,edit)}
    for i=1,scroll:GetNumPoints() do previous.points[#previous.points+1]={scroll:GetPoint(i)} end
    editorState=previous -- Recovery must be recorded before mutation.
    Log("DOCK","moving ORIGINAL Blizzard editor from "..FrameName(previous.parent)
        .." points="..#previous.points.." protected="..Clean(scroll.IsProtected and scroll:IsProtected())
        .." originalViewport="..Dim(previous.dimensions.scrollW).."x"..Dim(previous.dimensions.scrollH)
        .." originalInputWidth="..Dim(previous.dimensions.editW)
        .."; no SetText/Paste or security-flag modifications")
    local ok,err=pcall(function()
        scroll:SetParent(editorSlot)
        if not SizeDockedEditor() then error("native editor could not fit slot") end
        scroll:Show()
    end)
    if not ok or scroll:GetParent()~=editorSlot then
        Log("DOCK","Failed: "..Clean(err).."; restoring")
        RestoreEditor("failed dock")
        Notice("Editor docking failed; close the creator and use /reload if restoration is needed.")
        return false
    end
    Log("DOCK","success parentIsSlot=true sameOriginalEdit="..tostring(select(2,NativeEditor())==edit))
    return true
end
local function RefreshActivities()
    activities={}
    if not selectedCategory then return end
    local ids,ok=TryRead("GetAvailableActivities",Function("GetAvailableActivities"),selectedCategory)
    if ok and type(ids)=="table" then
        for _,id in ipairs(ids) do
            if type(id)=="number" then
                local info,exists=TryRead("GetActivityInfoTable",Function("GetActivityInfoTable"),id)
                local name="Activity "..id
                local level=""
                local minLevel,maxLevel=nil,nil
                if exists and type(info)=="table" then
                    local label=info.fullName or info.shortName or info.name
                    if type(label)=="string" and not Secret(label) then name=label end
                    local min,max=info.minLevelSuggestion,info.maxLevelSuggestion
                    if not Secret(min) and not Secret(max) and type(min)=="number" and type(max)=="number"
                        and min>0 and max>=min then
                        level=" ("..min.."-"..max..")"
                    else
                        min,max=nil,nil
                    end
                    minLevel,maxLevel=min,max
                end
                activities[#activities+1]={id=id,name=name,search=name:lower(),level=level,
                    minLevel=minLevel,maxLevel=maxLevel}
            end
        end
    end
    table.sort(activities,function(a,b)return a.name:lower()<b.name:lower()end)
    Log("CATALOG","category="..selectedCategory.." available activities="..#activities)
end
local function Limit()
    local c=type(Constants)=="table" and Constants.LFGConstsExposed
    local limit=type(c)=="table" and c.GROUP_FINDER_MAX_ACTIVITY_CAPACITY
    return type(limit)=="number" and limit>=1 and math.floor(limit) or 10
end
local function ChosenCopy()
    local result={}
    for _,id in ipairs(selectedIDs) do result[#result+1]=id end
    return result
end
local function UpdateSelected()
    if not selectedLabel then return end
    local names={}
    for i,id in ipairs(selectedIDs) do
        local name="Activity "..id
        for _,item in ipairs(activities) do
            if item.id==id then name=item.name;break end
        end
        names[#names+1]=name
    end
    local summary=#names==0 and "None yet" or table.concat(names,"\n")
    -- Display full selection independently of the menu, without only exposing IDs.
    selectedLabel:SetText("SELECTED ACTIVITIES ("..#selectedIDs.." / "..Limit()..")\n"..summary)
end
local function FilteredActivities()
    local query=searchInput and searchInput:GetText() or ""
    if type(query)~="string" or Secret(query) then query="" end
    query=query:lower()
    local filtered={}
    local playerLevel=type(UnitLevel)=="function" and UnitLevel("player") or nil
    if Secret(playerLevel) or type(playerLevel)~="number" or playerLevel<1 then playerLevel=nil end
    for _,item in ipairs(activities) do
        local matches=query=="" or item.search:find(query,1,true) or tostring(item.id):find(query,1,true)
        local inRange=showAllLevels or not playerLevel or not item.minLevel
            or (playerLevel>=item.minLevel and playerLevel<=item.maxLevel)
        -- Previously selected activities must stay reachable even if out of range.
        if matches and (inRange or selectedSet[item.id]) then filtered[#filtered+1]=item end
    end
    return filtered
end
local function RenderActivities()
    UpdateSelected()
    if activityDropdown then
        -- The native SetupMenu callback reads FilteredActivities at menu-open time.
        -- Keep this control static and the real selection summary below it.
        if type(activityDropdown.SetDefaultText)=="function" then
            activityDropdown:SetDefaultText("Choose activities ("..#selectedIDs..")")
        end
    end
end
local function ToggleActivityID(id)
    if type(id)~="number" then return end
    if selectedSet[id] then
        selectedSet[id]=nil
        for i,k in ipairs(selectedIDs) do if k==id then table.remove(selectedIDs,i);break end end
    else
        if #selectedIDs>=Limit() then
            Notice("Activity limit is "..Limit().." for this client.")
            return
        end
        selectedIDs[#selectedIDs+1]=id
        selectedSet[id]=true
    end
    Log("SELECT","activityIDs="..IDString(selectedIDs))
    RenderActivities()
end
local function LoadCategories()
    local prior=selectedCategory
    categories={}
    local ids,ok=TryRead("GetAvailableCategories",Function("GetAvailableCategories"))
    if ok and type(ids)=="table" then
        for _,id in ipairs(ids) do
            if type(id)=="number" then
                local info,infoOk=TryRead("GetLfgCategoryInfo",Function("GetLfgCategoryInfo"),id)
                local label="Category "..id
                if infoOk and type(info)=="table" and type(info.name)=="string" and not Secret(info.name) then
                    label=info.name
                end
                categories[#categories+1]={id=id,name=label}
            end
        end
    end
    categoryIndex=1
    if prior then
        for i,c in ipairs(categories) do if c.id==prior then categoryIndex=i;break end end
    end
    if #categories>0 then selectedCategory=categories[categoryIndex].id end
    Log("CATALOG","categories="..#categories)
end
local function SetCategory(index,clear)
    if #categories==0 then Notice("No categories yet: click Refresh Metadata.");return end
    categoryIndex=((index-1)%#categories)+1
    selectedCategory=categories[categoryIndex].id
    if categoryText then
        if type(categoryText.OverrideText)=="function" then
            categoryText:OverrideText(categories[categoryIndex].name)
        elseif type(categoryText.SetDefaultText)=="function" then
            categoryText:SetDefaultText(categories[categoryIndex].name)
        else categoryText:SetText(categories[categoryIndex].name) end
    end
    if clear then selectedIDs={};selectedSet={} end
    if searchInput then searchInput:SetText("") end
    RefreshActivities()
    RenderActivities()
end
local function RefreshCatalog(request)
    if request and Function("RequestAvailableActivities") then
        local _,ok=TryRead("RequestAvailableActivities",Function("RequestAvailableActivities"))
        Log("CATALOG","Requested client metadata; ok="..tostring(ok))
    end
    LoadCategories()
    SetCategory(categoryIndex,false)
end
local StyleValues
local function SetStyle(style)
    selectedStyle=style
    local title="Style "..tostring(style)
    for _,row in ipairs(StyleValues()) do
        if row.id==style then title=row.name;break end
    end
    if playstyleText then
        if type(playstyleText.OverrideText)=="function" then
            playstyleText:OverrideText(title)
        elseif type(playstyleText.SetDefaultText)=="function" then
            playstyleText:SetDefaultText(title)
        else playstyleText:SetText(title) end
    end
end
StyleValues=function()
    local v=type(Enum)=="table" and Enum.LFGEntryGeneralPlaystyle
    return {
        {id=v and v.Learning or 1,name="Learning"},
        {id=v and v.Casual or 2,name="Relaxed"},
        {id=v and v.Expert or 3,name="Expert"},
    }
end
local function ConfirmOperation(name,requireActive)
    if Combat() then Notice("Can't "..name.." during combat.");return false end
    if type(selectedCategory)~="number" or #selectedIDs<1 then
        Notice("Select a category and at least one activity.");return false
    end
    if #selectedIDs>Limit() then Notice("Too many activities.");return false end
    if type(IsInGroup)=="function" and IsInGroup() and
       type(UnitIsGroupLeader)=="function" and not UnitIsGroupLeader("player") then
       Notice("Only the party leader can modify a listing.");return false
    end
    if requireActive and not HasEntry() then Notice("No active listing to update.");return false end
    if not requireActive and HasEntry() then Notice("Listing already active. Use Update.");return false end
    if not Function(name) then Notice(name.." API is unavailable.");return false end
    return true
end
local function BeginAttempt(op,ids)
    delistArmed=false
    persistentStyleWarning=nil
    if delistButton then delistButton:SetText("Delist") end
    callCounter=callCounter+1
    lastAttempt={kind=op,ids=ChosenCopy(),id=callCounter,
        expectedStyle=selectedStyle}
    Log("PRECALL","#"..callCounter.." "..op.." ids="..IDString(ids)
        .." style="..Clean(selectedStyle).." friendly="..tostring(friendlyCheck and friendlyCheck:GetChecked()==true)
        .." editorDocked="..tostring(editorState~=nil)
        .."; real player click; contents of description NOT logged")
end
local function CreateOnClick()
    if not ConfirmOperation("CreateListing",false) then return end
    local ids=ChosenCopy()
    BeginAttempt("CREATE",ids)
    -- Direct OnClick only. Protected functions are not in pcall/timers/event callbacks.
    local result=C_LFGList.CreateListing({
        activityIDs=ids,
        newPlayerFriendly=friendlyCheck and friendlyCheck:GetChecked()==true or false,
        generalPlaystyle=selectedStyle,
        voiceMode=0,
    })
    Log("RETURN","CreateListing returned="..Clean(result).."; wait for active entry update")
    DelayedSnapshot("CreateListing")
end
local function UpdateOnClick()
    if not ConfirmOperation("UpdateListing",true) then return end
    local ids=ChosenCopy()
    local current=CurrentEntry()
    local currentStyle=current and current.generalPlaystyle
    local style=selectedStyle
    BeginAttempt("UPDATE",ids)
    Log("STYLE","Update old="..Clean(currentStyle).." selected="..Clean(style)
        .." (verify active state; Forever may reset to 0)")
    local result=C_LFGList.UpdateListing({
        activityIDs=ids,
        newPlayerFriendly=friendlyCheck and friendlyCheck:GetChecked()==true or false,
        voiceMode=(current and type(current.voiceMode)=="number" and current.voiceMode or 0),
        generalPlaystyle=style, -- Client may ignore this during Update; verify the active state.
    })
    Log("RETURN","UpdateListing returned="..Clean(result).."; check playstyle and activity IDs")
    DelayedSnapshot("UpdateListing")
end
local function DelistOnClick()
    if Combat() then Notice("Cannot delist in combat.");return end
    if not HasEntry() then Notice("No active listing to remove.");return end
    if not Function("RemoveListing") then Notice("RemoveListing API unavailable.");return end
    if not delistArmed then
        delistArmed=true
        delistButton:SetText("Confirm Delist")
        Notice("Press Confirm Delist a second time to remove your REAL listing.")
        return
    end
    delistArmed=false
    delistButton:SetText("Delist")
    Log("PRECALL","C_LFGList.RemoveListing(); direct player click")
    local r=C_LFGList.RemoveListing()
    Log("RETURN","RemoveListing result="..Clean(r))
    DelayedSnapshot("RemoveListing")
end
local function ExportLog()
    if not exportPanel then
        exportPanel=CreateFrame("Frame","ForeverQuickJoinListingExport",UIParent,"BackdropTemplate")
        exportPanel:SetSize(735,515)
        exportPanel:SetPoint("CENTER")
        exportPanel:SetFrameStrata("DIALOG")
        exportPanel:SetFrameLevel(200)
        exportPanel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=15,
            insets={left=4,right=4,top=4,bottom=4}})
        exportPanel:EnableMouse(true)
        Label(exportPanel,"QuickJoin Listing - Diagnostic Log (no descriptions, chat, or names)",20,15,675,27,"GameFontNormalLarge")
        Button(exportPanel,"Close",650,475,70,27,function()exportPanel:Hide()end)
        exportScroll=CreateFrame("ScrollFrame",nil,exportPanel,"UIPanelScrollFrameTemplate")
        exportScroll:SetPoint("TOPLEFT",exportPanel,"TOPLEFT",23,-58)
        exportScroll:SetPoint("BOTTOMRIGHT",exportPanel,"BOTTOMRIGHT",-40,58)
        exportEdit=CreateFrame("EditBox",nil,exportScroll)
        exportEdit:SetMultiLine(true)
        exportEdit:SetAutoFocus(false)
        exportEdit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        exportEdit:SetWidth(660)
        exportEdit:SetScript("OnEscapePressed",function(self)self:ClearFocus();exportPanel:Hide()end)
        exportScroll:SetScrollChild(exportEdit)
        exportPanel:Hide()
    end
    local lines=db and db.lines or {}
    local all={"Forever QuickJoin Listing diagnostic (optional diagnostic)","Descriptions, messages, and player names excluded.",""}
    for _,s in ipairs(lines) do all[#all+1]=s end
    exportEdit:SetText(table.concat(all,"\n"))
    exportPanel:Show()
    exportEdit:SetFocus()
    exportEdit:HighlightText()
    Notice("Log opened. Press Ctrl+A, Ctrl+C, then paste into chat.")
end
-- The normal List Group view contains high-frame-level applicant rows, labels,
-- and party controls. Merely painting an opaque frame in front of them does not
-- guarantee they stay behind the creator (especially with the Modern theme).
-- Hide the actual old view while Manage Listing is open; restore ONLY objects
-- that were originally shown when returning to Applicants/another main tab.
local function HideApplicantUnderlay()
    if underlayIsHidden or not parentPanel then return end
    underlayHidden={}
    local framesHidden,labelsHidden=0,0
    local function HideRemember(item,isLabel)
        if not item or type(item.IsShown)~="function" or not item:IsShown() then return end
        local ok=pcall(item.Hide,item)
        if ok and not item:IsShown() then
            underlayHidden[#underlayHidden+1]=item
            if isLabel then labelsHidden=labelsHidden+1 else framesHidden=framesHidden+1 end
        end
    end
    if type(parentPanel.GetChildren)=="function" then
        for _,child in ipairs({parentPanel:GetChildren()}) do
            -- Keep both our navigation overlay and Manage Listing visible.
            if child~=creator and child~=navOverlay then HideRemember(child,false) end
        end
    end
    if type(parentPanel.GetRegions)=="function" then
        for _,region in ipairs({parentPanel:GetRegions()}) do
            -- Don't hide the parent's backdrop textures, just native text.
            if type(region.GetObjectType)=="function" and region:GetObjectType()=="FontString" then
                HideRemember(region,true)
            end
        end
    end
    underlayIsHidden=true
    Log("ISOLATION","native applicant content hidden: frames="..framesHidden
        .." labels="..labelsHidden.."; preview navigation preserved")
end
local function RestoreApplicantUnderlay(reason)
    if not underlayIsHidden then return end
    local n=0
    for _,item in ipairs(underlayHidden) do
        if type(item.Show)=="function" then
            local ok=pcall(item.Show,item)
            if ok then n=n+1 end
        end
    end
    underlayHidden={}
    underlayIsHidden=false
    Log("ISOLATION","restored "..n.." native view objects: "..reason)
end
-- Respect the built-in Forever/Modern Transparency menu, including changes
-- made WHILE Manage Listing is open. Do not call SetAlpha on a parent: that
-- would fade text and the protected Blizzard editor along with the backdrop.
local function CurrentTheme()
    local api=ForeverQuickJoinTheme
    if type(api)=="table" and type(api.Current)=="function" then
        local ok,style,isTransparent=pcall(api.Current)
        if ok then return style=="Modern" and "Modern" or "Forever",isTransparent==true end
    end
    local saved=ForeverQuickJoinDB
    return (type(saved)=="table" and saved.theme=="Modern") and "Modern" or "Forever",
        type(saved)=="table" and saved.themeTransparency==true
end
local function GetPanelBackdrop()
    if not parentPanel or type(parentPanel.GetBackdropColor)~="function" then return nil end
    local ok,r,g,b,a=pcall(parentPanel.GetBackdropColor,parentPanel)
    if ok and type(r)=="number" and type(g)=="number"
        and type(b)=="number" and type(a)=="number" then
        return {r,g,b,a}
    end
end
local function RestoreHostBackdrop(reason)
    if parentBackdropSaved and parentPanel and type(parentPanel.SetBackdropColor)=="function" then
        parentPanel:SetBackdropColor(unpack(parentBackdropSaved))
        Log("TRANSPARENCY","restored native hosting backdrop ("..Clean(reason,65)..")")
    end
    parentBackdropSaved=nil
end
local function ApplyCreatorTransparency(reason,themeReapplied)
    if not creator then return end
    local theme,enabled=CurrentTheme()
    local mainColor=theme=="Modern" and {.049,.057,.074} or {.035,.047,.066}
    local insetColor=theme=="Modern" and {.075,.088,.109} or {.07,.09,.12}
    -- The underlying QuickJoin window already applies its own alpha. Use a
    -- lighter Manage backdrop to avoid accumulating multiple dark layers.
    creator:SetBackdropColor(mainColor[1],mainColor[2],mainColor[3],enabled and .23 or 1)
    for _,pane in ipairs(previewBackdrops) do
        if pane and type(pane.SetBackdropColor)=="function" then
            pane:SetBackdropColor(insetColor[1],insetColor[2],insetColor[3],enabled and .56 or 1)
        end
    end
    if creator:IsShown() and parentPanel and type(parentPanel.SetBackdropColor)=="function" then
        -- Existing hosting backdrop must not double-darken the preview. Save
        -- its real color for restoring Applicants. Theme.ApplyNew will repaint
        -- it before this hook fires, so refresh our snapshot on theme changes.
        if themeReapplied or not parentBackdropSaved then
            local current=GetPanelBackdrop()
            if current and (current[4]~=0 or not parentBackdropSaved) then
                parentBackdropSaved=current
            end
        end
        if parentBackdropSaved then
            parentPanel:SetBackdropColor(parentBackdropSaved[1],parentBackdropSaved[2],
                parentBackdropSaved[3],0)
        end
    end
    local state=theme.." / transparent="..tostring(enabled)
    if lastVisualState~=state or reason=="creator opened" then
        lastVisualState=state
        Log("TRANSPARENCY",reason.." theme="..theme.." enabled="..tostring(enabled)
            .." Manage backdrop="..(enabled and "0.23" or "1.00")
            .." sections="..(enabled and "0.56" or "1.00")
            .." native hosting backdrop="..(creator:IsShown() and "suppressed" or "unmodified"))
    end
end

local function ShowPartySummary(show)
    local party=ForeverQuickJoinParty
    if type(party)=="table" and type(party.SetSummaryVisible)=="function" then
        local ok,err=pcall(party.SetSummaryVisible,show)
        if not ok then Log("ISOLATION","party summary toggle error: "..Clean(err)) end
    end
end
local function CloseCreator()
    if not creator then return end
    delistArmed=false
    if delistButton then delistButton:SetText("Delist") end
    if not RestoreEditor("creator closed") then
        Notice("Editor restoration is deferred until combat ends; do not manipulate Blizzard listing UI meanwhile.")
    end
    creator:Hide()
    isOpen=false
end
local function OpenCreator()
    if not creator then return end
    if creator:IsShown() then return end -- top navigation always opens Manage Listing
    if Combat() then Notice("Open the creator out of combat.");return end
    HideApplicantUnderlay()
    ShowPartySummary(true) -- preserve the shared ribbon at its original y=117 on both main tabs
    creator:Show()
    ApplyCreatorTransparency("creator opened",true)
    isOpen=true
    delistArmed=false
    if delistButton then delistButton:SetText("Delist") end
    persistentStyleWarning=nil
    if statusText then statusText:SetText("Type in Blizzard's embedded description box; each listing action requires your click.") end
    RefreshCatalog(false)
    selectedIDs={};selectedSet={}
    RenderActivities()
    if friendlyCheck then friendlyCheck:SetChecked(false) end
    SetStyle(2)
    local current=CurrentEntry()
    if current and type(current.activityIDs)=="table" and not Secret(current.activityIDs) then
        local existingIds={}
        for _,id in ipairs(current.activityIDs) do if type(id)=="number" then existingIds[#existingIds+1]=id end end
        if #existingIds>0 then
            local info=TryRead("GetActivityInfoTable",Function("GetActivityInfoTable"),existingIds[1])
            if type(info)=="table" and type(info.categoryID)=="number" then
                for i,c in ipairs(categories) do
                    if c.id==info.categoryID then SetCategory(i,true);break end
                end
            end
            selectedIDs=existingIds
            selectedSet={}
            for _,id in ipairs(existingIds) do selectedSet[id]=true end
            RenderActivities()
        end
        if type(current.generalPlaystyle)=="number" and current.generalPlaystyle~=0 then
            SetStyle(current.generalPlaystyle)
        end
        if friendlyCheck then friendlyCheck:SetChecked(current.newPlayerFriendly==true) end
        Log("ACTIVE","Loaded existing IDs "..IDString(existingIds).." and style="..Clean(current.generalPlaystyle))
        -- CopyActiveEntryInfoToCreationFields is a built-in field initializer;
        -- do not attempt to read or write protected description text.
        if Function("CopyActiveEntryInfoToCreationFields") then
            local ok,err=pcall(C_LFGList.CopyActiveEntryInfoToCreationFields)
            Log("EDITOR","CopyActiveEntryInfoToCreationFields ok="..tostring(ok)..(ok and "" or (" error="..Clean(err))))
        end
    end
    DockEditor()
    Snapshot("creator opened")
end
local function MakeCreator()
    if creator or not parentPanel then return end
    -- Manage Listing is a distinct view. The old applicant content is hidden,
    -- rather than covered by an always-opaque texture. The main theme's
    -- Transparency switch controls the new view in both themes.
    creator=CreateFrame("Frame","ForeverQuickJoinListingCreator",parentPanel,"BackdropTemplate")
    creator:SetPoint("TOPLEFT",parentPanel,"TOPLEFT",0,0)
    creator:SetPoint("BOTTOMRIGHT",parentPanel,"BOTTOMRIGHT",0,0)
    creator:SetFrameLevel(parentPanel:GetFrameLevel()+15)
    creator:EnableMouse(true)
    creator:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=18,
        insets={left=4,right=4,top=4,bottom=4}})
    creator:SetBackdropColor(.035,.047,.066,1)
    -- No extra texture here. It bypassed ForeverQuickJoinTheme's backdrop
    -- transparency and caused the v5 theme-menu regression.
    creator:SetScript("OnHide",function()
        isOpen=false
        delistArmed=false
        if delistButton then delistButton:SetText("Delist") end
        RestoreEditor("Manage Listing view hidden")
        RestoreApplicantUnderlay("Manage Listing view hidden")
        RestoreHostBackdrop("Manage Listing view hidden")
    -- The native ribbon is shared by Find Groups and both hosting subviews.
    -- Do not hide or reposition it when returning to Applicants.
    if parentPanel and parentPanel:IsShown() then ShowPartySummary(true) end
    end)
    Label(creator,"MANAGE LISTING",17,11,487,26,"GameFontNormalLarge")
    -- The shared two-button subnavigation sits ABOVE both Manage and Applicants views.
    activeLabel=Label(creator,"No active listing",18,46,767,24,"GameFontHighlightSmall")

    -- Left column: category, searchable activities, and the active selection.
    Label(creator,"CATEGORY",19,151,180,19,"GameFontNormalSmall")
    -- Native category dropdown; changing category resets activity choices.
    creatorCategoryDropdown=CreateFrame("DropdownButton",nil,creator,"WowStyle1DropdownTemplate")
    creatorCategoryDropdown:SetPoint("TOPLEFT",creator,"TOPLEFT",19,-174)
    creatorCategoryDropdown:SetWidth(368)
    creatorCategoryDropdown:SetDefaultText("Choose category")
    categoryText=creatorCategoryDropdown
    creatorCategoryDropdown:SetupMenu(function(_,root)
        root:SetTag("MENU_QJ_LISTING_CATEGORY")
        for i,item in ipairs(categories) do
            root:CreateRadio(item.name,
                function(id) return selectedCategory==id end,
                function(id)
                    for j,c in ipairs(categories) do
                        if c.id==id then SetCategory(j,true); break end
                    end
                end,item.id)
        end
        if #categories==0 then root:CreateTitle("No categories available") end
    end)
    Label(creator,"FILTER ACTIVITIES",19,215,365,19,"GameFontNormalSmall")
    searchInput=Field(creator,19,236,368,26)
    searchInput:SetMaxLetters(70)
    searchInput:SetScript("OnTextChanged",function()RenderActivities()end)
    activityDropdown=CreateFrame("DropdownButton",nil,creator,"WowStyle1DropdownTemplate")
    activityDropdown:SetPoint("TOPLEFT",creator,"TOPLEFT",19,-273)
    activityDropdown:SetWidth(368)
    activityDropdown:SetDefaultText("Choose activities")
    activityDropdown:SetupMenu(function(_,root)
        root:SetTag("MENU_QJ_LISTING_ACTIVITIES")
        local filtered=FilteredActivities()
        root:CreateTitle("Multiple selections allowed (up to "..Limit()..")")
        if #filtered==0 then root:CreateTitle("No matching activities - change filters") end
        for _,item in ipairs(filtered) do
            local caption=item.name..item.level
            root:CreateCheckbox(caption,
                function(id)return selectedSet[id]==true end,
                function(id) ToggleActivityID(id) end,item.id)
        end
    end)
    allLevelsCheck=CreateFrame("CheckButton",nil,creator,"UICheckButtonTemplate")
    allLevelsCheck:SetPoint("TOPLEFT",creator,"TOPLEFT",19,-314)
    allLevelsCheck:SetSize(24,24)
    allLevelsCheck:SetChecked(showAllLevels)
    Label(creator,"Show all level ranges",47,315,299,22,"GameFontHighlightSmall")
    allLevelsCheck:SetScript("OnClick",function(self)
        showAllLevels=self:GetChecked()==true
        if db then db.showAllLevelRanges=showAllLevels end
        Log("FILTER","Show all level ranges="..tostring(showAllLevels))
        RenderActivities()
    end)
    local selectedBox=Backdrop(creator,16,351,385,218)
    Label(selectedBox,"Selected activities",12,9,350,22,"GameFontNormal")
    selectedLabel=Label(selectedBox,"SELECTED ACTIVITIES (0)\nNone yet",12,39,358,165,"GameFontHighlightSmall")
    selectedLabel:SetJustifyV("TOP")
    Button(creator,"Refresh activities",19,580,176,27,function()RefreshCatalog(true)end)
    Button(creator,"Clear selection",208,580,177,27,function()
        selectedIDs={};selectedSet={};Log("SELECT","all selected activities cleared")
        RenderActivities()
    end)

    -- Right column: playstyle and the ORIGINAL secure Blizzard input widget.
    Label(creator,"PLAYSTYLE",430,151,333,19,"GameFontNormalSmall")
    -- Native playstyle dropdown replaces the temporary arrow buttons.
    creatorStyleDropdown=CreateFrame("DropdownButton",nil,creator,"WowStyle1DropdownTemplate")
    creatorStyleDropdown:SetPoint("TOPLEFT",creator,"TOPLEFT",429,-174)
    creatorStyleDropdown:SetWidth(358)
    creatorStyleDropdown:SetDefaultText("Relaxed")
    playstyleText=creatorStyleDropdown
    creatorStyleDropdown:SetupMenu(function(_,root)
        root:SetTag("MENU_QJ_LISTING_STYLE")
        for _,item in ipairs(StyleValues()) do
            root:CreateRadio(item.name,
                function(id) return selectedStyle==id end,
                function(id) SetStyle(id) end,item.id)
        end
    end)
    friendlyCheck=CreateFrame("CheckButton",nil,creator,"UICheckButtonTemplate")
    friendlyCheck:SetPoint("TOPLEFT",creator,"TOPLEFT",431,-215)
    friendlyCheck:SetSize(24,24)
    Label(creator,"New-player friendly",461,216,315,24,"GameFontHighlightSmall")

    Label(creator,"DESCRIPTION  (BLIZZARD'S ORIGINAL EDITOR)",431,250,354,23,"GameFontNormalSmall")
    editorSlot=Backdrop(creator,429,276,360,132)
    Label(editorSlot,"Click in the field below and type normally:",10,7,329,21,"GameFontHighlightSmall")
    -- The native scroll frame is dynamically sized in SizeDockedEditor().
    -- Critically, the nested EditBox also needs its width updated; otherwise
    -- it keeps its old width from UIPanelInputScrollFrame_OnLoad and visually
    -- protrudes past the slot even though the ScrollFrame itself is docked.
    Label(creator,"The description is protected; QuickJoin never reads, pastes,",431,413,345,17,"GameFontHighlightSmall")
    Label(creator,"or programmatically edits its contents.",431,431,345,17,"GameFontHighlightSmall")
    Button(creator,"Refit Editor",431,456,153,28,function()
        if not editorState then DockEditor()
        else
            local ok,success=pcall(SizeDockedEditor)
            if not ok or not success then
                Notice("Editor re-layout failed; close and reopen or /reload out of combat.")
            end
        end
    end)
    Label(creator,"Create and Update submit immediately on click.",432,497,360,26,"GameFontHighlightSmall")
    createButton=Button(creator,"Create",432,531,109,32,CreateOnClick)
    updateButton=Button(creator,"Update",548,531,109,32,UpdateOnClick)
    delistButton=Button(creator,"Delist",666,531,120,32,DelistOnClick)
    Label(creator,"Update checks playstyle after posting; Delist needs two clicks.",431,570,355,32,"GameFontHighlightSmall")
    Label(creator,"Clear old description manually before a new listing.",431,603,355,25,"GameFontHighlightSmall")

    statusText=Label(creator,"Ready. Select activities and type a description.",18,634,770,33,"GameFontHighlightSmall")
    Button(creator,"Export Listing Log",20,671,170,28,ExportLog)
    Button(creator,"Verify Listing",201,671,142,28,function()Snapshot("manual verify")end)
    creator:Hide()
end

-- Selection state belongs to the actual main navigation, not the disabled
-- button's native texture (Modern mode deliberately hides native art).
-- Parent these lightweight indicators to the root window so theme skinning
-- cannot turn them off. They NEVER intercept mouse input.
local function MakeTabIndicator(window,button)
    local holder=CreateFrame("Frame",nil,window)
    holder:SetFrameLevel(button:GetFrameLevel()+5)
    holder:SetPoint("TOPLEFT",button,"TOPLEFT",0,0)
    holder:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",0,0)
    holder:EnableMouse(false)
    local tint=holder:CreateTexture(nil,"ARTWORK")
    tint:SetAllPoints(holder)
    local underline=holder:CreateTexture(nil,"OVERLAY")
    underline:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",5,3)
    underline:SetPoint("BOTTOMRIGHT",holder,"BOTTOMRIGHT",-5,3)
    underline:SetHeight(3)
    holder:Hide()
    return {holder=holder,tint=tint,underline=underline}
end
local function RefreshMainTabSelection(reason)
    local theme=CurrentTheme()
    local r,g,b=1,.77,.19 -- Forever gold
    if theme=="Modern" then r,g,b=.37,.72,1 end -- Modern blue
    for tab,ind in pairs(tabIndicators) do
        ind.tint:SetColorTexture(r,g,b,.13)
        ind.underline:SetColorTexture(r,g,b,1)
        if tab==mainSelected then ind.holder:Show() else ind.holder:Hide() end
    end
end
local function SelectMainTab(tab)
    if tab~="find" and tab~="listing" then return end
    mainSelected=tab
    RefreshMainTabSelection("navigation")
end

-- This is a VIEW onto the *existing* advanced exclusion filter; the menu
-- invokes the same old checkbox handlers so results refresh normally and
-- Advanced Filters continues to reflect any changes. Never synthesize a
-- protected group-finder action.
local PLAYSTYLE_FILTERS={
    {1,"Learning"},{2,"Relaxed"},{3,"Competitive"},{4,"Carry Offered"}
}
local function FindAdvancedStyleChecks()
    if finderPlaystyleChecks then return finderPlaystyleChecks end
    local advanced=_G.ForeverQuickJoinAdvancedFilters
    if not advanced or type(advanced.GetChildren)~="function" then return nil end
    local found={}
    for _,child in ipairs({advanced:GetChildren()}) do
        if type(child.GetObjectType)=="function" and child:GetObjectType()=="CheckButton"
            and type(child.GetRegions)=="function" then
            for _,label in ipairs({child:GetRegions()}) do
                if type(label.GetObjectType)=="function" and label:GetObjectType()=="FontString"
                    and type(label.GetText)=="function" then
                    local caption=label:GetText()
                    for _,p in ipairs(PLAYSTYLE_FILTERS) do
                        if caption==p[2] then found[p[1]]=child end
                    end
                end
            end
        end
    end
    local count=0
    for _ in pairs(found) do count=count+1 end
    if count~=4 then
        Log("FINDER","Playstyle filter checkbox discovery incomplete ("..count.."/4); dropdown will not edit native filters")
        return nil
    end
    finderPlaystyleChecks=found
    return found
end
local function CurrentExcludedStyles()
    local d=ForeverQuickJoinDB
    local advanced=type(d)=="table" and d.advanced
    local t=type(advanced)=="table" and advanced.excludedPlaystyles
    return type(t)=="table" and t or {}
end
local function UpdateFinderStyleCaption()
    if not finderPlaystyleDropdown then return end
    local excluded=CurrentExcludedStyles()
    local n=0
    for _,p in ipairs(PLAYSTYLE_FILTERS) do if excluded[p[1]]==true then n=n+1 end end
    local caption=n==0 and "Playstyle: All" or ("Playstyle: Exclude "..n)
    if type(finderPlaystyleDropdown.OverrideText)=="function" then
        finderPlaystyleDropdown:OverrideText(caption)
    elseif type(finderPlaystyleDropdown.SetDefaultText)=="function" then
        finderPlaystyleDropdown:SetDefaultText(caption)
    end
end
local function ChangePlaystyleExclusion(id,excluded)
    local checks=FindAdvancedStyleChecks()
    local native=checks and checks[id]
    if not native then
        Notice("Native playstyle filters are unavailable; use Advanced Filters instead.")
        return
    end
    local current=CurrentExcludedStyles()[id]==true
    if current==excluded then return end
    local fn=native:GetScript("OnClick")
    if type(fn)~="function" then
        Notice("Native playstyle handler unavailable; use Advanced Filters.")
        return
    end
    -- Pure Lua checkbox callback; no :Click() or protected Blizzard buttons.
    native:SetChecked(excluded)
    fn(native)
    Log("FINDER","Playstyle exclusion id="..id.." hidden="..tostring(excluded))
    UpdateFinderStyleCaption()
end
local function InstallFinderDropdown()
    if finderPlaystyleDropdown or not finderContent then return end
    -- Category is ALREADY a native dropdown in Find Groups. The second row
    -- has room for Playstyle where the old explanatory hint used to sit.
    if type(finderContent.GetRegions)=="function" then
        for _,region in ipairs({finderContent:GetRegions()}) do
            if type(region.GetObjectType)=="function" and region:GetObjectType()=="FontString"
                and type(region.GetText)=="function" then
                local caption=region:GetText()
                if type(caption)=="string" and caption:find("Search retrieves groups on click",1,true) then
                    finderHelpLabel=region
                    region:Hide()
                    break
                end
            end
        end
    end
    finderPlaystyleDropdown=CreateFrame("DropdownButton",nil,finderContent,"WowStyle1DropdownTemplate")
    finderPlaystyleDropdown:SetPoint("TOPLEFT",finderContent,"TOPLEFT",275,-87)
    finderPlaystyleDropdown:SetWidth(202)
    finderPlaystyleDropdown:SetDefaultText("Playstyle: All")
    finderPlaystyleDropdown:SetupMenu(function(_,menu)
        menu:SetTag("MENU_QJ_LISTING_FIND_STYLE")
        menu:CreateTitle("Exclude playstyles")
        menu:CreateTitle("Unspecified playstyles remain visible")
        for _,p in ipairs(PLAYSTYLE_FILTERS) do
            local id,label=p[1],p[2]
            menu:CreateCheckbox(label,
                function(pid) return CurrentExcludedStyles()[pid]==true end,
                function(pid) ChangePlaystyleExclusion(pid,not (CurrentExcludedStyles()[pid]==true)) end,id)
        end
        menu:CreateDivider()
        menu:CreateButton("Clear playstyle exclusions",function()
            for _,p in ipairs(PLAYSTYLE_FILTERS) do
                ChangePlaystyleExclusion(p[1],false)
            end
            UpdateFinderStyleCaption()
        end)
    end)
    finderPlaystyleDropdown:HookScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:AddLine("Playstyle filters")
        GameTooltip:AddLine("Hide selected styles from Find Groups. Uses the same exclusions as Advanced Filters; unknown playstyles remain visible.",1,1,1,true)
        GameTooltip:Show()
    end)
    finderPlaystyleDropdown:HookScript("OnLeave",function()if GameTooltip then GameTooltip:Hide() end end)
    UpdateFinderStyleCaption()
    -- Existing Advanced checkboxes and Clear All Filters remain authoritative.
    local checks=FindAdvancedStyleChecks()
    if checks then
        for _,native in pairs(checks) do
            if type(native.HookScript)=="function" then
                native:HookScript("OnClick",UpdateFinderStyleCaption)
            end
        end
    end
    Log("FINDER","Find Groups category uses existing dropdown; playstyle exclusion dropdown installed")
end

-- The outgoing-application panel is a separate native view. Keep its data
-- and conversation controls intact; only add a safe navigation button.
local function InstallApplicationsBackButton()
    if applicationBackButton then return end
    local applications=_G.ForeverQuickJoinApplicationsPanel
    if not applications then return end
    applicationBackButton=Button(applications,"Back to Listings",648,12,152,27,function()
        if ForeverQuickJoinHost and type(ForeverQuickJoinHost.OpenFind)=="function" then
            ForeverQuickJoinHost.OpenFind() -- restores finder, hides outgoing applications
            SelectMainTab("find")
            UpdateFinderStyleCaption()
            Log("NAV","My Applications -> Find Groups listings")
        end
    end)
    -- The original reply-notification toggle occupies the same upper-right
    -- area. Relocate only that checkbutton (and its anchored text), not its
    -- OnClick or saved preference.
    for _,child in ipairs({applications:GetChildren()}) do
        if child~=applicationBackButton and type(child.GetObjectType)=="function"
            and child:GetObjectType()=="CheckButton" then
            child:ClearAllPoints()
            child:SetPoint("TOPRIGHT",applications,"TOPRIGHT",-330,-17)
            break
        end
    end
    Log("NAV","My Applications has Back to Listings button")
end

-- The Party Role Manager is a modal. Its background must stay opaque even
-- when the surrounding QuickJoin window has transparency enabled. The main
-- theme traversal intentionally fades ordinary frame backgrounds; restore
-- only this modal's background alpha after theme updates, never changing the
-- frame's overall alpha (which would fade labels and controls).
local function EnsureSolidRoleManager(reason)
    local modal=_G.ForeverQuickJoinRoleManager
    if not modal or type(modal.SetBackdropColor)~="function" then return end
    local theme=CurrentTheme()
    if theme=="Modern" then
        modal:SetBackdropColor(.049,.057,.074,1)
    else
        modal:SetBackdropColor(.035,.045,.065,1)
    end
    -- The outer opaque backing blocks all Finder/Applicants text, including
    -- the party summary at higher levels underneath it.
    if reason=="opened" or reason=="installed" then
        Log("ROLE","solid manager background applied ("..theme..", alpha=1); "..reason)
    end
end
local function InstallRoleManagerOpacity()
    local modal=_G.ForeverQuickJoinRoleManager
    if not modal then return end
    if not roleManagerOpacityHooked then
        roleManagerOpacityHooked=true
        modal:HookScript("OnShow",function()EnsureSolidRoleManager("opened")end)
    end
    EnsureSolidRoleManager("installed")
end

local function FindCaptionButton(parent,caption)
    if not parent or type(parent.GetChildren)~="function" then return nil end
    for _,child in ipairs({parent:GetChildren()}) do
        if type(child.GetText)=="function" then
            local ok,value=pcall(child.GetText,child)
            if ok and type(value)=="string" and (value==caption or value:match("^"..caption.." %(%")) then
                return child
            end
        end
    end
end
-- Test-only fixed-size override. The base addon creates an unnamed 18x18
-- resize button in the window's bottom-right corner. Identify that specific
-- control by its exact geometry/anchor instead of disabling unrelated buttons.
-- Do not interfere with title-bar moving, theme alpha, protected listing
-- fields or other addons. The original size preference is normalized to 1.
-- Align the three main FINDER actions to exactly the same right edge.
-- The native role ribbon is attached directly to the main window at x=25,
-- y=117 and 789x76; its Change Roles button is anchored INSIDE the ribbon.
-- Avoid moving the ribbon or changing any of its behavior.
local FINDER_ACTION_LEFT=635
local FINDER_ACTION_WIDTH=170
local FINDER_ROLE_LOCAL_X=610 -- global x=25+610=635
local FINDER_APPLICATIONS_Y=205 -- ribbon ends at 117+76=193; 12px gap

local function FindFinderAction(parent,exact,prefix)
    if not parent or type(parent.GetChildren)~="function" then return nil end
    for _,child in ipairs({parent:GetChildren()}) do
        if type(child.GetObjectType)=="function" and child:GetObjectType()=="Button"
            and type(child.GetText)=="function" then
            local ok,caption=pcall(child.GetText,child)
            if ok and type(caption)=="string" and (caption==exact
                or (prefix and caption:find(prefix,1,true)==1)) then
                return child
            end
        end
    end
end

local function FindRoleRibbonAction(window)
    if not window or type(window.GetChildren)~="function" then return nil,nil end
    for _,child in ipairs({window:GetChildren()}) do
        local roleButton=FindFinderAction(child,"Change Roles")
        if roleButton then
            -- Confirm this is the permanent 789x76 ribbon before changing it.
            -- Never reposition buttons from the separate role-manager modal.
            local w,h=0,0
            if type(child.GetSize)=="function" then w,h=child:GetSize() end
            if w==789 and h==76 then return child,roleButton end
        end
    end
end

local function HideObsoleteFinderHint()
    if not finderContent or type(finderContent.GetRegions)~="function" then return end
    for _,region in ipairs({finderContent:GetRegions()}) do
        if type(region.GetObjectType)=="function" and region:GetObjectType()=="FontString"
            and type(region.GetText)=="function" then
            local txt=region:GetText()
            if type(txt)=="string" and txt:find("Click a row to view members",1,true) then
                region:Hide() -- compatibility if an older theme module injects it
            end
        end
    end
end
local function AlignFinderActions(window)
    HideObsoleteFinderHint()
    if not finderContent or not topApplicationsTab then return end
    -- Main QuickJoin calls Host.Attach BEFORE Party.Attach on initial window
    -- creation. The Change Roles button does not exist during our initial
    -- Install hook. Anchor My Applications *first and unconditionally*, so
    -- failure to find the party ribbon can never leave this action invisible.
    topApplicationsTab:ClearAllPoints()
    topApplicationsTab:SetPoint("TOPLEFT",finderContent,"TOPLEFT",FINDER_ACTION_LEFT,-FINDER_APPLICATIONS_Y)
    topApplicationsTab:SetSize(FINDER_ACTION_WIDTH,26)
    -- Keep the action above native finder content (e.g. result headers), but
    -- below the permanent role ribbon. Reparenting retains no dependable
    -- frame level across Forever clients.
    if type(topApplicationsTab.SetFrameLevel)=="function"
        and type(finderContent.GetFrameLevel)=="function" then
        topApplicationsTab:SetFrameLevel(finderContent:GetFrameLevel()+8)
    end
    if finderAlignmentInstalled then return end
    local advanced=FindFinderAction(finderContent,"Advanced Filters >>","Advanced Filters")
    local ribbon,changeRoles=FindRoleRibbonAction(window)
    if not advanced or not changeRoles then
        Log("ALIGN","My Applications positioned; waiting for party summary to finish initializing")
        return
    end
    -- Align left and right edges once all three native controls are ready.
    advanced:ClearAllPoints()
    advanced:SetPoint("TOPLEFT",finderContent,"TOPLEFT",FINDER_ACTION_LEFT,-89)
    advanced:SetSize(FINDER_ACTION_WIDTH,26)
    changeRoles:ClearAllPoints()
    changeRoles:SetPoint("TOPLEFT",ribbon,"TOPLEFT",FINDER_ROLE_LOCAL_X,-22)
    changeRoles:SetSize(FINDER_ACTION_WIDTH,35)
    -- The previous right-side hint sits at y=198-215, directly behind My
    -- Applications in the improved row. Results remain independently labeled.
    if type(finderContent.GetRegions)=="function" then
        for _,region in ipairs({finderContent:GetRegions()}) do
            if type(region.GetObjectType)=="function"
                and region:GetObjectType()=="FontString"
                and type(region.GetText)=="function"
                and region:GetText()=="Click a row to view members" then
                region:Hide()
                break
            end
        end
    end
    finderAlignmentInstalled=true
    Log("ALIGN","Find Groups controls: Advanced, Change Roles, My Applications x=635 width=170 right=805; role ribbon bottom y=193, My Applications top y=205 gap=12")
end

local function Install()
    if initialized then return end
    local panel=_G.ForeverQuickJoinHostingPanel
    if not panel then return end
    parentPanel=panel
    local window=panel:GetParent()
    if not window then return end
    topFindTab=FindCaptionButton(window,"Find Groups")
    topHostingTab=FindCaptionButton(window,"List Group")
    topApplicationsTab=FindCaptionButton(window,"Applications") or FindCaptionButton(window,"Apps")
    finderContent=_G.ForeverQuickJoinFindContent
    existingButton=FindCaptionButton(panel,"Open Blizzard Listing")
    if not topFindTab or not topHostingTab or not topApplicationsTab or not existingButton or not finderContent then
        Log("INSTALL","Missing native navigation controls; no partial UI patch applied")
        return
    end
    initialized=true
    if type(window.SetSize)=="function" then window:SetSize(840,785) end
    if type(window.SetScale)=="function" then window:SetScale(1) end
    -- Reassert fixed size when reopened, but leave the original title-drag
    -- position and all other Open/Hide behavior entirely unchanged.
    window:HookScript("OnShow",function(self)
        if type(self.SetSize)=="function" then self:SetSize(840,785) end
        if type(self.SetScale)=="function" then self:SetScale(1) end
    end)
    -- This companion only moves/relabels the real native buttons. Switching it
    -- off and /reload restores the installed ForeverQuickJoin unchanged.
    topHostingTab:SetText("Create Listing")
    topHostingTab:SetWidth(136)
    tabIndicators.find=MakeTabIndicator(window,topFindTab)
    tabIndicators.listing=MakeTabIndicator(window,topHostingTab)
    InstallFinderDropdown()
    InstallApplicationsBackButton()
    InstallRoleManagerOpacity()
    SelectMainTab("find")
    -- The original My Applications action now belongs to finder content and
    -- disappears when Find Groups is not visible. Retain its existing OnClick.
    topApplicationsTab:SetParent(finderContent)
    topApplicationsTab:ClearAllPoints()
    topApplicationsTab:SetText("My Applications")
    AlignFinderActions(window)
    -- Keep the two hosting subnav buttons consistently above the Manage view
    -- (which is a separate, theme-aware sibling view) and original applicant content.
    navOverlay=CreateFrame("Frame",nil,panel)
    navOverlay:SetAllPoints(panel)
    navOverlay:SetFrameLevel(panel:GetFrameLevel()+25)
    navOverlay:EnableMouse(false)
    originalClick=existingButton:GetScript("OnClick")
    existingButton:SetParent(navOverlay)
    existingButton:ClearAllPoints()
    existingButton:SetPoint("TOPLEFT",navOverlay,"TOPLEFT",505,-11)
    existingButton:SetSize(134,27)
    existingButton:SetText("Manage Listing")
    existingButton:SetScript("OnClick",OpenCreator)
    applicantsNav=Button(navOverlay,"Applicants",649,11,135,27,CloseCreator)
    MakeCreator()
    ApplyCreatorTransparency("preview initialized",false)
    if type(hooksecurefunc)=="function" then
        if type(ForeverQuickJoinTheme)=="table"
            and type(ForeverQuickJoinTheme.ApplyNew)=="function" then
            hooksecurefunc(ForeverQuickJoinTheme,"ApplyNew",function()
                -- Main theme applies first, then update the preview backgrounds
                -- and suppress the now-repainted native host backdrop again.
                ApplyCreatorTransparency("theme menu changed",true)
                RefreshMainTabSelection("theme menu changed")
                EnsureSolidRoleManager("theme switched")
            end)
        else
            Log("TRANSPARENCY","Theme.ApplyNew hook unavailable; open / close refresh remains supported")
        end
        -- The main tab calls the original Host.OpenList. After it completes,
        -- open Manage as the default (not the applicant inbox).
        hooksecurefunc(ForeverQuickJoinHost,"OpenList",function()
            OpenCreator()
            SelectMainTab("listing")
        end)
        hooksecurefunc(ForeverQuickJoinHost,"OpenFind",function()
            SelectMainTab("find")
            UpdateFinderStyleCaption()
            -- Reassert the My Applications placement if a native tab or
            -- theme operation changed frame levels after initialization.
            AlignFinderActions(window)
        end)
        hooksecurefunc(ForeverQuickJoinHost,"OpenApplications",function()
            -- My Applications belongs logically to Find Groups, not Hosting.
            SelectMainTab("find")
            InstallApplicationsBackButton()
        end)
        if type(ForeverQuickJoinApplications)=="table"
            and type(ForeverQuickJoinApplications.Attach)=="function" then
            hooksecurefunc(ForeverQuickJoinApplications,"Attach",InstallApplicationsBackButton)
        end
        if type(ForeverQuickJoinParty)=="table"
            and type(ForeverQuickJoinParty.Attach)=="function" then
            hooksecurefunc(ForeverQuickJoinParty,"Attach",function()
                InstallRoleManagerOpacity()
                -- Party.Attach is later than Host.Attach, so the real role
                -- summary and Change Roles button now exist.
                AlignFinderActions(window)
            end)
        end
        -- Retain the original unread count while using a clearer finder label.
        hooksecurefunc(ForeverQuickJoinHost,"SetApplicationCount",function(_,unread)
            if not topApplicationsTab then return end
            local n=type(unread)=="number" and unread or 0
            topApplicationsTab:SetText(n>0 and ("My Applications ("..n..")") or "My Applications")
        end)
    end
    panel:HookScript("OnHide",function()
        if creator and creator:IsShown() then creator:Hide() end
        RestoreEditor("hosting area hidden")
        RestoreApplicantUnderlay("hosting area hidden")
        RestoreHostBackdrop("hosting area hidden")
    end)
    Log("READY","Integrated listing creator ready: native editor, multi-activity listings, applicants, fixed window and restored navigation")
end
local watcher=CreateFrame("Frame")
for _,ev in ipairs({"PLAYER_LOGIN","PLAYER_REGEN_ENABLED","LFG_LIST_ACTIVE_ENTRY_UPDATE",
    "LFG_LIST_AVAILABILITY_UPDATE","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN"}) do
    watcher:RegisterEvent(ev)
end
watcher:SetScript("OnEvent",function(self,event,...)
    if event=="PLAYER_LOGIN" then
        db=type(ForeverQuickJoinListingDB)=="table" and ForeverQuickJoinListingDB or {}
        ForeverQuickJoinListingDB=db
        showAllLevels=db.showAllLevelRanges==true
        Log("LOGIN","integrated listing creator enabled; version 0.9.0")
        Install()
    elseif event=="PLAYER_REGEN_ENABLED" then
        if restorePending then RestoreEditor("combat ended") end
    elseif event=="LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        local created=...
        Log("EVENT","LFG_LIST_ACTIVE_ENTRY_UPDATE created="..Clean(created))
        if creator and creator:IsShown() then Snapshot("active entry event") end
    elseif event=="LFG_LIST_AVAILABILITY_UPDATE" then
        if creator and creator:IsShown() then
            Log("EVENT","activity metadata availability updated")
            if #activities==0 then RefreshCatalog(false) end -- read-only metadata refresh
        end
    elseif event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN" then
        local name,detail=...
        if name==addonName or name=="ForeverQuickJoin" then
            Log("SECURITY",event.." addon="..Clean(name).." detail="..Clean(detail))
            if creator and creator:IsShown() then Notice("Client blocked an action; export the log and use Blizzard's native Group Finder outside QuickJoin.") end
        end
    end
end)
-- Main ForeverQuickJoin creates its UI lazily (normally on first /qj). Hook
-- the public Attach method, but do not wrap protected listing functions.
if type(ForeverQuickJoinHost)=="table" and type(ForeverQuickJoinHost.Attach)=="function"
    and type(hooksecurefunc)=="function" then
    hooksecurefunc(ForeverQuickJoinHost,"Attach",Install)
end
SLASH_FQJLISTINGDEBUG1="/qjlisting"
SlashCmdList.FQJLISTINGDEBUG=function(arg)
    if not initialized then Install() end
    if arg=="export" then ExportLog()
    elseif arg=="verify" then Snapshot("slash command")
    elseif arg=="restore" then RestoreEditor("slash command")
    else
        if ForeverQuickJoinHost and type(ForeverQuickJoinHost.OpenList)=="function" then
            ForeverQuickJoinHost.OpenList()
            Install()
            if not initialized then Notice("Run /qj once to initialize the QuickJoin window, then use /qjlisting.") end
        else
            Notice("Open ForeverQuickJoin (/qj) first, then select Create Listing.")
        end
    end
end
