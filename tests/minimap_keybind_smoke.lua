-- WoW Lua 5.1 regression for current minimap binding tooltip.
local f=assert(io.open("ForeverQuickJoin.lua","rb"))
local source=f:read("*a");f:close()
local start=assert(source:find("local function CurrentToggleBindingText()",1,true))
local finish=assert(source:find("\nlocal function CreateMinimapButton()",start,true))
local code=source:sub(start,finish-1):gsub("^local function ","function ",1)
local keys={"CTRL-I"}
local calls={}
local env={
    GetBindingKey=function(command)
        calls[#calls+1]=command
        return unpack(keys)
    end,
    GetBindingText=function(key,prefix,abbrev)
        assert(prefix=="KEY_" and abbrev==false,
            "Use Blizzard's full localized label")
        return ({["CTRL-I"]="Ctrl+I",["SHIFT-F7"]="Shift+F7",
                 ["ALT-MOUSEWHEELUP"]="Alt+Mouse Wheel Up"})[key]
    end,
}
setmetatable(env,{__index=_G})
local fn=assert(loadstring(code.."\nreturn CurrentToggleBindingText"))
setfenv(fn,env)
local current=fn()
assert(current()=="Ctrl+I","current default should be presented, not hardcoded")
keys={"SHIFT-F7"}
assert(current()=="Shift+F7","changed binding takes effect on next hover")
keys={"SHIFT-F7","CTRL-I"}
assert(current()=="Shift+F7 / Ctrl+I","show both key assignments")
keys={"ALT-MOUSEWHEELUP"}
assert(current()=="Alt+Mouse Wheel Up","native formatting supports mouse bindings")
env.GetBindingText=nil
assert(current()=="ALT-MOUSEWHEELUP","raw key fallback without text formatter")
keys={}
assert(current()=="Not bound","unassigned action must not claim default")
env.GetBindingKey=nil
assert(current()=="Unavailable","missing API should be acknowledged")
assert(#calls>=6,"query the native keybinding each time")
for _,name in ipairs(calls) do
    assert(name=="FOREVERQUICKJOIN_TOGGLE",
        "never inspect or modify unrelated bindings")
end
assert(source:find('GameTooltip:AddLine("Keybind: "..CurrentToggleBindingText()',1,true),
    "minimap tooltip must display current shortcut at mouseover")
assert(source:find('minimapButton:SetScript("OnEnter", function(self)',1,true),
    "lookup should happen on hover, not at login")
assert(not source:find("SetBinding(",1,true)
    and not source:find("SaveBindings(",1,true),
    "tooltip must not edit any player's keybindings")
print("Minimap binding tooltip tests passed.")
