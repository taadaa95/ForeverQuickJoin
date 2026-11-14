-- Lua 5.1 regression test using a minimal WoW UI stub. No client launched.
local function Frame(kind,parent,name)
    local f={kind=kind,parent=parent,name=name,children={},regions={},alpha=1,
        backdrop={bgFile="original",edgeFile="originalEdge"},
        bg={.11,.13,.17,1},border={.75,.70,.65,1},width=840,height=785,
        calls={}}
    -- FontStrings/textures are regions, not child frames, in the real WoW UI.
    if parent and kind~="FontString" and kind~="Texture" then
        parent.children[#parent.children+1]=f
    end
    function f:GetObjectType() return self.kind end
    function f:GetParent() return self.parent end
    function f:GetName() return self.name end
    function f:GetChildren() return unpack(self.children) end
    function f:GetRegions() return unpack(self.regions) end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:GetBackdrop() return self.backdrop end
    function f:SetBackdrop(value) self.backdrop=value end
    function f:GetBackdropColor() return unpack(self.bg) end
    function f:SetBackdropColor(...) self.bg={...} end
    function f:GetBackdropBorderColor() return unpack(self.border) end
    function f:SetBackdropBorderColor(...) self.border={...} end
    function f:SetAlpha(v) self.alpha=v;self.calls.alpha=(self.calls.alpha or 0)+1 end
    function f:SetWidth(v) self.width=v end
    function f:SetSize(w,h) self.width=w;self.height=h end
    function f:SetJustifyH(value) self.justify=value end
    function f:SetPoint(...) end
    function f:Hide() self.hidden=true end
    function f:Show() self.hidden=false end
    function f:CreateTexture(_,layer)
        local t=Frame("Texture",self)
        self.regions[#self.regions+1]=t
        function t:SetColorTexture(...) self.tint={...} end
        function t:SetHeight(h) self.height=h end
        function t:SetAllPoints(...) end
        function t:GetAlpha() return self.alpha end
        return t
    end
    function f:CreateFontString(_,layer,font)
        local t=Frame("FontString",self)
        self.regions[#self.regions+1]=t
        t.font={ "Fonts\\FRIZQT__.TTF",12,"" }
        t.color={1,.8,.1,1}
        function t:SetText(s) self.text=s end
        function t:GetText() return self.text end
        function t:GetFont() return unpack(self.font) end
        function t:SetFont(...) self.font={...} end
        function t:GetTextColor() return unpack(self.color) end
        function t:SetTextColor(...) self.color={...} end
        return t
    end
    function f:SetDefaultText(t) self.text=t end
    function f:SetText(t) self.text=t end
    function f:GetText() return self.text end
    function f:OverrideText(t) self.text=t end
    function f:SetupMenu(handler) self.menuHandler=handler end
    return f
end
local lastDropdown
CreateFrame=function(kind,name,parent,template)
    local f=Frame(kind,parent,name)
    if kind=="DropdownButton" then lastDropdown=f end
    return f
end

local function Menu()
    local m={radio={},check=nil,dungeon=nil}
    function m:SetTag(s) self.tag=s end
    function m:CreateRadio(text,selected,action)
        self.radio[text]={selected=selected,action=action}
    end
    function m:CreateTitle(title) self.titles=self.titles or {};self.titles[#self.titles+1]=title end
    function m:CreateDivider() self.divider=true end
    function m:CreateCheckbox(text,selected,action)
        local entry={name=text,selected=selected,action=action}
        function entry:SetSelectionIgnored() self.selectionIgnored=true end
        if not self.check then self.check=entry else self.dungeon=entry end
        return entry
    end
    return m
end
ForeverQuickJoinDB={theme="Forever",themeTransparency=false}
local originalWindow=Frame("Frame",nil,"ForeverQuickJoinWindow")
local child=Frame("Frame",originalWindow,"ForeverQuickJoinRoleManager")
child.bg={.2,.22,.25,.9}
local button=Frame("Button",originalWindow)
button.text="Search"
local font=button:CreateFontString()
font:SetText("Search")
local f=assert(loadfile("ForeverQuickJoin_Theme.lua"))
f()
local theme=assert(ForeverQuickJoinTheme)
theme.Attach(originalWindow)
assert(lastDropdown and lastDropdown.width==121,"Single dropdown replaces old buttons")
assert(#originalWindow.children==3,"Expected: child, button, theme dropdown, not two theme buttons")
assert(lastDropdown.text=="Forever · EN","Original theme caption retained")
assert(originalWindow.bg[4]==1 and child.bg[4]==.9)
local menu=Menu()
lastDropdown.menuHandler(lastDropdown,menu)
assert(menu.radio.Forever and menu.radio.Modern and menu.divider and menu.check
    and menu.dungeon and menu.radio["Français"],"Dropdown must include themes, language, and translation toggle")
assert(menu.check.selectionIgnored,"Transparency must not change selection text")
assert(menu.check.selected()==false)
menu.check.action()
assert(theme.Current()=="Forever")
local selected,trans=theme.Current()
assert(selected=="Forever" and trans==true,"Forever + transparency should activate instantly")
assert(originalWindow.bg[4]<1 and originalWindow.bg[4]>.5,"Forever window backdrop translucent")
assert(math.abs(child.bg[4]-.9*.58)<.001,"Original panel alpha proportional and transparent")
assert(font.alpha==1 and originalWindow.alpha==1,"Text and window must not be faded")
assert(ForeverQuickJoinDB.themeTransparency==true,"Per-character transparency saved")
assert(lastDropdown.text=="Forever · EN","Theme caption must retain theme and language")

menu.radio.Modern.action()
selected,trans=theme.Current()
assert(selected=="Modern" and trans==true,"Modern retains transparency")
assert(lastDropdown.text=="Modern · EN")
assert(originalWindow.bg[4]<1,"Modern background translucent")
assert(originalWindow.backdrop.bgFile=="Interface\\Buttons\\WHITE8X8","Modern uses its own palette")
theme.RowHover(child,true)
assert(child.bg[4]<1,"Hover must not remove transparency")

menu.check.action()
selected,trans=theme.Current()
assert(selected=="Modern" and trans==false,"Toggle off transparency without changing theme")
assert(originalWindow.bg[4]==1,"Modern returns to opaque background")
assert(child.bg[4]==1,"Modern cards return to opaque background")
menu.radio.Forever.action()
selected,trans=theme.Current()
assert(selected=="Forever" and trans==false)
assert(originalWindow.backdrop.bgFile=="original","Forever restores original backdrop")
assert(originalWindow.bg[4]==1 and child.bg[4]==.9,"Forever restores exact saved alpha")
assert(child.border[1]==.75 and child.border[4]==1,"Forever restores border")
assert(originalWindow.alpha==1 and (originalWindow.calls.alpha or 0)==0,"No parent SetAlpha calls")
assert(ForeverQuickJoinDB.theme=="Forever" and ForeverQuickJoinDB.themeTransparency==false)

-- Saved settings must survive addon reload and re-attach to a fresh window.
ForeverQuickJoinDB.theme="Modern"
ForeverQuickJoinDB.themeTransparency=true
local win2=Frame("Frame",nil,"ForeverQuickJoinWindow")
local f2=assert(loadfile("ForeverQuickJoin_Theme.lua"))
f2()
ForeverQuickJoinTheme.Attach(win2)
local mode2,alpha2=ForeverQuickJoinTheme.Current()
assert(mode2=="Modern" and alpha2==true and win2.bg[4]<1,
    "Saved theme/transparency should restore at login")
print("Theme selector/transparency smoke tests passed.")
