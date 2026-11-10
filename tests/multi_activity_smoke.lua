-- Lua 5.1 tests for multi-activity Group Finder listings.
-- Real functions are extracted from the production source; no WoW UI is run.
local source=assert(io.open("ForeverQuickJoin.lua","rb")):read("*a")
local function Piece(first,last)
    local start=assert(source:find("local function "..first.."(",1,true),"Missing "..first)
    local finish=assert(source:find("\nlocal function "..last.."(",start,true),
        "Missing end for "..first)
    return source:sub(start,finish-1):gsub("^local function ","function ",1)
end
local names={
    [101]="Blackfathom Deeps",
    [202]="Stormwind Stockades",
    [303]="The Deadmines",
    [404]="Scarlet Monastery",
}
local caps={[101]=5,[202]=5,[303]=5,[404]=10}
local env={
    Readable=function(value)return value end,
    db={sortOrder="default"},
    state={activityID=nil,categoryID=2,categoryAllIDs={[101]=true,[202]=true,[303]=true,[404]=true},
        cachedResults={},results={},sentByListing={},sentByID={}},
    C_LFGList={
        GetActivityInfoTable=function(id)
            if not names[id] then return nil end
            return {fullName=names[id],maxNumPlayers=caps[id],categoryID=2}
        end,
    },
    GetTime=function()return 100 end,
    Truncate=function(value,n) if #value<=n then return value end
        return value:sub(1,n-3).."..." end,
    ResultInfo=function(id) return env._results[id],env._results[id]~=nil end,
    PassesRoleFilters=function() return true end,
    PassesAdvancedFilters=function()return true end,
    UpdatePages=function()end,
    Status=function()end,
    GroupSize=function()return 0 end,
    PartyRoster=function()return {},0 end,
    GetRole=function()return "DPS" end,
    UnitClass=function()return "Warlock" end,
    UnitLevel=function()return 32 end,
    UnitName=function()return "Tester" end,
    CurrentLocation=function()return "Stormwind" end,
    FormatRoster=function()return "" end,
    CurrentTemplate=function()return env.template end,
    template="L{level} {class} {role} LFG {activity}",
    PREFIX="[QuickJoin]",
}
env._results={}
setmetatable(env,{__index=_G})
local compiled=assert(loadstring(table.concat({
    Piece("ResultActivityIDs","SentIdentity"),
    Piece("SentIdentity","SentStartTime"),
    Piece("ActivityDisplayName","ResultActivityNames"),
    Piece("ResultActivityNames","ResultActivityName"),
    Piece("ResultActivityName","ResultPlaystyle"),
    Piece("GetMaxMembers","GetCounts"),
    Piece("BuildMessage","Status"),
    Piece("SearchCoversSent","MatchSent"),
    Piece("RebuildVisibleResults","SaveAdvanced"),
    "return ResultActivityIDs,SentIdentity,ResultActivityNames,ResultActivityName,GetMaxMembers,BuildMessage,SearchCoversSent,RebuildVisibleResults",
},"\n")))
setfenv(compiled,env)
local ids,key,activityNames,label,maxMembers,message,covers,rebuild=compiled()
env.ResultActivityIDs=ids
env.SentIdentity=key
env.ActivityDisplayName=function(id)return names[id]end
env.ResultActivityNames=activityNames
env.ResultActivityName=label
env.GetMaxMembers=maxMembers
env.BuildMessage=message

local info={leaderName="Leader",activityIDs={101,202,303},name="Dungeon runs",
    isDelisted=false,numMembers=2}
local actual=ids(info)
assert(#actual==3 and actual[1]==101 and actual[2]==202 and actual[3]==303)
assert(key(1,info)==key(9,{leaderName="Leader",activityIDs={303,101,202}}),
    "Sent identity must ignore activity ordering and result IDs")
assert(key(1,info)~=key(9,{leaderName="Leader",activityIDs={101,202}}),
    "distinct advertised sets should not be conflated")
local dedupe=ids({activityIDs={101,101,202,202}})
assert(#dedupe==2 and dedupe[1]==101 and dedupe[2]==202)
assert(ids({activityID=202})[1]==202,"older singular activityID fallback")
assert(maxMembers({activityIDs={202,404}})==10,
    "group maximum must consider every advertised activity")

local full=label(info)
assert(full=="Blackfathom Deeps / Stormwind Stockades / The Deadmines",
    "unfiltered preview must list every dungeon")
env.state.activityID=202
assert(label(info):find("^Stormwind Stockades / Blackfathom Deeps"),
    "the user's selected dungeon should be first even if second in listing")
local compact=label(info,"row")
assert(compact:find("Stormwind Stockades",1,true) and compact:find("+2",1,true),
    "narrow finder row must show selected activity and count of others")
assert(#activityNames(info)==3,"tooltip should receive all activity names")

env._results[8]=info
env.state.cachedResults={8}
env.state.activityID=202
rebuild(true)
assert(#env.state.results==1 and env.state.results[1]==8,
    "listing must match second advertised activity")
env.state.activityID=303
rebuild(true)
assert(#env.state.results==1,"listing must match third advertised activity")
env.state.activityID=404
rebuild(true)
assert(#env.state.results==0,"unrelated activity must not match")
env.state.activityID=nil
rebuild(true)
assert(#env.state.results==1,"all-activities search should show listing just once")
env.state.categoryAllIDs={[303]=true}
rebuild(true)
assert(#env.state.results==1,"category filter must match any advertised ID")
env.state.categoryAllIDs={[404]=true}
rebuild(true)
assert(#env.state.results==0,"category filter must exclude nonmatching activity sets")

env.state.activityID=202
assert(message(info):find("Stormwind Stockades / Blackfathom Deeps",1,true),
    "whisper must include selected plus other advertised activities")
assert(not message(nil):find("nil",1,true),"generic preview should use current selection")

-- Full lists should compact only when over WoW's 255 byte limit.
env.template=string.rep("x",195).." {activity}"
local short=message(info)
assert(#short<=255,"compact multi-dungeon whisper should stay under limit")
assert(short:find("Stormwind Stockades (+2 more)",1,true),
    "long whisper should keep the selected activity and signal other dungeons")
env.template="L{level} {class} LFG {activity}"
assert(message(info):find("The Deadmines",1,true),
    "short whisper should keep every advertised dungeon")

local record={snapshot={activityIDs={101,202,303}}}
assert(covers({activityIDs={202}},record),
    "fresh search for the second activity covers the listing")
assert(covers({activityIDs={303}},record))
assert(not covers({activityIDs={404}},record))
assert(not covers(nil,record))
-- Source checks for the visual and app integration paths that require WoW frames.
assert(source:find("row.detailsActivities:SetShown(multiple)",1,true),
    "expanded row must reveal all activities")
assert(source:find("GameTooltip:AddLine(\"  \"..SafeMarkup(activityName)",1,true),
    "hover tooltip must list every activity")
assert(source:find("row.activityNames=ResultActivityNames(info)",1,true),
    "finder row must track all advertised activities")
print("Multi-activity listing tests passed.")
