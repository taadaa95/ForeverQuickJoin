-- Lua 5.1 regression checks for v0.8.0 activity filtering, alerts, and scale.
local main=assert(io.open("ForeverQuickJoin.lua","rb")):read("*a")
local apps=assert(io.open("ForeverQuickJoin_Applications.lua","rb")):read("*a")
local function Piece(source,first,last)
    local start=assert(source:find("local function "..first.."(",1,true),"Missing "..first)
    local finish=assert(source:find("\nlocal function "..last.."(",start,true),
        "Missing end for "..first)
    return source:sub(start,finish-1):gsub("^local function ","function ",1)
end
local env={state={activities={
    {id=1,name="Scarlet Monastery"},
    {id=2,name="Stormwind Stockades"},
    {id=3,name="The Deadmines"},
    {id=4,name="Scarlet Monastery Armory"}
}}}
setmetatable(env,{__index=_G})
local program=assert(loadstring(Piece(main,"FilterActivities","SetAllowedActivities").."\n"..
    Piece(main,"ClampWindowScale","CreateWindow").."\n"..
    "return FilterActivities,ClampWindowScale"))
setfenv(program,env)
local filter,scale=program()
assert(#filter("")==4 and #filter(nil)==4,"empty query restores all activities")
assert(#filter("SCARLET")==2 and filter("scarlet")[1].id==1,"case-insensitive filtering")
assert(#filter("  storm  ")==1 and filter("storm")[1].id==2,"trim query")
assert(#filter("some unknown dungeon")==0,"nonmatching activity excluded")
assert(scale(0.3)==0.7 and scale(5)==1.45,"resize limits")
assert(scale("broken")==1 and scale(1.2)==1.2,"invalid/default and valid scale")
assert(main:find("local choices=FilterActivities(state.activitySearchQuery)",1,true))
assert(main:find("activitySearchBox:SetScript(\"OnEnterPressed\"",1,true))
assert(main:find("grip:SetScript(\"OnMouseDown\"",1,true))
assert(main:find("db.windowScale=ClampWindowScale(window:GetScale())",1,true))
assert(main:find("searchButton:SetScript(\"OnClick\", SearchFromClick)",1,true),
    "search must still be explicitly player initiated")

local appEnv={ForeverQuickJoinDB={replyNotifications=false},soundCalls=0,
    SOUNDKIT={TELL_MESSAGE=42},UIErrorsFrame={AddMessage=function()end},
    DEFAULT_CHAT_FRAME={AddMessage=function()end},
    Plain=function(value)return value end,Display=function(value)return value end}
appEnv.PlaySound=function()appEnv.soundCalls=appEnv.soundCalls+1 end
setmetatable(appEnv,{__index=_G})
local loaded=assert(loadstring(Piece(apps,"NotificationsEnabled","NotifyReply").."\n"..
    Piece(apps,"NotifyReply","UpdateTab").."\n"..
    "return NotificationsEnabled,NotifyReply"))
setfenv(loaded,appEnv)
local enabled,notify=loaded()
local entry={leader="Leader"}
assert(not enabled(),"notification setting must honor off")
notify(entry)
assert(appEnv.soundCalls==0,"disabled alert cannot play")
appEnv.ForeverQuickJoinDB.replyNotifications=true
assert(enabled(),"explicit true should enable")
notify(entry)
assert(appEnv.soundCalls==1,"enabled reply plays once")
appEnv.selected=entry
appEnv.panel={IsShown=function()return true end}
notify(entry)
assert(appEnv.soundCalls==1,"opened conversation suppresses alert")
appEnv.ForeverQuickJoinDB.replyNotifications=nil
assert(enabled(),"default is on")
assert(apps:find("notificationsCheck:SetScript(\"OnClick\"",1,true))
assert(apps:find("NotifyReply(match)",1,true),"incoming replies must trigger alert")
print("UI feature tests passed.")
