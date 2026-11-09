-- Lightweight Lua 5.1 tests; no WoW client or protected APIs involved.
local time=100
GetTime=function() return time end
local listener
CreateFrame=function()
    local frame={events={}}
    function frame:RegisterEvent(event) self.events[event]=true end
    function frame:SetScript(name,fn) self[name]=fn end
    listener=frame
    return frame
end

dofile("ForeverQuickJoin_Applications.lua")
local apps=assert(ForeverQuickJoinApplications)
local one={leader="Alice-Realm",key="alice:1",started=80}
apps.TrackSent(one,{name="Scarlet Library",activityIDs={1}},"LFG DPS")
local total,unread=apps.Counts()
assert(total==1 and unread==0,"new sent record is one unread-free application")
assert(apps.StatusFor(one)=="Sent","sent record should not imply a reply")

-- Subsequent clicks on the same active group must reuse its record.
time=105
apps.TrackSent(one,{name="Scarlet Library",activityIDs={1}},"Can we join?")
total,unread=apps.Counts()
assert(total==1 and unread==0,"repeat whisper must not create another application")

listener.OnEvent(listener,"CHAT_MSG_WHISPER","Yes, invite coming","Alice-Realm")
total,unread=apps.Counts()
assert(total==1 and unread==1,"incoming matched reply increments unread")
assert(apps.StatusFor(one)=="Replied","reply status follows the original record")

listener.OnEvent(listener,"CHAT_MSG_WHISPER","Hi","Different-Realm")
total,unread=apps.Counts()
assert(unread==1,"unrelated whispers must not attach to the application")

-- Realm suffixes: an ambiguous basename cannot be assigned to the wrong person.
local two={leader="Alice-Different",key="alice:2",started=81}
apps.TrackSent(two,{name="Razorfen",activityIDs={2}},"LFG DPS")
total,unread=apps.Counts()
assert(total==2 and unread==1)
listener.OnEvent(listener,"CHAT_MSG_WHISPER","Ambiguous sender","Alice")
total,unread=apps.Counts()
assert(unread==1,"unqualified ambiguous sender must not be assigned")

listener.OnEvent(listener,"CHAT_MSG_WHISPER","Second reply","Alice-Different")
total,unread=apps.Counts()
assert(unread==2 and apps.StatusFor(two)=="Replied","second group tracks its own reply")

apps.ListingEnded(one)
assert(apps.StatusFor(one)=="Replied","ended listings retain chat history/status")
local three={leader="Bob",key="bob:3",started=90}
apps.TrackSent(three,{name="Deadmines",activityIDs={3}},"LFG healer")
total,unread=apps.Counts()
assert(total==3 and unread==2)
assert(apps.StatusFor(three)=="Sent")
print("Applications smoke tests passed.")
