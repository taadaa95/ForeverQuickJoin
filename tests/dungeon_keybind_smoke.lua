-- Lua 5.1 dungeon-level and native binding regression coverage.
local handle=assert(io.open("ForeverQuickJoin.lua","rb"))
local source=handle:read("*a"); handle:close()
local function Piece(startName,endName)
    local start=assert(source:find("local function "..startName.."(",1,true),"missing "..startName)
    local finish=assert(source:find("\nlocal function "..endName.."(",start,true),"missing end for "..startName)
    return source:sub(start,finish-1):gsub("^local function ","function ",1)
end
local data={
    [1]={categoryID=2,minLevelSuggestion=17,maxLevelSuggestion=26,fullName="Deadmines"},
    [2]={categoryID=2,minLevelSuggestion=32,maxLevelSuggestion=42,fullName="Scarlet Monastery"},
    [3]={categoryID=1,minLevelSuggestion=15,maxLevelSuggestion=26,fullName="Westfall"},
    [4]={categoryID=2,minLevel=10,minLevelSuggestion=0,maxLevelSuggestion=0,fullName="Unknown"},
    [5]={categoryID=2,minLevelSuggestion=15,maxLevelSuggestion=14,fullName="Bad Range"},
}
local env={
    Readable=function(x)return x end,
    state={activityID=nil},
    C_LFGList={GetActivityInfoTable=function(id)return data[id]end},
    ResultActivityIDs=function(info)return info.activityIDs or {info.activityID} end,
}
setmetatable(env,{__index=_G})
local fn=assert(loadstring(Piece("SuggestedDungeonLevelLabel","ActivityDungeonLevelLabel").."\n"..
    Piece("ActivityDungeonLevelLabel","ResultDungeonLevelLabel").."\n"..
    Piece("ResultDungeonLevelLabel","ResultActivityNames").."\n"..
    "return SuggestedDungeonLevelLabel,ActivityDungeonLevelLabel,ResultDungeonLevelLabel"))
setfenv(fn,env)
local suggested,activity,result=fn()
env.SuggestedDungeonLevelLabel=suggested
env.ActivityDungeonLevelLabel=activity
assert(suggested(data[1])=="Lv 17-26","use client's suggested range")
assert(suggested(data[3])==nil,"do not show ranges for Quests & Zones")
assert(suggested(data[4])==nil,"missing suggestions must not fall back to entry minimum")
assert(suggested(data[5])==nil,"bad range must be hidden")
assert(suggested({categoryID=2,minLevelSuggestion=32.5,maxLevelSuggestion=42})==nil,
    "levels must be integral")
assert(activity(2)=="Lv 32-42","activity lookup")
assert(activity(99)==nil,"missing activity lookup must not invent a range")
assert(result({activityIDs={1,2}})=="Lv 17-26","default first dungeon")
env.state.activityID=2
assert(result({activityIDs={1,2}})=="Lv 32-42","selected multi-activity dungeon wins")
assert(source:find("levelLabel=SuggestedDungeonLevelLabel(info)",1,true),
    "dropdown source must use native suggested dungeon range")
assert(source:find('root:CreateRadio(caption,',1,true),
    "menu entries must include level ranges")
assert(source:find('activityDropdown:OverrideText(caption)',1,true),
    "selected dropdown should display its level range")
assert(source:find('row.dungeonLevelLabel=ResultDungeonLevelLabel(info)',1,true),
    "finder rows must show the selected level range")
assert(source:find('local level=ActivityDungeonLevelLabel(id)',1,true),
    "tooltip must show per-activity levels")
assert(source:find('BINDING_HEADER_FOREVERQUICKJOIN = "Forever QuickJoin"',1,true),
    "native binding header must be readable")
assert(source:find('BINDING_NAME_FOREVERQUICKJOIN_TOGGLE = "Toggle Forever QuickJoin"',1,true),
    "native binding name must be readable")
assert(source:find('function ForeverQuickJoin_ToggleWindow()',1,true),
    "WoW binding must call a global function")
local bindingSource=source:match("function ForeverQuickJoin_ToggleWindow%b()(.+)\nend")
assert(bindingSource and bindingSource:find("ToggleWindow()",1,true),
    "binding action must delegate to /qj toggle")
assert(source:find('searchButton:SetScript("OnClick", SearchFromClick)',1,true),
    "keybinding must not invoke protected Group Finder search")
print("Dungeon range/keybinding tests passed.")
