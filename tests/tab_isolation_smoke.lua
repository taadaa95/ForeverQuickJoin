-- Lua 5.1 regression for transparency-safe tab switching.
-- The Finder must be hidden, not merely covered by a translucent panel.
local function Read(path)
    local handle=assert(io.open(path,"rb"))
    local source=handle:read("*a")
    handle:close()
    return source
end
local finder=Read("ForeverQuickJoin.lua")
local host=Read("ForeverQuickJoin_Host.lua")
local party=Read("ForeverQuickJoin_Party.lua")
local theme=Read("ForeverQuickJoin_Theme.lua")

-- All persistent Finder elements, not just its row list, must be children
-- of a single frame hidden by tab changes.
for _,token in ipairs({
    'findContent=CreateFrame("Frame","ForeverQuickJoinFindContent",window)',
    'findContent:SetAllPoints(window)',
    'window.QuickJoinSetFinderVisible=function(visible)',
    'if visible then findContent:Show() else findContent:Hide() end',
    'BuildSearchControls(findContent)',
    'advancedButton = CreateFrame("Button", nil, findContent',
    'advancedPanel = CreateFrame("Frame", "ForeverQuickJoinAdvancedFilters", findContent',
    'resultsViewport = CreateFrame("ScrollFrame", nil, findContent',
    'templateResetButton = CreateFrame("Button", nil, findContent',
    'messageBox = CreateFrame("EditBox", nil, findContent',
    'previewLabel = MakeLabel(findContent',
    'statusLabel = MakeLabel(findContent',
    'pageLabel = MakeLabel(findContent',
}) do
    assert(finder:find(token,1,true),"Finder UI must use isolated view: "..token)
end
assert(finder:find('MakeLabel(window, "Forever QuickJoin"',1,true),
    "Persistent window title must not be in hidden Finder container")
assert(host:find('findTab = Button(window,"Find Groups"',1,true),
    "Navigation must remain mounted on the always-visible root frame")
assert(theme:find('return .58 end',1,true),
    "Keep transparency in both themes instead of masking the issue by opacity")

-- Exercise the actual Host.OpenList/Find/Applications functions under a
-- minimal host environment, including an explicitly translucent backdrop.
local function Panel()
    return {
        shown=false,
        Show=function(self)self.shown=true end,
        Hide=function(self)self.shown=false end
    }
end
local function Button()
    return {
        enabled=true,
        Enable=function(self)self.enabled=true end,
        Disable=function(self)self.enabled=false end,
    }
end
local findView=Panel()
findView:Show()
local hostPanel=Panel()
local appsPanel=Panel()
local summary=Panel()
summary:Show()
local hideAdvancedCount=0
local win={
    shown=true,
    Show=function(self)self.shown=true end,
    QuickJoinSetFinderVisible=function(visible)
        if visible then findView:Show() else findView:Hide() end
    end,
    QuickJoinHideAdvanced=function()
        hideAdvancedCount=hideAdvancedCount+1
    end,
}
local apps={
    Open=function()appsPanel:Show() end,
    Hide=function()appsPanel:Hide() end,
}
local roles={
    SetSummaryVisible=function(visible)
        if visible then summary:Show() else summary:Hide() end
    end,
}
local env={
    Host={Redraw=function()end},
    panel=hostPanel,
    window=win,
    findTab=Button(),
    hostTab=Button(),
    applicationsTab=Button(),
    ForeverQuickJoinApplications=apps,
    ForeverQuickJoinParty=roles,
    UpdateListingUI=function()end,
}
setmetatable(env,{__index=_G})
local a=assert(host:find("function Host.OpenList()",1,true))
local b=assert(host:find("\nlocal watcher=",a,true))
local execute=assert(loadstring(host:sub(a,b-1).."\nreturn Host"))
setfenv(execute,env)
local Host=execute()
local function AssertView(which)
    if which=="find" then
        assert(findView.shown and not hostPanel.shown and not appsPanel.shown,
            "Find Groups must only show Finder content")
        assert(summary.shown,"Party summary visible in Find")
        assert(not env.findTab.enabled and env.hostTab.enabled and env.applicationsTab.enabled,
            "Find tab button state")
    elseif which=="list" then
        assert(not findView.shown and hostPanel.shown and not appsPanel.shown,
            "Hosting must hide Finder even if overlay is translucent")
        assert(summary.shown,"Party summary visible in List Group")
        assert(env.findTab.enabled and not env.hostTab.enabled and env.applicationsTab.enabled,
            "List tab button state")
    elseif which=="apps" then
        assert(not findView.shown and not hostPanel.shown and appsPanel.shown,
            "Applications must hide Finder and host panels")
        assert(not summary.shown,"Party summary must not bleed into Applications")
        assert(env.findTab.enabled and env.hostTab.enabled and not env.applicationsTab.enabled,
            "Applications tab button state")
    end
end
Host.OpenList(); AssertView("list")
Host.OpenApplications(); AssertView("apps")
Host.OpenFind(); AssertView("find")
Host.OpenApplications(); AssertView("apps")
Host.OpenList(); AssertView("list")
Host.OpenFind(); AssertView("find")
assert(hideAdvancedCount==4,"Leaving Finder/hosting for other tabs must close advanced drawer")
assert(party:find("function Party.SetSummaryVisible(visible)",1,true),
    "The party manager must offer summary visibility control")
assert(party:find("if visible then summary:Show() else summary:Hide() end",1,true),
    "The shared party summary uses explicit visibility")
assert(finder:find('searchButton:SetScript("OnClick", SearchFromClick)',1,true),
    "Protected Group Finder search must still require a direct click")
print("Tab isolation/transparency smoke tests passed.")
