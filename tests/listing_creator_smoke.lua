-- WoW Lua 5.1: integrated creator, navigation, privacy and package smoke test.
local toc=assert(io.open("ForeverQuickJoin.toc","rb")):read("*a")
local main=assert(io.open("ForeverQuickJoin.lua","rb")):read("*a")
local host=assert(io.open("ForeverQuickJoin_Host.lua","rb")):read("*a")
local listing=assert(io.open("ForeverQuickJoin_Listing.lua","rb")):read("*a")

local function has(where,what)
    assert(where:find(what,1,true), "Missing "..what)
end
has(toc,"\nForeverQuickJoin_Listing.lua\n")
has(toc,"ForeverQuickJoinListingDB")
assert(toc:match("## Version: %d+%.%d+%.%d+"), "Missing semantic addon version")
assert(not main:find("Click a row to view members",1,true),
    "obsolete helper text must be removed from Finder source")
assert(not main:find("AttachResizeGrip(",1,true),"resize grip must be removed")
assert(not main:find("ClampWindowScale(",1,true),"dynamic scaling must be removed")
has(main,"window:SetSize(840, 785)")
has(main,"window:SetScale(1)")

-- The main navigation and existing inbox are preserved, not replaced.
has(listing,'topHostingTab:SetText("Create Listing")')
has(listing,'existingButton:SetText("Manage Listing")')
has(listing,'Button(navOverlay,"Applicants"')
has(listing,'Button(applications,"Back to Listings"')
has(listing,'SelectMainTab("find")')
has(listing,'SelectMainTab("listing")')
has(listing,'local function HideApplicantUnderlay()')
has(listing,'local function RestoreApplicantUnderlay(')
has(listing,'ShowPartySummary(true)')
has(listing,'EnsureSolidRoleManager("theme switched")')
has(listing,'ApplyCreatorTransparency("theme menu changed",true)')
has(listing,'AlignFinderActions(window)')
has(listing,'local function HideObsoleteFinderHint()')

-- Multi-dungeon selection and explicit player-clicked listing operations.
has(listing,'local function FilteredActivities()')
has(listing,'root:CreateCheckbox(caption,')
has(listing,'selectedIDs[#selectedIDs+1]=id')
has(listing,'C_LFGList.CreateListing({')
has(listing,'C_LFGList.UpdateListing({')
has(listing,'C_LFGList.RemoveListing()')
has(listing,'generalPlaystyle=selectedStyle')
has(listing,'generalPlaystyle=style')
has(listing,'newPlayerFriendly=friendlyCheck')
has(listing,'lastAttempt={kind=op')
has(listing,'if not delistArmed then')
has(listing,'C_Timer.After(1.5,function() Snapshot(')

-- The protected, actual Blizzard editor is docked and restored, not copied.
has(listing,'local function DockEditor()')
has(listing,'scroll:SetParent(editorSlot)')
has(listing,'prior.scroll:SetParent(prior.parent)')
has(listing,'local function RestoreEditor(')
has(listing,'prior.edit:SetWidth(prior.dimensions.editW)')
has(listing,'local function CurrentTheme()')
has(listing,'SLASH_FQJLISTINGDEBUG1="/qjlisting"')
assert(not listing:find("ForeverQuickJoinHostPreviewDB",1,true),
    "production must not depend on a companion addon")
assert(not listing:find("MANAGE LISTING  [TEST]",1,true),
    "preview title should not be in release")
has(host,'Label(panel,"APPLICANT INBOX"')

-- Production UI must not display test-lab diagnostics or tutorial strings.
for _,old in ipairs({
    '"Export Listing Log"',
    '"Verify Listing"',
    '"The description is protected; QuickJoin never reads, pastes,"',
    '"or programmatically edits its contents."',
    '"Update checks playstyle after posting; Delist needs two clicks."',
    '"Clear old description manually before a new listing."',
    'statusText=Label(',
    'statusText:SetText(',
}) do
    assert(not listing:find(old,1,true),"obsolete creator UI text/control: "..old)
end
assert(not main:find("Whisper: {level} {class} {role} {activity} {location} {party} {partycount}",1,true),
    "whisper token-helper label must be removed")
assert(not main:find("No groups match your filters",1,true),
    "empty-filter results hint must not appear")
-- Keep core functionality and optional slash-only diagnostics available.
has(listing,'if arg=="export" then ExportLog()')
has(listing,'elseif arg=="verify" then Snapshot("slash command")')
has(listing,'local function CreateOnClick()')
has(listing,'local function UpdateOnClick()')
has(listing,'local function DelistOnClick()')
has(main,'messageBox = CreateFrame("EditBox"')
has(main,'previewLabel = MakeLabel(')
print("Integrated listing creator tests passed.")
