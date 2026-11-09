-- Forever QuickJoin 0.7.0: reversible, in-session UI themes.
-- Only QuickJoin-owned frames are styled; the Blizzard Group Finder is untouched.
local Theme = {}
local unpack = table.unpack or unpack
ForeverQuickJoinTheme = Theme

local root, advanced, resultRows
local active = "Forever"
local baseBackdrops = setmetatable({}, {__mode = "k"})
local baseFonts = setmetatable({}, {__mode = "k"})
local baseTextureAlphas = setmetatable({}, {__mode = "k"})
local buttonOverlays = setmetatable({}, {__mode = "k"})
local fontColors = setmetatable({}, {__mode = "k"})
local accent = {0.36, 0.80, 0.80}

local function SafeCall(object, method, ...)
    if object and type(object[method]) == "function" then
        local ok, a,b,c,d = pcall(object[method], object, ...)
        if ok then return a,b,c,d end
    end
end

local function Color(frame, r,g,b,a)
    SafeCall(frame, "SetBackdropColor", r,g,b,a or 1)
end

local function IsDecorated(frame)
    return frame and type(frame.GetBackdrop) == "function"
        and type(frame.SetBackdrop) == "function"
end

local function CopyBackdrop(backdrop)
    if type(backdrop) ~= "table" then return nil end
    local copy = {}
    for k,v in pairs(backdrop) do
        if type(v) == "table" then
            copy[k] = {}
            for x,y in pairs(v) do copy[k][x] = y end
        else copy[k] = v end
    end
    return copy
end

local function BgStyle(frame)
    if frame == root or frame == advanced or (frame.GetName and
        (frame:GetName() == "ForeverQuickJoinHostingPanel"
            or frame:GetName() == "ForeverQuickJoinRoleManager")) then
        return 0.045, 0.069, 0.090
    end
    if frame.GetWidth and frame.GetHeight then
        local w,h = frame:GetWidth(),frame:GetHeight()
        if type(w)=="number" and type(h)=="number" and w>=700 and h<=105 then
            return .075,.125,.148 -- party summary, result headers, detail rows
        elseif type(w)=="number" and w<350 then
            return .088,.122,.150
        end
    end
    return .069,.096,.123
end

local function StyleBackdrop(frame)
    if not IsDecorated(frame) then return end
    local saved = baseBackdrops[frame]
    if not saved then
        local original = SafeCall(frame, "GetBackdrop")
        if type(original) ~= "table" then return end
        local r,g,b,a = SafeCall(frame,"GetBackdropColor")
        local er,eg,eb,ea = SafeCall(frame,"GetBackdropBorderColor")
        saved = {config=CopyBackdrop(original), color={r or .1,g or .1,b or .1,a or 1},
            border={er or 1,eg or 1,eb or 1,ea or 1}}
        baseBackdrops[frame] = saved
    end
    if active == "Modern" then
        frame:SetBackdrop({
            bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Buttons\\WHITE8X8",
            tile=false, tileSize=1, edgeSize=1,
            insets={left=1,right=1,top=1,bottom=1},
        })
        local r,g,b = BgStyle(frame)
        Color(frame,r,g,b,1)
        SafeCall(frame,"SetBackdropBorderColor",.18,.31,.37,1)
    else
        frame:SetBackdrop(saved.config)
        Color(frame,unpack(saved.color))
        SafeCall(frame,"SetBackdropBorderColor",unpack(saved.border))
    end
end

local function StyleFontString(font)
    if not font or not font.GetFont or not font.SetFont then return end
    local saved = baseFonts[font]
    if not saved then
        local family,size,flags = SafeCall(font,"GetFont")
        if type(family)~="string" or type(size)~="number" then return end
        saved={family=family,size=size,flags=flags}
        baseFonts[font]=saved
    end
    if active=="Modern" then
        -- Built-in WoW font; never ships or replaces external font assets.
        SafeCall(font,"SetFont","Fonts\\ARIALN.TTF",saved.size+(.4), saved.flags)
        local message=SafeCall(font,"GetText")
        if type(message)=="string" and
            (message:find("GROUP LISTINGS",1,true) or message:find("PARTY ROLE MANAGER",1,true)
             or message:find("LIST GROUP & APPLICANT",1,true)
             or message:find("ADVANCED FILTER",1,true)) then
            if not fontColors[font] then
                local r,g,b,a = SafeCall(font,"GetTextColor")
                fontColors[font]={r or 1,g or 1,b or 1,a or 1}
            end
            SafeCall(font,"SetTextColor",accent[1],accent[2],accent[3],1)
        end
    else
        SafeCall(font,"SetFont",saved.family,saved.size,saved.flags)
        if fontColors[font] then SafeCall(font,"SetTextColor",unpack(fontColors[font])) end
    end
end

