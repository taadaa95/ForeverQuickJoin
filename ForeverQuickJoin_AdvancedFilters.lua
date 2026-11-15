-- Forever QuickJoin: role composition controls for 0.9.9.
-- Integrated role filters are registered after the existing QuickJoin files.
-- No protected searches, whispers, or invites are initiated here.
local M = {}
ForeverQuickJoinAdvancedRoles = M

local panel, win, seen = nil, nil, setmetatable({}, {__mode="k"})
local attached, tick, busy = false, 0, false
local buttons = {}
local newLabels = {}
local rolePairs = {
    {"needTank","hasTank"}, {"needHealer","hasHealer"}, {"needDps","hasDps"},
}
local translatedOr = {
    enUS = "Healer and/or Tank",
    frFR = "Soigneur et/ou tank",
    deDE = "Heiler und/oder Tank",
    esES = "Sanador y/o tanque",
    esMX = "Sanador y/o tanque",
    ptBR = "Curador e/ou tanque",
    ruRU = "Лекарь и/или танк",
    zhCN = "治疗和/或坦克",
    zhTW = "治療和／或坦克",
    koKR = "힐러 및/또는 탱커",
}
local function DB()
    if type(ForeverQuickJoinDB)~="table" then ForeverQuickJoinDB={} end
    local db=ForeverQuickJoinDB
    if type(db.filters)~="table" then db.filters={} end
    return db
end
local function Effective()
    local locale=ForeverQuickJoinLocale
    if locale and type(locale.Current)=="function" then
        local _,v=locale.Current()
        if type(v)=="string" and translatedOr[v] then return v end
    end
    return "enUS"
end
local function IsIgnore()
    local d=DB()
    return type(d.advanced)=="table" and d.advanced.ignoreTeamComposition==true
end
local function Label(parent,txt,x,y,w)
    local font=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    font:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    font:SetSize(w,22)
    font:SetJustifyH("LEFT")
    font:SetText(txt)
    return font
end
local function CPoint(frame)
    if not frame or type(frame.GetPoint)~="function" then return nil,nil end
    local _,_,_,x,y=frame:GetPoint(1)
    return x,y
