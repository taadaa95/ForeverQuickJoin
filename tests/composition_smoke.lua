-- Lua 5.1 smoke test of the real QuickJoin local role/advanced filters.
-- Load just the production filter functions; never initialize the WoW UI.
local source=assert(io.open("ForeverQuickJoin.lua","rb")):read("*a")
local function Extract(first,following)
    local start=assert(source:find("local function "..first.."(",1,true),
        "Cannot locate "..first)
    local finish=assert(source:find("\nlocal function "..following.."(",start,true),
        "Cannot locate end of "..first)
    return source:sub(start,finish-1):gsub("^local function ","function ",1)
end

local env={
    db={
        advanced={excludedClasses={},excludedPlaystyles={},maxMembers=0,ignoreTeamComposition=false},
        filters={}
    },
    state={rosterClassCache={}},
    Readable=function(value) return value end,
    GetMaxMembers=function(info) return info.maximum end,
    GetCounts=function(id)
        if id==1 then return {TANK=0,HEALER=0,DAMAGER=4} end
        if id==2 then return {TANK=4,HEALER=0,DAMAGER=0} end
        return nil
    end,
    ROLE_TARGETS={[5]={TANK=1,HEALER=1,DAMAGER=3}},
    RosterClasses=function() return {classes={PRIEST=true},unknown=false} end,
    UpdateFilterButtons=function() end,
    RebuildVisibleResults=function() end,
}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(Extract("PassesAdvancedFilters","PassesRoleFilters").."\n"..
    Extract("PassesRoleFilters","UpdateAdvancedControls").."\n"..
    Extract("ResetFilters","SetSort").."\n"..
    "return PassesAdvancedFilters,PassesRoleFilters,ResetFilters"))
setfenv(chunk,env)
local advanced,roles,reset=chunk()

local fourDps={
    numMembers=4,maximum=5,
    counts={TANK=0,HEALER=0,DAMAGER=4},
    generalPlaystyle=2,leaderName="Alice",hasSelf=false,isDelisted=false,
    comment="Unconventional team",
}
local fourTanks={
    numMembers=4,maximum=5,
    counts={TANK=4,HEALER=0,DAMAGER=0},
    generalPlaystyle=2,leaderName="Bob",hasSelf=false,isDelisted=false,
}
env.db.filters.needDps=true
assert(not roles(1,fourDps),"4 DPS rejected by normal DPS vacancy target")
env.db.advanced.ignoreTeamComposition=true
assert(roles(1,fourDps),"ignore composition must admit a 4 DPS listing")
assert(env.db.filters.needDps==true,"existing role selections must be retained")

env.db.advanced.ignoreTeamComposition=false
env.db.filters={needTank=true}
assert(not roles(2,fourTanks),"4 tanks rejected by normal tank vacancy target")
env.db.advanced.ignoreTeamComposition=true
assert(roles(2,fourTanks),"ignore composition must admit a 4 tank listing")

env.db.advanced.ignoreTeamComposition=false
env.db.filters={hasHealer=true}
assert(not roles(1,fourDps),"missing healer should normally fail Already has healer")
env.db.advanced.ignoreTeamComposition=true
assert(roles(1,fourDps),"ignore must bypass Already has healer")
env.db.advanced.ignoreTeamComposition=false
assert(not roles(1,fourDps),"unchecking must restore previous role filters")

env.db.advanced.ignoreTeamComposition=true
env.db.advanced.excludedPlaystyles[2]=true
assert(not advanced(1,fourDps),"ignore team composition must not override playstyle exclusions")
env.db.advanced.excludedPlaystyles[2]=nil

env.db.advanced.maxMembers=3
assert(not advanced(1,fourDps),"ignore team composition must not override group-size cap")
env.db.advanced.maxMembers=0

env.db.advanced.whisperable=true
local hidden={numMembers=4,maximum=5,counts=fourDps.counts,generalPlaystyle=2}
assert(not advanced(1,hidden),"ignore team composition must not override whisperable")
env.db.advanced.whisperable=nil

env.db.advanced.excludedClasses.PRIEST=true
assert(not advanced(1,fourDps),"ignore must not override class exclusion")
env.db.advanced.excludedClasses.PRIEST=nil

-- An unknown role-count result must not be rejected by composition filters
-- when the override is active. It still needs genuine server listing data.
local unknown={
    numMembers=4,maximum=nil,counts=nil,leaderName="Carol",
    generalPlaystyle=2,hasSelf=false,isDelisted=false,
}
assert(roles(3,unknown),"ignore should bypass unreadable composition data")

reset()
assert(not env.db.advanced.ignoreTeamComposition,"Clear All Filters resets the override")
assert(not env.db.filters.hasHealer,"Clear All Filters clears role requirements")
assert(advanced(1,fourDps),"no unrelated restrictions after reset")
print("Composition filter tests passed.")
