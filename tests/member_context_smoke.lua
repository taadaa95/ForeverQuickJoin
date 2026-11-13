-- Regression checks for player context actions in expanded Group Listings.
-- Extracts real callbacks and mocks the native Blizzard chat/menu APIs.
local source=assert(io.open("ForeverQuickJoin.lua","rb")):read("*a")
local function contains(text)
    assert(source:find(text,1,true),"Expected source: "..text)
end
contains('tile:SetScript("OnMouseDown"')
contains('if button == "RightButton" then OpenMemberContextMenu(self) end')
contains('root:CreateButton("Prepare /who"')
contains('root:CreateButton("Prepare Whisper"')
contains('Nothing is sent until you press Enter.')
assert(not source:find('tile:SetScript("OnMouseUp"',1,true),
    "legacy immediate right-click /who handler must be removed")
local first=assert(source:find("local function WhoNameKey(",1,true))
local last=assert(source:find("\n-- Only use native LFG data",first,true))
local chunk=source:sub(first,last-1)..
    "\nreturn WhoNameKey, LookupMemberWho, PrepareMemberWhisper, OpenMemberContextMenu"
local run=assert(loadstring(chunk))
Readable=function(value) return value end
local log={}
Print=function(line) log[#log+1]=line end
GetTime=function() return 1234 end
state={pendingWho=nil}
local commands={}
ChatFrameUtil={OpenChat=function(command) commands[#commands+1]=command end}
ChatFrame_OpenChat=nil
local whoUi=0
C_FriendList={SetWhoToUi=function(enabled) if enabled then whoUi=whoUi+1 end end}
local tooltips=0
GameTooltip={Hide=function() tooltips=tooltips+1 end}
SendChatMessage=function() error("menu should never send messages automatically") end
C_ChatInfo={SendChatMessage=SendChatMessage}
local popup
MenuUtil={CreateContextMenu=function(owner,generator)
    popup={owner=owner,buttons={}}
    generator(owner,{
        CreateTitle=function(_,caption) popup.title=caption end,
        CreateButton=function(_,label,callback) popup.buttons[label]=callback end,
    })
end}
local key,who,whisper,open=run()
assert(key(" Example-Realm ")=="example-realm")
open({whoName="Example-Realm"})
assert(popup and popup.title=="Example-Realm" and tooltips==1)
assert(type(popup.buttons["Prepare /who"])=="function")
assert(type(popup.buttons["Prepare Whisper"])=="function")
assert(#commands==0 and state.pendingWho==nil)
popup.buttons["Prepare Whisper"]()
assert(commands[1]=="/w Example-Realm ","whisper must only populate chat input")
assert(state.pendingWho==nil and whoUi==0,
    "preparing a whisper must not change WHO tracking")
popup.buttons["Prepare /who"]()
assert(commands[2]=='/who n-"Example-Realm"')
assert(state.pendingWho.name=="Example-Realm" and whoUi==1)
local count=#commands
popup=nil
open({whoName=nil})
assert(not popup and #commands==count,"hidden player must not open menu")
open({whoName='bad"|TInterface'})
assert(not popup and #commands==count,"invalid name must be rejected")
MenuUtil=nil
open({whoName="Example-Realm"})
assert(#commands==count,"missing menu API should not send a WHO request")
ChatFrameUtil=nil
ChatFrame_OpenChat=function(command) commands[#commands+1]=command end
whisper("Example-Realm")
assert(commands[#commands]=="/w Example-Realm ","legacy chat-opening fallback")
print("Member context menu tests passed.")
