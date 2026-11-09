-- Forever QuickJoin v0.7.1: flat graphite/blue Modern UI and exact Forever restoration.
-- QuickJoin-owned frames only. Never modifies Blizzard's protected windows.
local Theme = {}
ForeverQuickJoinTheme = Theme

local unpack = table.unpack or unpack
local root, advanced
local active = "Forever"
local baseBackdrops = setmetatable({}, {__mode="k"})
local baseFonts = setmetatable({}, {__mode="k"})
local baseFontColors = setmetatable({}, {__mode="k"})
local nativeTextures = setmetatable({}, {__mode="k"})
local buttonSkins = setmetatable({}, {__mode="k"})
local hovering = setmetatable({}, {__mode="k"})
local chrome = {}
local foreverButton, modernButton

-- Restrained, high-contrast graphite rather than saturated turquoise.
-- One blue accent is reserved for important actions and section headings.
local P = {
    canvas={.049,.057,.074}, panel={.075,.088,.109},
    card={.101,.120,.149}, elevated={.127,.150,.181},
    border={.225,.262,.313}, borderSoft={.18,.212,.259},
    accent={.515,.688,.910}, accentFill={.180,.306,.457},
    accentHover={.232,.388,.568}, neutralHover={.176,.211,.263},
    text={.92,.94,.97}, muted={.71,.76,.83},
    danger={.49,.213,.229}, dangerHover={.61,.258,.272},
}

local function Safe(object, name, ...)
    if object and type(object[name])=="function" then
        local ok,a,b,c,d = pcall(object[name],object,...)
        if ok then return a,b,c,d end
    end
end

local function Color(frame,rgb)
    Safe(frame,"SetBackdropColor",rgb[1],rgb[2],rgb[3],1)
end

local function CopyBackdrop(value)
    if type(value)~="table" then return nil end
    local copy={}
    for k,v in pairs(value) do
        if type(v)=="table" then
            copy[k]={}
            for x,y in pairs(v) do copy[k][x]=y end
        else copy[k]=v end
    end
    return copy
end

local function PaletteFor(frame)
    local name=Safe(frame,"GetName")
    if frame==root or frame==advanced
        or name=="ForeverQuickJoinHostingPanel"
        or name=="ForeverQuickJoinRoleManager" then return P.canvas,P.border end
    local w,h=Safe(frame,"GetWidth"),Safe(frame,"GetHeight")
    if type(w)=="number" and type(h)=="number" then
        if w>=700 and h<=105 then return P.panel,P.accentFill end
        if h<=41 then return P.elevated,P.borderSoft end
        if w<350 then return P.card,P.borderSoft end
    end
    return P.panel,P.borderSoft
end

local function StyleBackdrop(frame)
    if not frame or type(frame.GetBackdrop)~="function"
        or type(frame.SetBackdrop)~="function" then return end
    local saved=baseBackdrops[frame]
    if not saved then
        local config=Safe(frame,"GetBackdrop")
        if type(config)~="table" then return end
        local r,g,b,a=Safe(frame,"GetBackdropColor")
        local er,eg,eb,ea=Safe(frame,"GetBackdropBorderColor")
        saved={config=CopyBackdrop(config),color={r or .1,g or .1,b or .1,a or 1},
            border={er or 1,eg or 1,eb or 1,ea or 1}}
        baseBackdrops[frame]=saved
    end
    if active=="Modern" then
        frame:SetBackdrop({
            bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Buttons\\WHITE8X8",
            tile=false,tileSize=1,edgeSize=1,
            insets={left=1,right=1,top=1,bottom=1},
        })
        local bg,border=PaletteFor(frame)
        Color(frame,bg)
        Safe(frame,"SetBackdropBorderColor",border[1],border[2],border[3],1)
    else
        frame:SetBackdrop(saved.config)
        Safe(frame,"SetBackdropColor",unpack(saved.color))
        Safe(frame,"SetBackdropBorderColor",unpack(saved.border))
    end
end

local function IsHeading(text)
    if type(text)~="string" then return false end
    return text:find("GROUP LISTINGS",1,true)
        or text:find("ADVANCED FILTER",1,true)
        or text:find("PARTY ROLE MANAGER",1,true)
        or text:find("LIST GROUP & APPLICANT",1,true)
        or text:find("EXCLUDE",1,true)
        or text:find("Exclude groups containing",1,true)
        or text:find("Exclude these playstyles",1,true)
        or text=="Space for:" or text=="Already has:" or text=="Sort by:"
