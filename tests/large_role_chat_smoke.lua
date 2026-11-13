-- Production regression coverage for the approved local v0.9.6 preview.
-- These checks use real function bodies extracted from source, not a test companion.
local function Read(path)
    local file=assert(io.open(path,"rb"))
    local value=file:read("*a")
    file:close()
    return value
end
local chat=Read("ForeverQuickJoin_Chat.lua")
local party=Read("ForeverQuickJoin_Party.lua")
local toc=Read("ForeverQuickJoin.toc")
assert(toc:find("## Version: 0.9.6",1,true))
assert(not toc:find("ForeverQuickJoin096Test",1,true))
local function Extract(source,first,last,returnCode)
    local a=assert(source:find(first,1,true),"Missing "..first)
    local b=assert(source:find(last,a,true),"Missing "..last)
    return assert(loadstring(source:sub(a,b-1).."\n"..returnCode))()
end

local ValidName,PrepareChat,OpenSenderMenu,Hitbox =
    Extract(chat,"local function ContextPlayerName(","local function InstallChatPanel(window)",
        "return ContextPlayerName,PrepareSenderChat,OpenSenderContextMenu,InstallSenderHitbox")
assert(ValidName("Player-Realm")=="Player-Realm")
assert(not ValidName('Bad"/who') and not ValidName("Bad Name"))
local opened={}
ChatFrameUtil={OpenChat=function(cmd) opened[#opened+1]=cmd end}
local menuCalls=0
local popups={}
MenuUtil={CreateContextMenu=function(owner,build)
    menuCalls=menuCalls+1
    local menu={}
    local ctx={
        CreateTitle=function(_,s) menu.title=s end,
        CreateButton=function(_,s,callback) menu[s]=callback end,
    }
    build(owner,ctx)
    popups[#popups+1]=menu
end}
local whoUi=0
C_FriendList={SetWhoToUi=function(value) if value then whoUi=whoUi+1 end end}
local tooltip={Hide=function() end,SetOwner=function() end,
    AddLine=function() end,Show=function() end}
GameTooltip=tooltip
Readable=function(v) return v end
Print=function() end
OpenSenderMenu({}, {sender="Player-Realm",synthetic=false})
assert(menuCalls==1 and popups[1].title=="Player-Realm")
assert(opened[1]==nil,"opening context menu must not submit WHO/whisper")
popups[1]["Prepare Whisper"]()
assert(opened[1]=="/w Player-Realm ")
popups[1]["Prepare /who"]()
assert(opened[2]=='/who n-"Player-Realm"' and whoUi==1)
OpenSenderMenu({}, {sender="Player-Realm",synthetic=true})
OpenSenderMenu({}, {sender="Evil Player",synthetic=false})
assert(menuCalls==1,"test posts and invalid names must not open a context menu")
local row={entry={sender="First",synthetic=false},scripts={},
    GetFrameLevel=function() return 3 end}
local hit
CreateFrame=function(kind,_,parent)
    assert(kind=="Button" and parent==row)
    hit={scripts={},SetPoint=function() end,SetSize=function() end,
        RegisterForClicks=function(self,value) self.clicks=value end,
        SetFrameLevel=function(self,value) self.level=value end,
        SetScript=function(self,k,f) self.scripts[k]=f end}
    return hit
end
Hitbox(row)
assert(hit.clicks=="RightButtonUp" and hit.level==5 and row.senderHitbox==hit)
hit.scripts.OnClick(hit,"RightButton")
assert(popups[2].title=="First")
row.entry={sender="Second",synthetic=false}
popups[2]["Prepare Whisper"]()
assert(opened[3]=="/w First ","menu callback must retain original sender after row reuse")
hit.scripts.OnClick(hit,"RightButton")
assert(popups[3].title=="Second")

-- Production large-icon construction uses Blizzard's proper 256x256 role
-- atlas and 256x128 circular background sheet.
local roleData,makeIcon =
    Extract(party,"local LARGE_ROLE_ART=","-- Original WoW classes",
        "return LARGE_ROLE_DATA,CreateSummaryRoleIcon")
assert(#roleData==3)
assert(roleData[1].key=="TANK" and roleData[2].key=="HEALER"
    and roleData[3].key=="DAMAGER")
GetTexCoordsForRole=nil
GetBackgroundTexCoordsForRole=nil
local components={}
local frame={}
function frame:CreateTexture()
    local component={SetTexture=function(self,path) self.path=path end,
        SetSize=function(self,w,h) self.width=w;self.height=h end,
        SetPoint=function() end,
        SetTexCoord=function(self,a,b,c,d) self.coords={a,b,c,d} end,
        SetAlpha=function(self,x) self.alpha=x end}
    components[#components+1]=component
    return component
end
function frame:CreateFontString()
    return {SetPoint=function() end,SetSize=function() end,
        SetJustifyH=function() end,SetText=function(self,s) self.text=s end}
end
local role=makeIcon(frame,roleData[1])
assert(role.key=="TANK" and role.count.text=="0")
assert(components[1].width==63 and components[2].width==54)
assert(components[1].path:find("UI-LFG-ICONS-ROLEBACKGROUNDS",1,true))
assert(components[2].path:find("UI-LFG-ICON-ROLES",1,true))
assert(math.abs(components[2].coords[4]-134/256)<.0001)
assert(party:find('entry.count:SetText(tostring(count[entry.key] or 0))',1,true))
assert(party:find('summaryUnknown:SetText(count.UNKNOWN>0',1,true))
assert(party:find("summaryCounts:Hide()",1,true))
assert(not party:find("debug.getupvalue",1,true))
print("LFG Chat context menu and Blizzard large-role summary tests passed.")