end
local function Move(frame,x,y)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y)
end
local function VisibleRows()
    local found,visited={},{}
    local root=_G.ForeverQuickJoinFindContent
    local n=0
    local function Visit(f)
        if not f or visited[f] or n>1500 then return end
        visited[f]=true; n=n+1
        if f.resultID~=nil and f.whisper and f.composition then
            found[#found+1]=f
        end
        if type(f.GetChildren)=="function" then
            for _,ch in ipairs({f:GetChildren()}) do Visit(ch) end
        end
    end
    Visit(root)
    return found
end
local function Counts(resultID)
    if not C_LFGList or type(C_LFGList.GetSearchResultMemberCounts)~="function" then return nil end
    local ok,counts=pcall(C_LFGList.GetSearchResultMemberCounts,resultID)
    if not ok or type(counts)~="table" then return nil end
    local result={}
    for _,key in ipairs({"TANK","HEALER","DAMAGER"}) do
        local value=counts[key]
        if type(value)~="number" or value<0 then return nil end
        result[key]=value
    end
    return result
end
function M.PassesExtra(resultID,filters,memberCounts)
    filters=filters or DB().filters
    if filters.hasDps~=true and filters.hasTankOrHealer~=true then return true end
    local counts=memberCounts or Counts(resultID)
    if not counts then return false end
    if filters.hasDps and not (counts.DAMAGER and counts.DAMAGER>0) then return false end
    -- Inclusive OR: one healer, one tank, or both satisfy the checkbox.
    if filters.hasTankOrHealer
        and not ((counts.TANK and counts.TANK>0) or (counts.HEALER and counts.HEALER>0)) then
        return false
    end
    return true
end
local function CheckListingRow(row)
    if not row or not row.resultID then return end
    if IsIgnore() then return end
    local f=DB().filters
    if f.hasDps~=true and f.hasTankOrHealer~=true then return end
    if not M.PassesExtra(row.resultID,f) then
        row.qjRoleFilterHidden=true
        row:Hide()
    else
        row.qjRoleFilterHidden=nil
    end
end
local function AttachRowHooks()
    local rows=VisibleRows()
    for _,row in ipairs(rows) do
        if not seen[row] and type(row.HookScript)=="function" then
            seen[row]=true
            row:HookScript("OnShow",function(self) CheckListingRow(self) end)
        end
        if row.IsShown and row:IsShown() then CheckListingRow(row) end
    end
end
local function Rebuild()
    if busy then return end
    busy=true
    if win and type(win.QuickJoinApplyRoleFilters)=="function" then
        -- Apply all role filters before pagination; no new server search.
        win.QuickJoinApplyRoleFilters()
    elseif win and type(win.QuickJoinUpdateSent)=="function" then
        -- Compatibility with older core versions.
        win.QuickJoinUpdateSent()
    end
    AttachRowHooks()
    busy=false
end
local function ResolveConflicts(changed)
    local d=DB()
    local f=d.filters
    -- These preferences represent alternate team-composition goals, not
    -- simultaneous requirements for one role. The newly selected wins.
    for _,pair in ipairs(rolePairs) do
        local need,has=pair[1],pair[2]
        if f[need]==true and f[has]==true then
            if changed==has then f[need]=false
            else f[has]=false end
        end
    end
end
local function UpdateControls()
    local f=DB().filters
    local ignored=IsIgnore()
    for _,pair in ipairs(rolePairs) do
        local need,has=pair[1],pair[2]
        local n,h=buttons[need],buttons[has]
        if n then
            n:SetChecked(f[need]==true)
            n:SetEnabled(not ignored and f[has]~=true)
            n:SetAlpha((ignored or f[has]==true) and .42 or 1)
        end
        if h then
            h:SetChecked(f[has]==true)
            h:SetEnabled(not ignored and f[need]~=true)
            h:SetAlpha((ignored or f[need]==true) and .42 or 1)
        end
    end
    local composite=buttons.hasTankOrHealer
    if composite then
        composite:SetChecked(f.hasTankOrHealer==true)
        composite:SetEnabled(not ignored)
        composite:SetAlpha(ignored and .42 or 1)
    end
    if newLabels.hasTankOrHealer then
        newLabels.hasTankOrHealer:SetText(translatedOr[Effective()] or translatedOr.enUS)
    end
end
function M.Change(field,value)
    local f=DB().filters
    f[field]=value==true
    ResolveConflicts(value and field or nil)
    UpdateControls()
    Rebuild()
end
local function AttachExisting(button,field)
    if not button or seen[button] then return end
    buttons[field]=button
    seen[button]=true
    if type(button.HookScript)=="function" then
        button:HookScript("OnClick",function(self)
            local f=DB().filters
            -- Main QuickJoin owns this button and has already applied its
            -- saved state when its OnClick handler runs.
            f[field]=self:GetChecked()==true
            ResolveConflicts(f[field] and field or nil)
            UpdateControls()
            Rebuild()
        end)
    end
end
local function MapExistingButtons()
    if not panel then return end
    local lookup={
        ["15:-104"]="needTank",["128:-104"]="needHealer",
        ["249:-104"]="needDps",["15:-161"]="hasTank",
        ["128:-161"]="hasHealer",
    }
    for _,child in ipairs({panel:GetChildren()}) do
        if type(child.GetObjectType)=="function" and child:GetObjectType()=="CheckButton" then
            local x,y=CPoint(child)
            local key=(x and math.floor(x+.5) or 0)..":"..(y and math.floor(y+.5) or 0)
            if lookup[key] then AttachExisting(child,lookup[key]) end
        end
    end
end
local function CreateNew(field,x,y,title,w)
    local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
    b:SetSize(22,22);Move(b,x,y)
    local label=Label(b,title,26,-2,w)
    b:SetScript("OnClick",function(self) M.Change(field,self:GetChecked()) end)
    buttons[field]=b
    newLabels[field]=label
    return b
end
local function MoveExistingLayout()
    -- Make a line for "Healer and/or Tank" without overlapping the existing
    -- composition, exclusion, playstyle, or size controls.
    for _,child in ipairs({panel:GetChildren()}) do
        local x,y=CPoint(child)
        if x and y then
            if math.abs(x-14)<1 and math.abs(y+196)<1 then
                Move(child,14,-213)
            elseif y<=-261 and y>=-370 and
                (math.abs(x-15)<1 or math.abs(x-184)<1)
                and child.GetObjectType and child:GetObjectType()=="CheckButton" then
                local row=math.floor((-y-261)/27+.5)
                Move(child,x,-275-row*24)
            elseif y<=-455 and y>=-488
                and (math.abs(x-15)<1 or math.abs(x-184)<1)
                and child.GetObjectType and child:GetObjectType()=="CheckButton" then
                local row=math.floor((-y-455)/29+.5)
                Move(child,x,-463-row*24)
            end
        end
    end
    if type(panel.GetRegions)=="function" then
        for _,font in ipairs({panel:GetRegions()}) do
            if font and type(font.GetObjectType)=="function"
                and font:GetObjectType()=="FontString" then
                local x,y=CPoint(font)
                if x and y then
                    if math.abs(y+239)<1 then Move(font,x,-250)
                    elseif math.abs(y+394)<1 then
                        Move(font,x,-403)
                        font:SetHeight(30)
                    elseif math.abs(y+429)<1 then Move(font,x,-438) end
                end
            end
        end
    end
end
function M.Attach()
    panel=_G.ForeverQuickJoinAdvancedFilters
    win=_G.ForeverQuickJoinWindow
    if not panel or not win then return false end
    if attached then return true end
    MapExistingButtons()
    if not buttons.needTank or not buttons.hasTank or not buttons.hasHealer
        or not buttons.needHealer or not buttons.needDps then return false end
    MoveExistingLayout()
    CreateNew("hasDps",249,-161,"DPS",74)
    CreateNew("hasTankOrHealer",15,-185,translatedOr[Effective()],300)
    ResolveConflicts()
    UpdateControls()
    if type(win.HookScript)=="function" then
        win:HookScript("OnShow",function()
            UpdateControls()
            AttachRowHooks()
        end)
    end
    if ForeverQuickJoinLocale and type(ForeverQuickJoinLocale.Select)=="function"
        and type(hooksecurefunc)=="function" then
        hooksecurefunc(ForeverQuickJoinLocale,"Select",function() UpdateControls() end)
    end
    attached=true
    AttachRowHooks()
    return true
end
local updater=CreateFrame("Frame")
updater:RegisterEvent("PLAYER_LOGIN")
updater:SetScript("OnEvent",function() M.Attach() end)
updater:SetScript("OnUpdate",function(_,dt)
    tick=tick+(type(dt)=="number" and dt or 0)
    if tick<.4 then return end
    tick=0
    if not attached then M.Attach() return end
    if not win or (win.IsShown and not win:IsShown()) then return end
    UpdateControls()
    AttachRowHooks()
end)