end

local function StyleFont(font)
    if not font or type(font.SetFont)~="function" then return end
    local saved=baseFonts[font]
    if not saved then
        local family,size,flags=Safe(font,"GetFont")
        if type(family)~="string" or type(size)~="number" then return end
        saved={family=family,size=size,flags=flags}
        baseFonts[font]=saved
    end
    local text=Safe(font,"GetText")
    local heading=IsHeading(text)
    local parent=Safe(font,"GetParent")
    local inButton=Safe(parent,"GetObjectType")=="Button"
    if active=="Modern" then
        local delta=heading and 1 or .5
        Safe(font,"SetFont","Fonts\\ARIALN.TTF",math.max(10,math.floor(saved.size+delta)),saved.flags)
        if heading or inButton then
            if not baseFontColors[font] then
                local r,g,b,a=Safe(font,"GetTextColor")
                baseFontColors[font]={r or 1,g or 1,b or 1,a or 1}
            end
            local color=heading and P.accent or P.text
            Safe(font,"SetTextColor",color[1],color[2],color[3],1)
        end
    else
        Safe(font,"SetFont",saved.family,saved.size,saved.flags)
        if baseFontColors[font] then Safe(font,"SetTextColor",unpack(baseFontColors[font])) end
    end
end

local function AddEdge(button,pointA,pointB,vertical)
    local line=button:CreateTexture(nil,"ARTWORK")
    line:SetColorTexture(unpack(P.border))
    if vertical then
        line:SetWidth(1)
        line:SetPoint(pointA,button,pointA,0,0)
        line:SetPoint(pointB,button,pointB,0,0)
    else
        line:SetHeight(1)
        line:SetPoint(pointA,button,pointA,0,0)
        line:SetPoint(pointB,button,pointB,0,0)
    end
    return line
end

local function ButtonKind(text)
    if type(text)~="string" then return "secondary" end
    if text:find("Decline",1,true) then return "danger" end
    if text:find("Whisper to Join",1,true)
        or text=="Search" or text=="Invite"
        or text=="Open Blizzard Listing"
        or text:find("Review / Fix Roles",1,true)
        or text=="Change Roles" then return "primary" end
    if text=="[Modern]" or text=="[Forever]" then return "selected" end
    return "secondary"
end

local function RefreshButton(button)
    local skin=buttonSkins[button]
    if not skin then return end
    if active~="Modern" then
        skin.fill:Hide()
        for _,edge in ipairs(skin.edges) do edge:Hide() end
        return
    end
    local text=Safe(button,"GetText")
    local kind=ButtonKind(text)
    local disabled=Safe(button,"IsEnabled")==false
    local hover=hovering[button]==true and not disabled
    local color=P.card
    if kind=="danger" then color=hover and P.dangerHover or P.danger
    elseif kind=="primary" or kind=="selected" then
        color=hover and P.accentHover or P.accentFill
    elseif hover then color=P.neutralHover end
    if disabled then color=P.panel end
    skin.fill:SetColorTexture(color[1],color[2],color[3],1)
    skin.fill:Show()
    local border=(kind=="primary" or kind=="selected") and P.accent or P.borderSoft
    for _,edge in ipairs(skin.edges) do
        edge:SetColorTexture(border[1],border[2],border[3],disabled and .4 or 1)
        edge:Show()
    end
end

local function StyleButton(button)
    local text=Safe(button,"GetText")
    if type(text)~="string" or text=="" or type(button.CreateTexture)~="function" then return end
    local skin=buttonSkins[button]
    if not skin then
        skin={edges={},preserved=setmetatable({},{__mode="k"})}
        skin.fill=button:CreateTexture(nil,"BACKGROUND",nil,2)
        skin.fill:SetAllPoints(button)
        skin.fill:Hide()
        skin.edges={
            AddEdge(button,"TOPLEFT","TOPRIGHT",false),
            AddEdge(button,"BOTTOMLEFT","BOTTOMRIGHT",false),
            AddEdge(button,"TOPLEFT","BOTTOMLEFT",true),
            AddEdge(button,"TOPRIGHT","BOTTOMRIGHT",true),
        }
        for _,edge in ipairs(skin.edges) do edge:Hide() end
        buttonSkins[button]=skin
        if type(button.HookScript)=="function" then
            button:HookScript("OnEnter",function(self)
                hovering[self]=true;RefreshButton(self)
            end)
            button:HookScript("OnLeave",function(self)
                hovering[self]=false;RefreshButton(self)
            end)
        end
    end
    -- Suppress only template artwork. Text, role icons inside text and our
    -- custom flat button layers remain visible. Restore exact alpha in Forever.
    if type(button.GetRegions)=="function" then
        local regions={button:GetRegions()}
        for _,region in ipairs(regions) do
            local t=Safe(region,"GetObjectType")
            if t=="Texture" and region~=skin.fill then
                local ours=false
                for _,edge in ipairs(skin.edges) do if region==edge then ours=true;break end end
                if not ours then
                    if nativeTextures[region]==nil then nativeTextures[region]=Safe(region,"GetAlpha") or 1 end
                    Safe(region,"SetAlpha",active=="Modern" and 0 or nativeTextures[region])
                end
            end
        end
    end
    RefreshButton(button)
