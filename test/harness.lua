-- Mock WoW API harness for Bean Counter
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat+1] = m end }
local function clearChat() for i=#chat,1,-1 do chat[i]=nil end end
local function chatHas(p) for _,m in ipairs(chat) do if m:find(p, 1, true) then return true end end return false end
local fails, passes = 0, 0
local function ok(c, name) if c then passes = passes + 1 else fails = fails + 1 print("FAIL: "..name) end end

-- items: id -> {name, texture, icon}
local ITEMS = {
  [2770] = {"Copper Ore", "Interface\\Icons\\INV_Ore_Copper_01"},
  [2771] = {"Tin Ore", "Interface\\Icons\\INV_Ore_Tin_01"},
  [2835] = {"Rough Stone", "Interface\\Icons\\INV_Stone_06"},
  [2589] = {"Linen Cloth", "Interface\\Icons\\INV_Fabric_Linen_01"},
  [2840] = {"Copper Bar", "Interface\\Icons\\INV_Ingot_02"},
}
local counts = { [2770] = 3, [2771] = 12, [2835] = 0, [2589] = 20, [2840] = 7 }
local bags = { [0] = { [1] = {id=2770, n=3, link="|cffffffff|Hitem:2770|h[Copper Ore]|h|r"} } }
NUM_BAG_SLOTS = 4
NUM_REAGENTBAG_SLOTS = 0

C_Item = {
  GetItemCount = function(id, includeBank)
    ok(includeBank == false, "GetItemCount asked for bags only")
    return counts[id] or 0
  end,
  GetItemInfo = function(id)
    local d = ITEMS[id]; if not d then return end
    return d[1], "|cffffffff|Hitem:"..id.."|h["..d[1].."]|h|r", 1, 1, 1, "", "", 1, "", d[2]
  end,
  GetItemIconByID = function(id) local d = ITEMS[id]; return d and d[2] end,
}
C_Container = {
  GetContainerItemInfo = function(bag, slot)
    local it = bags[bag] and bags[bag][slot]
    if not it then return nil end
    return { itemID = it.id, stackCount = it.n, hyperlink = it.link }
  end,
  GetContainerItemID = function(bag, slot)
    local it = bags[bag] and bags[bag][slot]
    return it and it.id
  end,
}

local shift, alt, ctrl, chatShown = false, false, false, false
function IsShiftKeyDown() return shift end
function IsAltKeyDown() return alt end
function IsControlKeyDown() return ctrl end
function ChatEdit_GetActiveWindow()
  if chatShown then return { IsShown = function() return true end } end
end

function ContainerFrameItemButton_OnModifiedClick() end
function ContainerFrameItemButton_OnClick() end
ContainerFrameItemButtonMixin = { OnModifiedClick = function() end, OnClick = function() end }