local function StyleButton(button)
    if not button or not button.GetText or type(SafeCall(button,"GetText"))~="string" then return end
    if not button.CreateTexture then return end
    local overlay=buttonOverlays[button]
    if not overlay then
        overlay=button:CreateTexture(nil,"BACKGROUND",nil,1)
        overlay:SetAllPoints(button)
        overlay:SetColorTexture(.11,.18,.21,1)
        overlay:Hide()
        buttonOverlays[button]=overlay
        if type(button.HookScript)=="function" then
            button:HookScript("OnEnter",function(self)
                local tex=buttonOverlays[self]
                if active=="Modern" and tex then tex:SetColorTexture(.14,.28,.31,1) end
            end)
            button:HookScript("OnLeave",function(self)
                local tex=buttonOverlays[self]
                if active=="Modern" and tex then tex:SetColorTexture(.11,.18,.21,1) end
            end)
        end
    end
    -- Existing template highlights and borders should not bleed through the
    -- flat Modern buttons. Save each region's alpha for exact restoration.
    if type(button.GetRegions)=="function" then
        local count=select("#",button:GetRegions())
        for i=1,count do
            local region=select(i,button:GetRegions())
            if region ~= overlay and region and region.GetObjectType
                and region:GetObjectType()=="Texture" then
                if baseTextureAlphas[region]==nil then
                    baseTextureAlphas[region]=region:GetAlpha()
                end
                if active=="Modern" then region:SetAlpha(0)
                else region:SetAlpha(baseTextureAlphas[region]) end
            end
        end
    end
    if active=="Modern" then
        overlay:Show()
    else
        overlay:Hide()
    end
end

local function Visit(frame, visited, limit)
    if not frame or visited[frame] or limit.count>900 then return end
    visited[frame]=true
    limit.count=limit.count+1
    if frame.GetObjectType then
        local t=SafeCall(frame,"GetObjectType")
        if t=="FontString" then StyleFontString(frame)
        elseif t=="Frame" or t=="Button" or t=="CheckButton"
            or t=="ScrollFrame" or t=="EditBox" or t=="DropdownButton" then
            StyleBackdrop(frame)
            if t=="Button" then StyleButton(frame) end
        end
    end
    if frame.GetRegions then
        local count=select("#",frame:GetRegions())
        for i=1,count do
            local child=select(i,frame:GetRegions())
            if child and child.GetObjectType and SafeCall(child,"GetObjectType")=="FontString" then
                StyleFontString(child)
            end
        end
    end
    if frame.GetChildren then
        local count=select("#",frame:GetChildren())
        for i=1,count do Visit(select(i,frame:GetChildren()),visited,limit) end
    end
end

local foreverButton,modernButton
local function UpdateToggles()
    if foreverButton then
        foreverButton:SetText(active=="Forever" and "[Forever]" or "Forever")
    end
    if modernButton then
        modernButton:SetText(active=="Modern" and "[Modern]" or "Modern")
    end
    if active=="Modern" then
        local a=buttonOverlays[modernButton]
        if a then a:SetColorTexture(.12,.39,.40,1) end
    else
        local a=buttonOverlays[foreverButton]
        if a then a:SetColorTexture(.12,.39,.40,1) end
    end
end

function Theme.ApplyNew()
    if not root then return end
    -- Never traverse UIParent or native Blizzard frames. Include hidden
    -- QuickJoin-owned host/party panes, which switch live as well.
    Visit(root,{}, {count=0})
    UpdateToggles()
end

function Theme.Select(name)
    if name~="Forever" and name~="Modern" then return end
    active=name
    ForeverQuickJoinDB=ForeverQuickJoinDB or {}
    ForeverQuickJoinDB.theme=name
    Theme.ApplyNew() -- no /reload, no recreated frames, no protected API
    if ForeverQuickJoinParty and ForeverQuickJoinParty.Refresh then
        ForeverQuickJoinParty.Refresh(false)
    end
end

function Theme.RowHover(row, entered)
    if not row then return end
    if active=="Modern" then
        Color(row, entered and .11 or .075, entered and .20 or .125,
            entered and .23 or .148,1)
    else
        Color(row, entered and .17 or .10, entered and .20 or .12,
            entered and .27 or .16,1)
    end
end

function Theme.Attach(window, drawer, rows)
    if root then return end
    root,advanced,resultRows=window,drawer,rows
    active=(ForeverQuickJoinDB and ForeverQuickJoinDB.theme=="Modern") and "Modern" or "Forever"
    local tag=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tag:SetPoint("TOPLEFT",window,"TOPLEFT",247,-22)
    tag:SetText("Theme:")
    local function Toggle(text,x,width,onClick)
        local button=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT",window,"TOPLEFT",x,-13)
        button:SetSize(width,27)
        button:SetText(text)
        button:SetScript("OnClick",onClick)
        return button
    end
    foreverButton=Toggle("Forever",293,80,function() Theme.Select("Forever") end)
    modernButton=Toggle("Modern",374,80,function() Theme.Select("Modern") end)
    Theme.ApplyNew()
end
