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
local env={}
env.Readable=function(value)return value end
local initial={
    db={sortOrder="default"},
    state={activityID=nil,categoryID=2,selectedActivityIDs={},selectedActivitySet={},
        categoryAllIDs={[101]=true,[202]=true,[303]=true,[404]=true},
        cachedResults={},results={},sentByListing={},sentByID={},
        pinnedRealIDs={},suppressedIDs={},totalInCache=1},
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
for k,v in pairs(initial) do env[k]=v end
env._results={}
setmetatable(env,{__index=_G})
local compiled=assert(loadstring(table.concat({
    Piece("ResultActivityIDs","SentIdentity"),
    Piece("SentIdentity","SentStartTime"),
    Piece("SentStartTime","RemoveSent"),
    Piece("MatchSent","SnapshotSentInfo"),
    Piece("ActivityDisplayName","ResultActivityNames"),
    Piece("ResultActivityNames","ResultActivityName"),
    Piece("ResultActivityName","ResultPlaystyle"),
    Piece("GetMaxMembers","GetCounts"),
    Piece("BuildMessage","Status"),
    Piece("SearchCoversSent","MatchSent"),
    Piece("RebuildVisibleResults","SaveAdvanced"),
    "return ResultActivityIDs,SentIdentity,ResultActivityNames,ResultActivityName,GetMaxMembers,BuildMessage,SearchCoversSent,RebuildVisibleResults,MatchSent",
},"\n")))
setfenv(compiled,env)
local ids,key,activityNames,label,maxMembers,message,covers,rebuild,matchSent=compiled()
env.ResultActivityIDs=ids
env.SentIdentity=key
env.ActivityDisplayName=function(id)return names[id]end
env.ResultActivityNames=activityNames
env.ResultActivityName=label
env.GetMaxMembers=maxMembers
env.BuildMessage=message
env.RemoveSent=function(record,reason) env.retired={record=record,reason=reason} end

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

local function SelectForTest(...)
    local selected={...}
    env.state.selectedActivityIDs=selected
    env.state.selectedActivitySet={}
    for _,id in ipairs(selected) do env.state.selectedActivitySet[id]=true end
    env.state.activityID=#selected==1 and selected[1] or nil
    env.state.activityName=env.state.activityID and names[env.state.activityID] or nil
end

local full=label(info)
assert(full=="Blackfathom Deeps / Stormwind Stockades / The Deadmines",
    "unfiltered preview must list every dungeon")
SelectForTest(202)
assert(label(info):find("^Stormwind Stockades / Blackfathom Deeps"),
    "the user's selected dungeon should be first even if second in listing")
local compact=label(info,"row")
assert(compact:find("Stormwind Stockades",1,true) and compact:find("+2",1,true),
    "narrow finder row must show selected activity and count of others")
assert(#activityNames(info)==3,"tooltip should receive all activity names")
SelectForTest(404,202)
assert(label(info):find("^Stormwind Stockades /"),
    "multi-select should prioritize a selected dungeon actually advertised")
SelectForTest(202)

env._results[8]=info
env.state.cachedResults={8}
SelectForTest(202)
rebuild(true)
assert(#env.state.results==1 and env.state.results[1]==8,
    "listing must match second advertised activity")
SelectForTest(303)
rebuild(true)
assert(#env.state.results==1,"listing must match third advertised activity")
SelectForTest(202,404)
rebuild(true)
assert(#env.state.results==1 and env.state.results[1]==8,
    "OR selection must match any checked dungeon, including second in listing")
SelectForTest(404,303)
rebuild(true)
assert(#env.state.results==1,
    "multi-selection must match selected third advertised activity")
SelectForTest(202,303)
rebuild(true)
assert(#env.state.results==1,
    "a group matching two selected activities must appear exactly once")
SelectForTest(404)
rebuild(true)
assert(#env.state.results==0,"unrelated activity must not match")
SelectForTest()
rebuild(true)
assert(#env.state.results==1,"all-activities search should show listing just once")
env.state.categoryAllIDs={[303]=true}
rebuild(true)
assert(#env.state.results==1,"category filter must match any advertised ID")
env.state.categoryAllIDs={[404]=true}
rebuild(true)
assert(#env.state.results==0,"category filter must exclude nonmatching activity sets")

SelectForTest(202)
assert(message(info):find("Stormwind Stockades / Blackfathom Deeps",1,true),
    "whisper must include selected plus other advertised activities")
assert(not message(nil):find("nil",1,true),"generic preview should use current selection")

-- Full lists should compact only when over WoW's 255 byte limit.
env.template=string.rep("x",205).." {activity}"
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
assert(covers({activityIDs={404,303}},record),
    "multi-activity server search covers a listing if any advertised activity overlaps")
assert(not covers(nil,record))
-- A change to the dungeon selection on the SAME group preserves Sent only
-- when both the leader and listing creation time remain consistent.
env.state.sentByID={}
env.state.sentByListing={}
local original={leaderName="Leader",activityIDs={101,202},age=20}
local recordSent={key=key(8,original),leader="Leader",started=80,id=8}
env.state.sentByID[8]=recordSent
env.state.sentByListing[recordSent.key]=recordSent
local expanded={leaderName="Leader",activityIDs={202,303,101},age=20}
assert(matchSent(8,expanded)==recordSent,"adding an activity to the same listing keeps Sent")
assert(recordSent.key==key(8,expanded),"Sent identity must update to new set")
assert(env.state.sentByListing[recordSent.key]==recordSent)
assert(env.state.sentByListing[key(8,original)]==nil,"old canonical key must be cleared")

local replaced={leaderName="Different Leader",activityIDs={202,303,101},age=20}
assert(matchSent(8,replaced)==nil,"same result ID with another leader is not the same listing")
assert(env.retired==nil,"unrelated listing must not trigger false lifecycle transition")

-- Exercise the production activity toggles, selection captions, and native
-- search call without a WoW UI. Only SearchFromClick may invoke Search().
env.state.activities={
    {id=101,name=names[101]}, {id=202,name=names[202]},
    {id=303,name=names[303]}, {id=404,name=names[404]},
}
env.state.categoryAllIDs={[101]=true,[202]=true,[303]=true,[404]=true}
env.state.searchActivityIDs={101,202,303,404}
SelectForTest()
env.window=true
env.activityDropdown={OverrideText=function(_,value)env.caption=value end}
env.UpdatePreview=function()end
local selectorChunk=assert(loadstring(
    Piece("UpdateActivityDropdown","SetCategory")..
    "\nreturn UpdateActivityDropdown,ClearActivitySelection,ToggleActivity"))
setfenv(selectorChunk,env)
local updateCaption,clearSelection,toggleSelection=selectorChunk()
toggleSelection(202)
assert(#env.state.selectedActivityIDs==1 and env.state.selectedActivitySet[202],
    "first checkbox selects a dungeon")
assert(env.caption=="Stormwind Stockades","single selection displays its name")
toggleSelection(303)
assert(#env.state.selectedActivityIDs==2 and env.state.selectedActivitySet[303],
    "second checkbox adds rather than replaces the first selection")
assert(env.caption=="2 activities selected","multiple selections show their count")
toggleSelection(202)
assert(#env.state.selectedActivityIDs==1 and not env.state.selectedActivitySet[202]
    and env.state.selectedActivityIDs[1]==303,"checkbox deselects its dungeon")
toggleSelection(202)
assert(#env.state.selectedActivityIDs==2)
local sentSearches={}
env.state.searching=false
env.state.searchBlocked=false
env.UpdateSearchButton=function()end
env.C_LFGList.Search=function(category,one,two,three,four,five,activities)
    local copy={}
    for _,id in ipairs(activities) do copy[#copy+1]=id end
    sentSearches[#sentSearches+1]={category=category,ids=copy}
    return true
end
local searchChunk=assert(loadstring(
    Piece("SearchFromClick","FinishSearch").."\nreturn SearchFromClick"))
setfenv(searchChunk,env)
local search=searchChunk()
search()
assert(#sentSearches==1 and sentSearches[1].category==2,
    "one player click initiates one native search")
assert(#sentSearches[1].ids==2 and sentSearches[1].ids[1]==303
    and sentSearches[1].ids[2]==202,
    "native search receives both selected IDs without duplicate calls")
assert(env.state.pendingSearch.activityIDs[1]==303
    and env.state.pendingSearch.activityIDs[2]==202,
    "pending search snapshot preserves exact selected scope")
search()
assert(#sentSearches==1,"in-progress search blocks extra calls")
env.state.searching=false
clearSelection()
assert(#env.state.selectedActivityIDs==0 and env.caption=="All activities",
    "clear selection restores All activities")
search()
assert(#sentSearches==2 and #sentSearches[2].ids==4,
    "no checkboxes selected searches the category's available activities")

-- Source checks for the visual and app integration paths that require WoW frames.
assert(source:find("row.detailsActivities:SetShown(multiple)",1,true),
    "expanded row must reveal all activities")
assert(source:find("for _,activityName in ipairs(activities) do",1,true)
    and source:find('GameTooltip:AddLine("  "..SafeMarkup(display)',1,true),
    "hover tooltip must list every activity (with suggested levels where available)")
assert(source:find("row.activityNames=ResultActivityNames(info)",1,true),
    "finder row must track all advertised activities")
print("Multi-activity listing tests passed.")