local timers, now = {}, 100
C_Timer = { After = function(s, f) timers[#timers+1] = { s = s, f = f } end }
local function runTimers()
  local n = 0
  while #timers > 0 and n < 200 do
    local t = table.remove(timers, 1); t.f(); n = n + 1
  end
end
function GetTime() return now end

SlashCmdList = {}
local frames, hooked = {}, {}
local function mkFrame(ftype, name, parent, template)
  local f = { scripts = {}, events = {}, shown = true, ftype = ftype, name = name, template = template, points = {}, size = {0,0} }
  setmetatable(f, { __index = function(t, k) return function() end end })
  f.RegisterEvent = function(self, e) self.events[e] = true end
  f.UnregisterEvent = function(self, e) self.events[e] = nil end
  f.SetScript = function(self, k, fn) self.scripts[k] = fn end
  f.GetScript = function(self, k) return self.scripts[k] end
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  f.IsShown = function(self) return self.shown end
  f.IsVisible = function(self) return self.shown end
  f.SetText = function(self, t) self.text = t end
  f.GetText = function(self) return rawget(self, "text") or "" end
  f.SetTextColor = function(self, r,g,b) self.r, self.g, self.b = r,g,b end
  f.SetSize = function(self, w, h) self.size = {w,h} end
  f.SetPoint = function(self, ...) self.points[#self.points+1] = {...}; self.point = {...} end
  f.ClearAllPoints = function(self) self.points, self.point = {}, nil end
  f.GetPoint = function(self)
    local p = self.point
    if p then return p[1], UIParent, p[3] or p[1], p[4] or 0, p[5] or 0 end
  end
  f.SetFocus = function(self) self.focus = true end
  f.HasFocus = function(self) return rawget(self, "focus") or false end
  f.ClearFocus = function(self) self.focus = false end
  f.EnableMouse = function(self, v) self.mouse = v and true or false end
  f.RegisterForDrag = function(self, ...) self.drag = {...} end
  f.RegisterForClicks = function(self, ...) self.clicks = {...} end
  f.StartMoving = function(self) self.moving = true end
  f.StopMovingOrSizing = function(self) self.moving = false end
  f.SetMovable = function(self, v) self.movable = v end
  f.SetClampedToScreen = function(self, v) self.clamped = v end
  f.SetFrameStrata = function(self, s) self.strata = s end
  f.SetAutoFocus = function(self, v) self.autofocus = v end
  f.SetNumeric = function(self, v) self.numeric = v end
  f.SetMaxLetters = function(self, n) self.maxLetters = n end
  f.CreateFontString = function(self) return mkFrame("FontString") end
  f.CreateTexture = function(self)
    local t = mkFrame("Texture")
    t.SetTexture = function(self, tex) self.tex = tex return true end
    t.GetTexture = function(self) return self.tex end
    t.SetAllPoints = function() end
    return t
  end
  f.GetParent = function(self) return parent end
  f.GetID = function(self) return rawget(self, "id") end
  frames[#frames+1] = f
  if name then _G[name] = f end
  return f
end
function CreateFrame(...) return mkFrame(...) end
UIParent = mkFrame("Frame", "UIParent")
GameTooltip = setmetatable({
  lines = {},
  SetOwner = function(self, o, a) self.owner, self.anchor, self.lines = o, a, {} end,
  SetHyperlink = function(self, l) self.link = l end,
  AddLine = function(self, text) self.lines[#self.lines+1] = text end,
  Show = function(self) self.shown = true end,
  Hide = function(self) self.shown = false end,
}, { __index = function() return function() end end })

function hooksecurefunc(a, b, c)
  if type(a) == "table" then
    hooked[tostring(a) .. "." .. b] = hooked[tostring(a) .. "." .. b] or {}
    table.insert(hooked[tostring(a) .. "." .. b], c)
  else
    hooked[a] = hooked[a] or {}
    table.insert(hooked[a], b)
  end
end
local function fireHook(name, ...)
  for _, fn in ipairs(hooked[name] or {}) do fn(...) end
end

local chunk = assert(loadfile("../BeanCounterForever/BeanCounterForever.lua"))
chunk("BeanCounterForever")
local T = BeanCounterForever
ok(T and T.VERSION == "1.0.2", "version 1.0.2")
ok(SLASH_BEANCOUNTER1 == "/beans" and SLASH_BEANCOUNTER2 == "/tally" and SlashCmdList.BEANCOUNTER, "slash commands /beans and /tally")

local ev = T._ev
ok(ev and ev.events.ADDON_LOADED and ev.events.PLAYER_LOGIN and ev.events.BAG_UPDATE, "events registered")
local function fire(e, ...) ev.scripts.OnEvent(ev, e, ...) end
fire("ADDON_LOADED", "BeanCounterForever"); fire("PLAYER_LOGIN")
ok(type(BeanCounterCharDB) == "table" and type(BeanCounterCharDB.items) == "table" and BeanCounterCharDB.locked == false, "per-character defaults")
ok(BeanCounterForeverFrame and not BeanCounterForeverFrame.shown, "named bar frame exists and is hidden when empty at login")
ok(BeanCounterForeverGoalBox and not BeanCounterForeverGoalBox.shown, "named goal box starts hidden")
ok(hooked.ContainerFrameItemButton_OnModifiedClick and hooked.ContainerFrameItemButton_OnClick, "bag click hooks installed")
ok(hooked[tostring(ContainerFrameItemButtonMixin) .. ".OnModifiedClick"], "mixin OnModifiedClick hooked")

-- Colour / text helpers (no UI)
ok(T.CountText(3, nil) == "3" and T.CountText(3, 10) == "3/10", "count text format")
local r,g,b = T.CountColor(3, 10)
ok(r == 1 and g == 1 and b == 1, "count is white below the goal")
r,g,b = T.CountColor(10, 10)
ok(r == 0.2 and g == 1 and b == 0.2, "count is green at the goal")
r,g,b = T.CountColor(15, 10)
ok(r == 0.2 and g == 1, "count stays green above the goal")
ok(not T.GoalMet(9, 10) and T.GoalMet(10, 10) and T.GoalMet(11, 10) and not T.GoalMet(11, nil), "goal met checks")

-- Bags-only count
ok(T.Count(2770) == 3, "count copper from bags")
ok(T.Count(2771) == 12, "count tin from bags")

-- Add / cap / duplicate
ok(T.Add(2770) == true and #T.Items() == 1, "add first item")
ok(chatHas("Tracking"), "chat notes a new track")
clearChat()
ok(T.Add(2770) == false, "duplicate add refused")
ok(chatHas("Already tracking"), "chat notes a duplicate")
ok(T.Add(2771) and T.Add(2835) and T.Add(2589) and #T.Items() == 4, "four items tracked")
clearChat()
ok(T.Add(2840) == false and #T.Items() == 4, "fifth item refused")
ok(chatHas("only track 4") or chatHas("only track"), "chat notes the cap")
ok(BeanCounterCharDB.items[1].id == 2770 and BeanCounterCharDB.items[4].id == 2589, "saved in order on the character")

-- Goals
ok(T.SetGoal(2770, 20) and T.Find(2770).goal == 20, "set a goal")
ok(T.CountText(T.Count(2770), T.Find(2770).goal) == "3/20", "goal shows as have/need")
r,g,b = T.CountColor(T.Count(2770), T.Find(2770).goal)
ok(r == 1, "copper is still white at 3/20")
counts[2770] = 20
T.Refresh()
r,g,b = T.CountColor(T.Count(2770), T.Find(2770).goal)
ok(g == 1 and r == 0.2, "copper turns green at 20/20")
counts[2770] = 25
T.Refresh()
ok(T.CountText(T.Count(2770), T.Find(2770).goal) == "25/20", "keeps counting above the goal")
ok(T.SetGoal(2770, 0) and T.Find(2770).goal == nil, "goal 0 clears the goal")

-- Remove / clear
ok(T.Remove(2835) and #T.Items() == 3 and not T.Find(2835), "remove one item")
T.Clear()
ok(#T.Items() == 0, "clear empties the list")

-- Slash: add from a link, goal, remove, lock, reset, help
clearChat()
SlashCmdList.BEANCOUNTER("add |cffffffff|Hitem:2770|h[Copper Ore]|h|r")
ok(T.Find(2770), "slash add from an item link")
SlashCmdList.BEANCOUNTER("goal 40")
ok(T.Find(2770).goal == 40, "slash goal N applies to the last item")
SlashCmdList.BEANCOUNTER("add |cffffffff|Hitem:2771|h[Tin Ore]|h|r")
SlashCmdList.BEANCOUNTER("goal |cffffffff|Hitem:2771|h[Tin Ore]|h|r 8")
ok(T.Find(2771).goal == 8, "slash goal [item] N")
counts[2771] = 12
ok(T.GoalMet(T.Count(2771), T.Find(2771).goal), "tin is over its goal")
SlashCmdList.BEANCOUNTER("remove |cffffffff|Hitem:2771|h[Tin Ore]|h|r")
ok(not T.Find(2771), "slash remove from a link")
SlashCmdList.BEANCOUNTER("lock")
ok(BeanCounterCharDB.locked == true, "slash lock")
SlashCmdList.BEANCOUNTER("unlock")
ok(BeanCounterCharDB.locked == false, "slash unlock")
BeanCounterForeverFrame.point = {"CENTER", UIParent, "CENTER", 12, 34}
-- GetPoint is used on drag stop; set pos via Reset then manual
BeanCounterCharDB.pos = {"CENTER", "CENTER", 12, 34}
SlashCmdList.BEANCOUNTER("reset")
ok(BeanCounterCharDB.pos == nil, "slash reset clears saved position")
clearChat()
SlashCmdList.BEANCOUNTER("help")
ok(chatHas("/beans add") and chatHas("start or stop tracking") and chatHas("/tally still works") and not chatHas("Ctrl-click"), "slash help")
SlashCmdList.BEANCOUNTER("clear")
ok(#T.Items() == 0, "slash clear")

-- Alt+right-click on a bag button toggles the item; other modifiers do not.
local btn = { id = 1, GetID = function(self) return 1 end, GetBag = function() return 0 end }
shift, alt, ctrl, chatShown = false, true, false, false
clearChat()
T.OnBagClick(btn, "RightButton")
ok(T.Find(2770), "alt-right-click on a bag item tracks it")
ok(chatHas("Tracking"), "chat says Tracking")
ok(BeanCounterForeverFrame.shown, "bar is shown once an item is tracked")
now = now + 1
clearChat()
T.OnBagClick(btn, "RightButton")
ok(not T.Find(2770), "alt-right-click the same item again untracks it")
ok(chatHas("Removed"), "chat says Removed")
ok(not BeanCounterForeverFrame.shown, "bar hides when the last item is toggled off")
-- re-add for the remaining click tests
now = now + 1
T.OnBagClick(btn, "RightButton")
ok(T.Find(2770), "alt-right-click tracks again after a toggle off")
T.Clear()
ok(not BeanCounterForeverFrame.shown, "bar hides when the list is cleared")
-- Alt+left is left alone (Bagnon Flash Find / Auctionator sell shortcut)
T.OnBagClick(btn, "LeftButton")
ok(not T.Find(2770), "alt-left-click does not track")
-- Shift+right no longer tracks (it splits stacks in Bagnon)
alt, shift = false, true
T.OnBagClick(btn, "RightButton")
ok(not T.Find(2770), "shift-right-click does not track")
shift = false
-- Ctrl or Shift held with Alt: leave it alone
alt, ctrl = true, true
T.OnBagClick(btn, "RightButton")
ok(not T.Find(2770), "no track on alt+ctrl+right-click")
ctrl, shift = false, true
T.OnBagClick(btn, "RightButton")
ok(not T.Find(2770), "no track on alt+shift+right-click")
shift = false
-- Fire the actual hooksecurefunc path (advance time so the click debounce does not swallow it)
now = now + 1
alt = true
fireHook("ContainerFrameItemButton_OnModifiedClick", btn, "RightButton")
ok(T.Find(2770), "OnModifiedClick hook tracks alt-right-click")
-- Bank bag (bag 7) is ignored
local bankBtn = { GetBag = function() return 7 end, GetID = function() return 1 end, info = { itemID = 2840 } }
bags[7] = { [1] = {id=2840, n=2, link="|cffffffff|Hitem:2840|h[Copper Bar]|h|r"} }
T.OnBagClick(bankBtn, "RightButton")
ok(not T.Find(2840), "bank bag clicks are ignored (Bagnon uses shift-right there)")

-- BAG_UPDATE is bucketed: two events, one refresh after the timer
local refreshes = 0
local realRefresh = T.Refresh
T.Refresh = function() refreshes = refreshes + 1 return realRefresh() end
fire("BAG_UPDATE", 0)
fire("BAG_UPDATE", 1)
ok(refreshes == 0, "BAG_UPDATE does not refresh immediately")
ok(#timers == 1 and timers[1].s == 0.1, "BAG_UPDATE is bucketed to 0.1s")
runTimers()
ok(refreshes == 1, "one refresh after the bucket")
T.Refresh = realRefresh

-- Empty bar is hidden whether it is locked or not
T.Clear(); T.SetLocked(true); T.Refresh()
ok(not BeanCounterForeverFrame.shown, "locked empty bar is hidden")
T.SetLocked(false); T.Refresh()
ok(not BeanCounterForeverFrame.shown, "unlocked empty bar is hidden")
T.Add(2770); T.Refresh()
ok(BeanCounterForeverFrame.shown, "bar returns when an item is added")
T.Clear()

-- InitDB sanitizes bad saved data
local clean = T.InitDB({ items = { {id=2770, goal=5}, {id=2770, goal=9}, {id=0}, "x", {id=2771} }, locked = "yes" })
ok(#clean.items == 2 and clean.items[1].id == 2770 and clean.items[1].goal == 5 and clean.locked == false, "InitDB sanitizes items and lock")

-- Reload uses the saved character table
BeanCounterCharDB = { items = { {id=2589, goal=100} }, locked = true }
T.InitDB(BeanCounterCharDB)
ok(T.Find(2589) and T.Find(2589).goal == 100 and T.db.locked, "reloads per-character saved items")

-- Optional migrate from a leftover TallyCharDB
TallyCharDB = { items = { {id=2770, goal=15} }, locked = true, pos = {"TOP", "TOP", 0, -20} }
local migrated = T.InitDB({})
ok(migrated.items[1].id == 2770 and migrated.items[1].goal == 15 and migrated.locked == true
   and migrated.pos[1] == "TOP", "migrates a leftover TallyCharDB when Bean Counter data is empty")
local kept = T.InitDB({ items = { {id=2771} } })
ok(kept.items[1].id == 2771 and #kept.items == 1, "does not overwrite existing Bean Counter data with Tally")
TallyCharDB = nil

if fails > 0 then print("passes="..passes.." fails="..fails) else print("passes="..passes.." fails=0") end
return fails
