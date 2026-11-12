-- WoW Lua 5.1: minimap tooltip should display full modifier names.
local f=assert(io.open("ForeverQuickJoin.lua","rb"))
local source=f:read("*a");f:close()
local start=assert(source:find("local function FormatBindingKey()",1,true))
local finish=assert(source:find("\nlocal function CreateMinimapButton()",start,true))
local code=source:sub(start,finish-1):gsub("^local function ","function ",1)
local keys={"CTRL-I"}
local calls={}
local textCalls={}
local env={
    GetBindingKey=function(command)
        calls[#calls+1]=command
        return unpack(keys)
    end,
    GetBindingText=function(key,prefix,abbrev)
        textCalls[#textCalls+1]=key
        assert(prefix=="KEY_" and abbrev==false)
        -- Forever returns an abbreviated label if asked to format the whole
        -- binding. The helper must use raw modifier tokens instead.
        return ({["CTRL-I"]="c+I",I="I",F7="F7",
                 MOUSEWHEELUP="Mouse Wheel Up",BUTTON4="Mouse Button 4"})[key]
    end,
}
setmetatable(env,{__index=_G})
local fn=assert(loadstring(code.."\nreturn FormatBindingKey,CurrentToggleBindingText"))
setfenv(fn,env)
local format,current=fn()
assert(current()=="Ctrl + I","expand c+I to Ctrl + I")
assert(textCalls[1]=="I","do not pass CTRL-I to GetBindingText")
keys={"SHIFT-F7"}
assert(current()=="Shift + F7","changed binding takes effect on next hover")
keys={"CTRL-SHIFT-I"}
assert(current()=="Ctrl + Shift + I","combined modifiers are readable")
keys={"ALT-MOUSEWHEELUP"}
assert(current()=="Alt + Mouse Wheel Up","mouse keys use local labels")
keys={"CTRL-BUTTON4"}
assert(current()=="Ctrl + Mouse Button 4","mouse buttons are readable")
keys={"CTRL-I","SHIFT-F7"}
assert(current()=="Ctrl + I / Shift + F7","display both key assignments")
keys={"I"}
assert(current()=="I","unmodified key remains readable")
env.GetBindingText=nil
keys={"CTRL-I"}
assert(current()=="Ctrl + I","no native formatter still expands modifiers")
keys={"ALT-MOUSEWHEELUP"}
assert(current()=="Alt + MOUSEWHEELUP","fallback raw key names without formatter")
keys={}
assert(current()=="Not bound","unassigned keys are not claimed")
env.GetBindingKey=nil
assert(current()=="Unavailable","missing API is acknowledged")
for _,name in ipairs(calls) do
    assert(name=="FOREVERQUICKJOIN_TOGGLE",
        "never inspect or modify unrelated bindings")
end
assert(source:find('GameTooltip:AddLine("Keybind: "..CurrentToggleBindingText()',1,true),
    "tooltip should use current binding")
assert(source:find('minimapButton:SetScript("OnEnter", function(self)',1,true),
    "binding is read on hover")
assert(not source:find("SetBinding(",1,true)
    and not source:find("SaveBindings(",1,true),
    "tooltip must never modify saved keybindings")
print("Minimap modifier keybinding tooltip tests passed.")
