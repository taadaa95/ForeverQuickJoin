-- Lua 5.1 tests of real Sent-cache reconciliation functions.
-- No WoW client, protected searches or live API calls are needed.
local src=assert(io.open("ForeverQuickJoin.lua","rb")):read("*a")
local function FunctionPiece(name,nextName)
    local start=assert(src:find("local function "..name.."(",1,true),"Missing "..name)
    local finish=assert(src:find("\nlocal function "..nextName.."(",start,true),
        "Missing end of "..name)
    return src:sub(start,finish-1):gsub("^local function ","function ",1)
end
local env={SENT_UNVERIFIED_TTL=600}
setmetatable(env,{__index=_G})
local now=100
local returnedTotal,returnedIDs=0,{}
local infoByID={}
local notifications={unavailable={},ended={}}
env.GetTime=function()return now end
env.Readable=function(v)return v end
env.Status=function()end
env.TrackSearchAppearances=function()end
env.SentIdentity=function(_,info)return info and info.key end
env.SentStartTime=function(info)return info and info.started end
env.SnapshotSentInfo=function(info)
    return {activityIDs=info.activityIDs,leaderName=info.leaderName}
end
env.C_LFGList={GetFilteredSearchResults=function()return returnedTotal,returnedIDs end}
env.ResultInfo=function(id)
    local info=infoByID[id]
    return info,info~=nil
end
env.RebuildVisibleResults=function()
    env.visible={}
    for _,id in ipairs(env.state.cachedResults) do
        if not env.state.suppressedIDs[id] then
            env.visible[#env.visible+1]=id
        end
    end
end
env.ForeverQuickJoinApplications={
    ListingUnavailable=function(rec)notifications.unavailable[#notifications.unavailable+1]=rec end,
    ListingEnded=function(rec)notifications.ended[#notifications.ended+1]=rec end,
}
local function Reset()
    env.state={
        sentByID={},sentByListing={},sentVirtualIDs={},pinnedRealIDs={},
        suppressedIDs={},cachedResults={},rosterClassCache={},totalInCache=0,
    }
    env.visible={}
    infoByID={}
    returnedTotal,returnedIDs=0,{}
    now=100
    notifications.unavailable={}
    notifications.ended={}
end
local function Add(id,activity,virtual)
    local rec={
        id=id,key="Leader"..id..":"..activity,at=now,lastConfirmedAt=now,
        virtualID=virtual,started=now-20,
        snapshot={activityIDs={activity},leaderName="Leader"..id},
    }
    env.state.sentByID[id]=rec
    env.state.sentByListing[rec.key]=rec
    env.state.sentVirtualIDs[virtual]=rec
    env.state.pinnedRealIDs[id]=true
    infoByID[id]={key=rec.key,isDelisted=false,leaderName="Leader"..id,
        activityIDs={activity},started=rec.started}
    return rec
end
local chunk=assert(loadstring(
    FunctionPiece("RemoveSent","PruneExpiredSent").."\n"..
    FunctionPiece("PruneExpiredSent","SearchCoversSent").."\n"..
    FunctionPiece("SearchCoversSent","MatchSent").."\n"..
    FunctionPiece("MatchSent","SnapshotSentInfo").."\n"..
    FunctionPiece("RefreshResults","GetActivities").."\n"..
    "return RemoveSent,PruneExpiredSent,RefreshResults,MatchSent,SearchCoversSent"))
setfenv(chunk,env)
local remove,prune,refresh,match,covers=chunk()

-- An ordinary local refresh must not discard the Sent status.
Reset()
local rec=Add(100,42,-1)
returnedTotal,returnedIDs=1,{100}
refresh(false)
assert(env.state.sentByListing[rec.key]==rec,"local refresh preserves contacted listing")
assert(#env.visible==1 and env.visible[1]==100)
assert(#notifications.unavailable==0)

-- One complete manual Search for its exact activity missing the group should
-- remove it immediately even though GetSearchResultInfo(100) is still cached.
now=110
returnedTotal,returnedIDs=0,{}
refresh(true,{activityIDs={42}})
assert(env.state.sentByListing[rec.key]==nil,"matched-scope absence must retire Sent")
assert(env.state.suppressedIDs[100],"old Blizzard result ID must stay suppressed")
assert(#env.visible==0,"expired group must disappear from Finder")
assert(#notifications.unavailable==1 and notifications.unavailable[1]==rec)
assert(#notifications.ended==0,"missing search result is not proof of disbanding")

-- Unrelated category searches must not instantly remove recently seen Sent.
Reset()
rec=Add(200,42,-2)
now=120
returnedTotal,returnedIDs=0,{}
refresh(true,{activityIDs={66}})
assert(env.state.sentByListing[rec.key]==rec,"unrelated search retains Sent")
assert(#env.visible==1 and env.visible[1]==-2,"unverified entry uses virtual ID")
assert(#notifications.unavailable==0)
-- A native client cache still knows old ID 200, but the clock has expired.
now=701
assert(prune(),"10-minute idle expiry must clean session caches")
assert(env.state.sentByListing[rec.key]==nil)
assert(env.state.suppressedIDs[200],"idle-expired ID must be suppressed")
returnedTotal,returnedIDs=1,{200}
refresh(false)
assert(#env.visible==0,"stale native ID must not resurrect after expiry")

-- A truncated result set doesn't prove that a missing listing is gone.
Reset()
rec=Add(300,42,-3)
now=180
returnedTotal,returnedIDs=30,{999}
refresh(true,{activityIDs={42}})
assert(env.state.sentByListing[rec.key]==rec,
    "capped search results must not trigger premature removal")
assert(#env.visible==2 and env.visible[2]==-3)

-- A fresh verified hit renews the 10-minute evidence window.
Reset()
rec=Add(400,42,-4)
now=650
returnedTotal,returnedIDs=1,{400}
refresh(true,{activityIDs={42}})
assert(rec.lastConfirmedAt==650,"successful search must renew last seen time")
now=1200
returnedTotal,returnedIDs=0,{}
refresh(true,{activityIDs={99}})
assert(env.state.sentByListing[rec.key]==rec,"cross-scope search within TTL retains Sent")
now=1251
refresh(true,{activityIDs={99}})
assert(env.state.sentByListing[rec.key]==nil,"stale Sent retires after TTL")

-- Explicit delisting remains a different, stronger signal.
Reset()
rec=Add(500,42,-5)
local delisted={key=rec.key,isDelisted=true,leaderName="Leader500",activityIDs={42}}
assert(match(500,delisted)==nil)
assert(#notifications.ended==1 and notifications.ended[1]==rec)
assert(#notifications.unavailable==0)
assert(env.state.sentByListing[rec.key]==nil)

-- A new server listing with the same leader/activity must not inherit Sent.
Reset()
rec=Add(600,42,-6)
local reopened={key=rec.key,isDelisted=false,leaderName="Leader600",
    activityIDs={42},started=rec.started+200}
assert(match(600,reopened)==nil)
assert(env.state.sentByListing[rec.key]==nil)

-- Availability checks use the activities submitted, not the user's current UI.
Reset()
rec=Add(700,42,-7)
assert(covers({activityIDs={41,42}},rec))
assert(not covers({activityIDs={90}},rec))
assert(not covers(nil,rec))
print("Sent lifecycle tests passed.")