end

local function Visit(frame,visited,limits)
    if not frame or visited[frame] or limits.count>1350 then return end
    visited[frame]=true
    limits.count=limits.count+1
    local kind=Safe(frame,"GetObjectType")
    if kind=="FontString" then
        StyleFont(frame)
    elseif kind=="Frame" or kind=="Button" or kind=="CheckButton"
        or kind=="ScrollFrame" or kind=="EditBox" or kind=="DropdownButton" then
        StyleBackdrop(frame)
        if kind=="Button" then StyleButton(frame) end
    end
    if type(frame.GetRegions)=="function" then
        local regions={frame:GetRegions()}
        for _,r in ipairs(regions) do
            if Safe(r,"GetObjectType")=="FontString" then StyleFont(r) end
        end
    end
    if type(frame.GetChildren)=="function" then
        local children={frame:GetChildren()}
        for _,child in ipairs(children) do Visit(child,visited,limits) end
    end
end

local function AddChrome(window,drawer)
    local function Stroke(parent,y,height)
        local t=parent:CreateTexture(nil,"ARTWORK")
        t:SetColorTexture(unpack(P.accent))
        t:SetHeight(height)
        t:SetPoint("TOPLEFT",parent,"TOPLEFT",12,-y)
        t:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-12,-y)
        t:Hide()
        table.insert(chrome,t)
    end
    Stroke(window,2,2)
    Stroke(window,44,1)
    if drawer then Stroke(drawer,34,1) end
end

local function UpdateToggles()
    if foreverButton then foreverButton:SetText(active=="Forever" and "[Forever]" or "Forever") end
    if modernButton then modernButton:SetText(active=="Modern" and "[Modern]" or "Modern") end
end

function Theme.ApplyNew()
    if not root then return end
    UpdateToggles()
    Visit(root,{},{count=0})
    -- The drawer can be positioned outside the root but is still its child.
    -- Check it explicitly for client layouts where ownership changes.
    if advanced then Visit(advanced,{},{count=0}) end
    for _,texture in ipairs(chrome) do
        if active=="Modern" then texture:Show() else texture:Hide() end
    end
end

function Theme.Select(name)
    if name~="Forever" and name~="Modern" then return end
    active=name
    ForeverQuickJoinDB=ForeverQuickJoinDB or {}
    ForeverQuickJoinDB.theme=name
    Theme.ApplyNew() -- immediate; no reload or protected action
    if ForeverQuickJoinParty and ForeverQuickJoinParty.Refresh then
        ForeverQuickJoinParty.Refresh(false)
    end
end

function Theme.RowHover(row,entered)
    if not row then return end
    if active=="Modern" then
        Color(row,entered and P.neutralHover or P.card)
    else
        Safe(row,"SetBackdropColor",entered and .17 or .10,
            entered and .20 or .12,entered and .27 or .16,1)
    end
end

function Theme.Attach(window,drawer,rows)
    if root then return end
    root,advanced=window,drawer
    active=(ForeverQuickJoinDB and ForeverQuickJoinDB.theme=="Modern") and "Modern" or "Forever"
    local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    title:SetPoint("TOPLEFT",window,"TOPLEFT",247,-22)
    title:SetText("Theme:")
    local function Toggle(label,x,w,handler)
        local button=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT",window,"TOPLEFT",x,-13)
        button:SetSize(w,27)
        button:SetText(label)
        button:SetScript("OnClick",handler)
        return button
    end
    foreverButton=Toggle("Forever",293,80,function() Theme.Select("Forever") end)
    modernButton=Toggle("Modern",374,80,function() Theme.Select("Modern") end)
    AddChrome(window,drawer)
    Theme.ApplyNew()
end
