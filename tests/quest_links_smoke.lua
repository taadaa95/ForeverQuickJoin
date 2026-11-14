local path="ForeverQuickJoin_Chat.lua"
local f=assert(io.open(path,"rb"))
local src=f:read("*a")
f:close()
local a=assert(src:find("local function ForDisplay(",1,true))
local b=assert(src:find("local function NormalizeWords(",a,true))
Readable=function(v) return v end
local loadtext=loadstring or load
local run=assert(loadtext(src:sub(a,b-1).."\nreturn ForDisplay,ValidQuestLink,QuestChatText,SetupQuestMessageLinks,OpenQuestLink,ShowQuestTooltip"))
local Plain,Valid,Render,Setup,Open,Tip=run()
assert(Valid("quest:2994:0") and Valid("quest:4787:0"))
for _,bad in ipairs({"item:2994:0","quest:0","quest:abc","quest:12|r","quest:12:evil","quest:12:0|Hitem:8", "quest:1234567890123456:0"}) do
    assert(not Valid(bad),"Unsafe quest hyperlink accepted: "..bad)
end
local cases={
 {"LFM |cffff2020|Hquest:2994:0|h[Saving Sharpbeak]|h|r", "[Saving Sharpbeak]"},
 {"LFM ||cffff2020||Hquest:2994:0||h[Saving Sharpbeak]||h||r", "[Saving Sharpbeak]"},
 {"LFM ||||cffff2020||||Hquest:2994:0||||h[Saving Sharpbeak]||||h||||r", "[Saving Sharpbeak]"},
 {"LFM |Hquest:2994:0|h[Saving Sharpbeak]|h", "[Saving Sharpbeak]"},
}
for i,c in ipairs(cases) do
    local out,links=Render(c[1],115,true)
    assert(#links==1,"Case "..i.." parsed "..#links.." quest links")
    assert(links[1].payload=="quest:2994:0", "Wrong quest ID")
    assert(out:find("|Hquest:2994:0|h",1,true),"No native clickable link")
    assert(Plain(out)=="LFM "..c[2],"Wrong visible quest title: "..Plain(out))
    local plain,noLinks=Render(c[1],115,false)
    assert(#noLinks==0 and plain=="LFM "..c[2],"Plain fallback broken")
end
local two="LFG |cffff2020|Hquest:2994:0|h[Saving Sharpbeak]|h|r |cffff2020|Hquest:4787:0|h[The Ancient Egg]|h|r"
local out,links=Render(two,115,true)
assert(#links==2 and links[1].payload=="quest:2994:0" and links[2].payload=="quest:4787:0")
assert(Plain(out)=="LFG [Saving Sharpbeak] [The Ancient Egg]",Plain(out))
local clipped,partial=Render(two,25,true)
assert(#partial<=1 and (not clipped:find("|Hquest:",1,true) or clipped:find("|h|r",1,true)))
local malformed=Render("LFM |Hquest:12|r|h[Poison]|h",115,true)
assert(not malformed:find("|Hquest:",1,true),"Bad link must be plain text")
-- Native hyperlinks enabled: real Frame scripts should direct clicks and
-- tooltips to the exact link payload; messages are never sent automatically.
local calls={clicked={},tooltip={},menus={}}
GameTooltip={
    SetOwner=function(self,frame,anchor) calls.tooltip.owner=frame end,
    SetHyperlink=function(self,link) calls.tooltip.link=link end,
    Show=function() calls.tooltip.visible=true end,
    Hide=function() calls.tooltip.visible=false end,
}
SetItemRef=function(link,full,button)
    calls.clicked[#calls.clicked+1]={link=link,full=full,button=button}
end
local row={scripts={},linksOn=false}
function row:SetHyperlinksEnabled(state) self.linksOn=state end
function row:EnableMouse(state) self.mouse=state end
function row:SetScript(k,fn) self.scripts[k]=fn end
Setup(row)
assert(row.nativeQuestLinks==true and row.linksOn and row.mouse)
assert(row.scripts.OnHyperlinkEnter and row.scripts.OnHyperlinkClick)
row.scripts.OnHyperlinkEnter(row,"quest:2994:0")
assert(calls.tooltip.link=="quest:2994:0")
row.scripts.OnHyperlinkClick(row,"quest:2994:0","[Saving Sharpbeak]","LeftButton")
assert(#calls.clicked==1 and calls.clicked[1].link=="quest:2994:0")
row.scripts.OnHyperlinkClick(row,"item:111","[Danger]","LeftButton")
assert(#calls.clicked==1,"Only quest links can be activated")
row.scripts.OnHyperlinkLeave()
assert(calls.tooltip.visible==false)
-- Client with no hyperlink-enabled frame. A clickable native-action button
-- must handle one or multiple quest links without losing original IDs.
local oldButtons={}
CreateFrame=function(kind,_,parent)
    assert(kind=="Button" and parent==row)
    local button={scripts={}}
    function button:SetPoint(...) end
    function button:SetSize(...) end
    function button:SetText(v) self.text=v end
    function button:SetScript(k,fn) self.scripts[k]=fn end
    function button:Hide() self.visible=false end
    function button:Show() self.visible=true end
    oldButtons[#oldButtons+1]=button
    return button
end
local fallback={questLinks=links}
function fallback:SetScript(k,fn) self[k]=fn end
-- swap CreateFrame assertion for fallback
local oldCreate=CreateFrame
CreateFrame=function(kind,_,parent)
   assert(parent==fallback)
   row=fallback
   return oldCreate(kind,_,parent)
end
Setup(fallback)
assert(fallback.nativeQuestLinks==false and fallback.questLinkButton)
local linkButton=fallback.questLinkButton
local popup
MenuUtil={CreateContextMenu=function(owner,build)
    popup={buttons={}}
    function popup:CreateTitle(t) self.title=t end
    function popup:CreateButton(t,fn) self.buttons[t]=fn end
    build(owner,popup)
end}
linkButton.scripts.OnClick(linkButton)
assert(popup and popup.buttons["[The Ancient Egg]"])
popup.buttons["[The Ancient Egg]"]()
assert(calls.clicked[#calls.clicked].link=="quest:4787:0")
fallback.questLinks={links[1]}
linkButton.scripts.OnClick(linkButton)
assert(calls.clicked[#calls.clicked].link=="quest:2994:0")
print("PASS quest links: escaped/doubled, multiquest, clipped, malformed, native tooltip + click and fallback menu")
