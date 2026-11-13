-- Lua 5.1 regression checks for activity filtering, alerts and fixed-size window.
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
    "return FilterActivities"))
setfenv(program,env)
local filter=program()
assert(#filter("")==4 and #filter(nil)==4,"empty query restores all activities")
assert(#filter("SCARLET")==2 and filter("scarlet")[1].id==1,"case-insensitive filtering")
assert(#filter("  storm  ")==1 and filter("storm")[1].id==2,"trim query")
assert(#filter("some unknown dungeon")==0,"nonmatching activity excluded")
env.state.activities[5]={id=5,name="Forest",searchText="forest duskwood eastern kingdoms"}
assert(#filter("duskwood")==1 and filter("duskwood")[1].id==5,
    "available activity/zone aliases should be searchable")
assert(main:find("window:SetSize(840, 785)",1,true),"standard window dimensions")
assert(main:find("window:SetScale(1)",1,true),"fixed 100% window scale")
assert(main:find("local choices=FilterActivities(state.activitySearchQuery)",1,true))
assert(main:find("activitySearchBox:SetScript(\"OnEnterPressed\"",1,true))
assert(not main:find("AttachResizeGrip(",1,true),"resize grip should be removed")
assert(not main:find("ClampWindowScale(",1,true),"resize scale helper should be removed")
assert(not main:find("Click a row to view members",1,true),"obsolete helper label must be removed")
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
