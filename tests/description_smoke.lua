-- WoW Lua 5.1 regression checks: Group Finder Kstrings must reach the
-- native renderer unmodified rather than being parsed by addon Lua.
local source=assert(io.open("ForeverQuickJoin.lua","rb")):read("*a")
local function Piece(first,last)
    local start=assert(source:find("local function "..first.."(",1,true),"Missing "..first)
    local finish=assert(source:find("\nlocal function "..last.."(",start,true),
        "Missing end for "..first)
    return source:sub(start,finish-1):gsub("^local function ","function ",1)
end
local env={Readable=function(value) return value end}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(Piece("SafeMarkup","DescriptionForDisplay").."\n"..
    Piece("DescriptionForDisplay","PopulateMemberDetails").."\n"..
    "return SafeMarkup,DescriptionForDisplay"))
setfenv(chunk,env)
local _,display=chunk()
assert(display("|Kt116|k")=="|Kt116|k","Forever Kstrings pass through intact")
assert(display("|Kr123|k")=="|Kr123|k","native Group Finder Kstrings pass through intact")
assert(display("LFM for Bride of the Embalmer")=="LFM for Bride of the Embalmer")
assert(display("foo |Tnottrusted:16|t")=="foo ||Tnottrusted:16||t",
    "ordinary untrusted strings cannot inject texture markup")
assert(display(nil)==nil and display("")==nil,"empty comments remain absent")
assert(display("first\nsecond")=="first second","ordinary multiline text is sanitized")
assert(source:find('row.detailsComment:SetText(comment)',1,true),
    "expanded description is rendered without concatenation or truncation")
assert(source:find('row.detailsComment:GetStringHeight()',1,true),
    "expanded details measure the rendered text")
assert(source:find('GameTooltip:AddLine(row.descriptionDisplay,1,1,1,true)',1,true),
    "mouseover tooltip displays entire description with wrapping")
assert(source:find('row.descriptionPreview:SetText(description)',1,true),
    "single-line preview passes protected text unchanged")
assert(source:find('row.noteIcon:SetShown(description~=nil)',1,true),
    "notes icon should reflect descriptions")
assert(source:find('row.expand:SetHeight(headerHeight)',1,true),
    "clickable row includes description preview")
assert(source:find('headerHeight + PopulateMemberDetails(row, resultID, info)',1,true),
    "expanded layout accounts for the preview")
assert(not source:find('SafeMarkup(Truncate(comment,',1,true),
    "prevent regression to old protected-text escape-and-truncate bug")
assert(not source:find('string.find(info.comment',1,true),
    "protected content must not be searched")
print("Protected description tests passed.")
