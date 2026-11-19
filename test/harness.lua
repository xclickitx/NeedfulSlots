-- Mock WoW API harness for Needful Slots (formerly Bean Counter)
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat+1] = m end }
local function clearChat() for i=#chat,1,-1 do chat[i]=nil end end
local function chatHas(p) for _,m in ipairs(chat) do if m:find(p, 1, true) then return true end end return false end
local fails, passes = 0, 0
inCombat, protectedCalls, USE_ID = false, {}, nil
function InCombatLockdown() return inCombat end
ATTRIBUTE_NOOP = ""
local function ok(c, name) if c then passes = passes + 1 else fails = fails + 1 print("FAIL: "..name) end end

-- items: id -> {name, texture, icon}
local ITEMS = {
  [2770] = {"Copper Ore", "Interface\\Icons\\INV_Ore_Copper_01"},
  [2771] = {"Tin Ore", "Interface\\Icons\\INV_Ore_Tin_01"},
  [2835] = {"Rough Stone", "Interface\\Icons\\INV_Stone_06"},
  [2589] = {"Linen Cloth", "Interface\\Icons\\INV_Fabric_Linen_01"},
  [2840] = {"Copper Bar", "Interface\\Icons\\INV_Ingot_02"},
  [1113] = {"Conjured Bread", "Interface\\Icons\\INV_Misc_Food_09"},
}
local counts = { [2770] = 3, [2771] = 12, [2835] = 0, [2589] = 20, [2840] = 7, [1113] = 10 }
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
  GetItemSpell = function(id) if id == USE_ID then return "Food", 433 end end,
  IsUsableItem = function(id) return id == USE_ID end,
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
  f.attrs = {}
  f.SetAttribute = function(self, k, v)
    if inCombat and template and template:find("Secure") then protectedCalls[#protectedCalls+1] = "SetAttribute " .. k end
    self.attrs[k] = v
  end
  f.GetAttribute = function(self, k) return self.attrs[k] end
  f.HookScript = function(self, k, fn) self.scripts[k] = fn end
  if (template and template:find("Secure")) or name == "NeedfulSlotsFrame" then
    for _, m in ipairs({"Show", "Hide", "SetPoint", "ClearAllPoints", "SetSize", "RegisterForDrag", "EnableMouse", "StartMoving"}) do
      local orig = f[m]
      f[m] = function(self, ...)
        if inCombat then protectedCalls[#protectedCalls+1] = m end
        return orig(self, ...)
      end
    end
  end
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

local chunk = assert(loadfile("../NeedfulSlots/NeedfulSlots.lua"))
local ns = {}
chunk("NeedfulSlots", ns)
local T = ns.T
ok(T and T.VERSION == "1.0.3" and T.NAME == "Needful Slots", "version 1.0.3, title Needful Slots")
ok(rawget(_G, "NeedfulSlots") == nil and rawget(_G, "BeanCounterForever") == nil, "no public add-on table global (private namespace only)")
ok(SLASH_NEEDFULSLOTS1 == "/needful" and SLASH_NEEDFULSLOTS2 == "/nslots" and SlashCmdList.NEEDFULSLOTS, "slash commands /needful and /nslots")
ok(SlashCmdList.BEANCOUNTER == nil and rawget(_G, "SLASH_BEANCOUNTER1") == nil, "old /beans and /tally are gone")

local ev = T._ev
ok(ev and ev.events.ADDON_LOADED and ev.events.PLAYER_LOGIN and ev.events.BAG_UPDATE and ev.events.PLAYER_REGEN_ENABLED, "events registered (incl. PLAYER_REGEN_ENABLED)")
local function fire(e, ...) ev.scripts.OnEvent(ev, e, ...) end
fire("ADDON_LOADED", "NeedfulSlots"); fire("PLAYER_LOGIN")
ok(type(NeedfulSlotsCharDB) == "table" and type(NeedfulSlotsCharDB.items) == "table" and NeedfulSlotsCharDB.locked == false, "per-character defaults")
ok(NeedfulSlotsFrame and not NeedfulSlotsFrame.shown, "named bar frame exists and is hidden when empty at login")
ok(NeedfulSlotsGoalBox and not NeedfulSlotsGoalBox.shown, "named goal box starts hidden")
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
ok(NeedfulSlotsCharDB.items[1].id == 2770 and NeedfulSlotsCharDB.items[4].id == 2589, "saved in order on the character")

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
SlashCmdList.NEEDFULSLOTS("add |cffffffff|Hitem:2770|h[Copper Ore]|h|r")
ok(T.Find(2770), "slash add from an item link")
SlashCmdList.NEEDFULSLOTS("goal 40")
ok(T.Find(2770).goal == 40, "slash goal N applies to the last item")
SlashCmdList.NEEDFULSLOTS("add |cffffffff|Hitem:2771|h[Tin Ore]|h|r")
SlashCmdList.NEEDFULSLOTS("goal |cffffffff|Hitem:2771|h[Tin Ore]|h|r 8")
ok(T.Find(2771).goal == 8, "slash goal [item] N")
counts[2771] = 12
ok(T.GoalMet(T.Count(2771), T.Find(2771).goal), "tin is over its goal")
SlashCmdList.NEEDFULSLOTS("remove |cffffffff|Hitem:2771|h[Tin Ore]|h|r")
ok(not T.Find(2771), "slash remove from a link")
SlashCmdList.NEEDFULSLOTS("lock")
ok(NeedfulSlotsCharDB.locked == true, "slash lock")
SlashCmdList.NEEDFULSLOTS("unlock")
ok(NeedfulSlotsCharDB.locked == false, "slash unlock")
NeedfulSlotsFrame.point = {"CENTER", UIParent, "CENTER", 12, 34}
-- GetPoint is used on drag stop; set pos via Reset then manual
NeedfulSlotsCharDB.pos = {"CENTER", "CENTER", 12, 34}
SlashCmdList.NEEDFULSLOTS("reset")
ok(NeedfulSlotsCharDB.pos == nil, "slash reset clears saved position")
clearChat()
SlashCmdList.NEEDFULSLOTS("help")
ok(chatHas("/needful add") and chatHas("start or stop tracking") and chatHas("/nslots works") and chatHas("left-click uses") and not chatHas("Ctrl-click"), "slash help")
SlashCmdList.NEEDFULSLOTS("clear")
ok(#T.Items() == 0, "slash clear")

-- Alt+right-click on a bag button toggles the item; other modifiers do not.
local btn = { id = 1, GetID = function(self) return 1 end, GetBag = function() return 0 end }
shift, alt, ctrl, chatShown = false, true, false, false
clearChat()
T.OnBagClick(btn, "RightButton")
ok(T.Find(2770), "alt-right-click on a bag item tracks it")
ok(chatHas("Tracking"), "chat says Tracking")
ok(NeedfulSlotsFrame.shown, "bar is shown once an item is tracked")
now = now + 1
clearChat()
T.OnBagClick(btn, "RightButton")
ok(not T.Find(2770), "alt-right-click the same item again untracks it")
ok(chatHas("Removed"), "chat says Removed")
ok(not NeedfulSlotsFrame.shown, "bar hides when the last item is toggled off")
-- re-add for the remaining click tests
now = now + 1
T.OnBagClick(btn, "RightButton")
ok(T.Find(2770), "alt-right-click tracks again after a toggle off")
T.Clear()
ok(not NeedfulSlotsFrame.shown, "bar hides when the list is cleared")
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
ok(not NeedfulSlotsFrame.shown, "locked empty bar is hidden")
T.SetLocked(false); T.Refresh()
ok(not NeedfulSlotsFrame.shown, "unlocked empty bar is hidden")
T.Add(2770); T.Refresh()
ok(NeedfulSlotsFrame.shown, "bar returns when an item is added")
T.Clear()

-- InitDB sanitizes bad saved data
local clean = T.InitDB({ items = { {id=2770, goal=5}, {id=2770, goal=9}, {id=0}, "x", {id=2771} }, locked = "yes" })
ok(#clean.items == 2 and clean.items[1].id == 2770 and clean.items[1].goal == 5 and clean.locked == false, "InitDB sanitizes items and lock")

-- Reload uses the saved character table
NeedfulSlotsCharDB = { items = { {id=2589, goal=100} }, locked = true }
T.InitDB(NeedfulSlotsCharDB)
ok(T.Find(2589) and T.Find(2589).goal == 100 and T.db.locked, "reloads per-character saved items")

-- Optional migrate from a leftover TallyCharDB
TallyCharDB = { items = { {id=2770, goal=15} }, locked = true, pos = {"TOP", "TOP", 0, -20} }
local migrated = T.InitDB({})
ok(migrated.items[1].id == 2770 and migrated.items[1].goal == 15 and migrated.locked == true
   and migrated.pos[1] == "TOP", "migrates a leftover TallyCharDB when Needful Slots data is empty")
local kept = T.InitDB({ items = { {id=2771} } })
ok(kept.items[1].id == 2771 and #kept.items == 1, "does not overwrite existing Needful Slots data with Tally")
TallyCharDB = nil


---------------------------------------------------------------------------
-- 1.0.3: icons are secure use buttons
---------------------------------------------------------------------------
USE_ID = 1113
NeedfulSlotsCharDB = T.InitDB({})
T.Refresh()
local slots = T._slots
ok(slots and #slots == 4, "four slot buttons built")
local s1 = slots[1]
ok(s1.template == "SecureActionButtonTemplate" and s1.ftype == "Button", "slots use SecureActionButtonTemplate")
ok(s1.attrs.useOnKeyDown == false, "secure action fires on release only (useOnKeyDown false)")
ok(s1.attrs["alt-type1"] == ATTRIBUTE_NOOP, "alt-left-click has an explicit no-op secure action")
ok(s1.attrs.type2 == nil and s1.attrs["*type1"] == nil and s1.attrs["*type2"] == nil, "no right-click or any-modifier secure action")
ok(s1.clicks and #s1.clicks == 1 and s1.clicks[1] == "AnyUp", "clicks registered on button up only (AnyUp, so the key binding button is delivered)")
ok(s1.scripts.OnClick == nil and s1.scripts.PostClick, "secure OnClick left alone; add-on clicks run in PostClick")
ok(s1.attrs.type1 == nil and s1.attrs.item == nil, "empty slot has no use action")

clearChat()
T.Add(1113); T.Add(2770)
ok(s1.attrs.type1 == "item" and s1.attrs.item == "item:1113", "tracked food: left-click uses item:1113")
ok(slots[2].attrs.type1 == "item" and slots[2].attrs.item == "item:2770", "ore also gets the item action (client does nothing if no use)")
ok(s1.itemID == 1113 and s1.count.text == "10", "count shows on the use button")

-- Tooltip: "Left-click: use" only for usable items
local function tipHas(slot, text)
  slot.scripts.OnEnter(slot)
  for _, l in ipairs(GameTooltip.lines) do if l:find(text, 1, true) then return true end end
  return false
end
ok(tipHas(s1, "Left-click: use"), "tooltip shows Left-click: use for food")
ok(not tipHas(slots[2], "Left-click: use"), "tooltip omits Left-click: use for ore")
ok(tipHas(slots[2], "Alt-click: stop tracking") and tipHas(slots[2], "Right-click: set goal"), "tooltip keeps the other hints")

-- PostClick: right-click opens the goal box, plain left-click does not touch add-on state
alt, shift, ctrl = false, false, false
s1.scripts.PostClick(s1, "RightButton")
ok(NeedfulSlotsGoalBox.shown and NeedfulSlotsGoalBox.itemID == 1113, "right-click opens the goal box")
NeedfulSlotsGoalBox:SetText("20")
NeedfulSlotsGoalBox.scripts.OnEnterPressed(NeedfulSlotsGoalBox)
ok(T.Find(1113).goal == 20 and s1.count.text == "10/20", "goal set from the box")
s1.scripts.PostClick(s1, "LeftButton")
ok(T.Find(1113) and not NeedfulSlotsGoalBox.shown, "plain left-click keeps the item tracked (secure template uses it)")

-- Alt-click untracks; alt-left never resolves to the item action
alt = true
s1.scripts.PostClick(s1, "LeftButton")
ok(not T.Find(1113), "alt-left-click untracks")
ok(slots[1].itemID == 2770 and slots[1].attrs.item == "item:2770" and slots[2].attrs.item == nil, "slots shift and attributes follow")
T.Add(1113)
slots[2].scripts.PostClick(slots[2], "RightButton")
ok(not T.Find(1113), "alt-right-click on the icon also untracks")
alt = false

-- Drag swallows the click and pauses the secure use for that frame
T.Add(1113)
T.SetLocked(false)
local s2 = slots[2]
s2.scripts.OnDragStart(s2)
ok(s2.attrs.type1 == ATTRIBUTE_NOOP and NeedfulSlotsFrame.moving, "drag pauses the use action and moves the bar")
s2.scripts.OnDragStop(s2)
s2.scripts.PostClick(s2, "LeftButton")
ok(T.Find(1113), "release after a drag does not count as a click")
runTimers()
ok(s2.attrs.type1 == "item", "use action restored after the drag")
T.SetLocked(true)
NeedfulSlotsFrame.moving = false
s2.scripts.OnDragStart(s2)
ok(not NeedfulSlotsFrame.moving and s2.attrs.type1 == "item", "locked bar does not drag")
T.SetLocked(false)

---------------------------------------------------------------------------
-- 1.0.3: combat lockdown queue
---------------------------------------------------------------------------
inCombat = true; NeedfulSlotsFrame:Show(); slots[1]:SetAttribute("x", 1); inCombat = false
ok(#protectedCalls == 2, "harness self-check: protected calls in combat are detected")
slots[1].attrs.x = nil
protectedCalls = {}
local function noProtected() return #protectedCalls == 0 end
inCombat = true
local frameShown = NeedfulSlotsFrame.shown
counts[1113] = 4
T.Refresh()
T.SetGoal(1113, 20); ok(s2.count.text == "4/20", "counts and goal text update in combat")
T.Add(2771)
ok(T.Find(2771) and rawget(slots[3], "itemID") == nil and slots[3].attrs.item == nil, "add in combat is saved but the icon waits")
ok(chatHas("when combat ends"), "chat says the bar updates when combat ends")
clearChat()
T.Remove(2770)
ok(not chatHas("when combat ends"), "combat note only once per fight")
ok(slots[1].itemID == 2770 and slots[1].attrs.item == "item:2770", "untrack in combat leaves the secure button alone")
s2.scripts.OnDragStart(s2)
ok(s2.attrs.type1 == "item", "no drag in combat")
T.SetLocked(true); T.ResetPosition()
ok(T.LayoutPending(), "layout is queued")
ok(noProtected(), "no protected calls (attributes, show/hide, anchors, size, drag) in combat")
ok(NeedfulSlotsFrame.shown == frameShown, "bar visibility unchanged in combat")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
ok(not T.LayoutPending(), "queue applied on PLAYER_REGEN_ENABLED")
ok(slots[1].itemID == 1113 and slots[1].attrs.item == "item:1113" and slots[2].attrs.item == "item:2771" and slots[3].attrs.item == nil,
   "after combat: icons and use actions match the list")
-- Clear in combat keeps the bar until combat ends
inCombat = true
T.Clear()
ok(NeedfulSlotsFrame.shown, "bar stays up during combat after a clear")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
ok(not NeedfulSlotsFrame.shown and slots[1].attrs.type1 == nil, "bar hides after combat once empty")
clearChat()
inCombat = true; T.Add(2770); inCombat = false
ok(chatHas("when combat ends"), "combat note resets for the next fight")
fire("PLAYER_REGEN_ENABLED")
T.Clear(); T.SetLocked(false)

-- A BAG_UPDATE in combat only updates counts
T.Add(1113); inCombat = true; protectedCalls = {}
counts[1113] = 9; fire("BAG_UPDATE", 0); runTimers()
ok(slots[1].count.text == "9" and noProtected(), "BAG_UPDATE in combat updates the count only")
inCombat = false; fire("PLAYER_REGEN_ENABLED"); T.Clear()

---------------------------------------------------------------------------
-- 1.0.3: migration from Bean Counter
---------------------------------------------------------------------------
BeanCounterCharDB = { items = { {id=2770, goal=40}, {id=2771} }, locked = true, pos = {"BOTTOM", "BOTTOM", 10, 200} }
local mig = T.InitDB({})
ok(mig.items[1].id == 2770 and mig.items[1].goal == 40 and mig.items[2].id == 2771 and mig.locked == true and mig.pos[4] == 200,
   "copies items, goals, lock and position from BeanCounterCharDB")
ok(BeanCounterCharDB == nil, "old BeanCounterCharDB is cleared after migrating")
BeanCounterCharDB = { items = { {id=2589} } }
local keep = T.InitDB({ items = { {id=2840} } })
ok(keep.items[1].id == 2840 and #keep.items == 1 and BeanCounterCharDB ~= nil, "existing Needful Slots data is never overwritten")
BeanCounterCharDB = nil
fire("ADDON_LOADED", "NeedfulSlots")
ok(type(NeedfulSlotsCharDB) == "table", "ADDON_LOADED sets NeedfulSlotsCharDB")

-- The TOC lists only the new SavedVariables
local toc = io.open("../NeedfulSlots/NeedfulSlots.toc"):read("*a")
ok(toc:find("## Version: 1.0.3", 1, true) and toc:find("## Title: Needful Slots", 1, true)
   and toc:find("## SavedVariablesPerCharacter: NeedfulSlotsCharDB\n", 1, true) and not toc:find("BeanCounter", 1, true), "TOC: name, version, SavedVariables")


---------------------------------------------------------------------------
-- 1.0.3: Key Bindings (Use Needful Slot 1-4)
---------------------------------------------------------------------------
-- Mock of the client's secure attribute lookup (frame:GetAttribute(prefix,
-- name, suffix) + SecureButton_GetModifiedAttribute in SecureTemplates.lua).
local function suffixOf(button)
  if button == "LeftButton" then return "1" elseif button == "RightButton" then return "2"
  elseif button == "MiddleButton" then return "3" elseif button and button:match("^Button(%d+)$") then return button:match("^Button(%d+)$")
  elseif button and button ~= "" then return "-" .. button end
  return ""
end
local function prefixOf(a, c, s) return (a and "alt-" or "") .. (c and "ctrl-" or "") .. (s and "shift-" or "") end
local function resolve(f, name, button, a, c, s)
  local p, x, A = prefixOf(a, c, s), suffixOf(button), f.attrs
  for _, k in ipairs({ p .. name .. x, "*" .. name .. x, p .. name .. "*", "*" .. name .. "*", p .. name, "*" .. name }) do
    local v = A[k]
    if v ~= nil then if v == ATTRIBUTE_NOOP then return nil end return v end
  end
end
-- What a click would use: the item string, or nil (nothing happens).
local function wouldUse(f, button, a, c, s)
  if resolve(f, "type", button, a, c, s) ~= "item" then return nil end
  return resolve(f, "item", button, a, c, s)
end

-- Bindings.xml
local bx = io.open("../NeedfulSlots/Bindings.xml"):read("*a")
local binds = {}
for attrs in bx:gmatch("<Binding%s+([^>]-)/?>") do
  local b = {}
  for k, v in attrs:gmatch('(%w+)="([^"]*)"') do b[k] = v end
  binds[#binds+1] = b
end
ok(bx:match("^%s*<Bindings>") and bx:match("</Bindings>%s*$"), "Bindings.xml: one <Bindings> root")
ok(#binds == 4, "Bindings.xml: four bindings")
for i = 1, 4 do
  local b = binds[i] or {}
  ok(b.name == "CLICK NeedfulSlotsButton" .. i .. ":NeedfulSlotsKey" and b.name == T.BindingCommand(i), "binding " .. i .. " is the secure CLICK form for button " .. i)
  ok(b.category == "ADDONS", "binding " .. i .. " is in the AddOns category")
  ok((i == 1 and b.header == "NEEDFULSLOTS") or (i > 1 and b.header == nil), "binding " .. i .. " header only on the first")
  ok(_G["BINDING_NAME_" .. b.name] == "Use Needful Slot " .. i, "binding " .. i .. " label: Use Needful Slot " .. i)
end
ok(BINDING_HEADER_NEEDFULSLOTS == "Needful Slots", "Key Bindings header: Needful Slots")
ok(not bx:find("<Binding[^>]*>[^<]*%S[^<]*</Binding>"), "CLICK bindings have no Lua body (no insecure code runs)")
local tocText = io.open("../NeedfulSlots/NeedfulSlots.toc"):read("*a")
ok(not tocText:find("Bindings.xml", 1, true), "Bindings.xml is auto-loaded by the client, not listed in the TOC")

-- Named buttons for the CLICK bindings
for i = 1, 4 do
  ok(_G["NeedfulSlotsButton" .. i] == slots[i] and slots[i].name == "NeedfulSlotsButton" .. i and slots[i].index == i, "slot " .. i .. " is the global button NeedfulSlotsButton" .. i)
end

-- Key attributes follow the slot's item; empty slots do nothing
NeedfulSlotsCharDB = T.InitDB({}); T.Refresh()
for i = 1, 4 do ok(wouldUse(slots[i], "NeedfulSlotsKey") == nil, "empty slot " .. i .. ": key does nothing") end
T.Add(1113); T.Add(2770)
ok(slots[1].attrs["*type-NeedfulSlotsKey"] == "item" and slots[1].attrs["*item-NeedfulSlotsKey"] == "item:1113", "slot 1 key attributes set")
ok(wouldUse(slots[1], "NeedfulSlotsKey") == "item:1113", "key 1 uses the slot 1 item")
ok(wouldUse(slots[2], "NeedfulSlotsKey") == "item:2770", "key 2 uses the slot 2 item")
ok(wouldUse(slots[3], "NeedfulSlotsKey") == nil and wouldUse(slots[4], "NeedfulSlotsKey") == nil, "keys 3-4 do nothing while those slots are empty")
ok(wouldUse(slots[1], "NeedfulSlotsKey", true) == "item:1113" and wouldUse(slots[1], "NeedfulSlotsKey", false, true, false) == "item:1113"
   and wouldUse(slots[1], "NeedfulSlotsKey", false, false, true) == "item:1113" and wouldUse(slots[1], "NeedfulSlotsKey", true, true, true) == "item:1113",
   "key bound with Alt/Ctrl/Shift still uses the item")
-- Mouse behaviour is unchanged by the key attributes
ok(wouldUse(slots[1], "LeftButton") == "item:1113", "plain left-click still uses")
ok(wouldUse(slots[1], "LeftButton", true) == nil, "alt-left-click still never uses")
ok(wouldUse(slots[1], "LeftButton", false, false, true) == nil and wouldUse(slots[1], "LeftButton", false, true, false) == nil, "shift/ctrl-left-click do not use")
ok(wouldUse(slots[1], "RightButton") == nil and wouldUse(slots[1], "MiddleButton") == nil and wouldUse(slots[1], "Button4") == nil, "right/middle/side buttons do not use")

-- PostClick for a key press: never removes or opens the goal box, even with Alt
clearChat(); alt = true
slots[1].scripts.PostClick(slots[1], "NeedfulSlotsKey")
alt = false
ok(T.Find(1113) and not chatHas("Removed"), "key bound with Alt does not stop tracking")
ok(not NeedfulSlotsGoalBox.shown, "key press does not open the goal box")
slots[3].scripts.PostClick(slots[3], "NeedfulSlotsKey")
ok(#T.Items() == 2, "key on an empty slot changes nothing")
alt = true; slots[1].scripts.PostClick(slots[1], "MiddleButton"); alt = false
ok(T.Find(1113), "alt-middle-click does nothing (only left/right clicks reach PostClick logic)")
alt = true; slots[1].scripts.PostClick(slots[1], "LeftButton"); alt = false
ok(not T.Find(1113), "alt-left-click still stops tracking")
T.Add(1113) -- back to [2770, 1113]
ok(wouldUse(slots[1], "NeedfulSlotsKey") == "item:2770" and wouldUse(slots[2], "NeedfulSlotsKey") == "item:1113", "after a remove/add the keys follow the new order")

-- Drag pause does not break the key
T.SetLocked(false)
slots[1].scripts.OnDragStart(slots[1])
ok(wouldUse(slots[1], "LeftButton") == nil and wouldUse(slots[1], "NeedfulSlotsKey") == "item:2770", "during a drag the click is paused but the key still works")
slots[1].scripts.OnDragStop(slots[1]); runTimers()
ok(wouldUse(slots[1], "LeftButton") == "item:2770", "click restored after drag")

-- Combat: keys keep the item the icon shows; reassignments apply after combat
inCombat = true; protectedCalls = {}
T.Remove(2770); T.Add(2771)
ok(#protectedCalls == 0, "no secure attribute changes in combat")
ok(wouldUse(slots[1], "NeedfulSlotsKey") == "item:2770" and wouldUse(slots[2], "NeedfulSlotsKey") == "item:1113", "in combat each key matches the icon still shown")
inCombat = false; fire("PLAYER_REGEN_ENABLED")
ok(wouldUse(slots[1], "NeedfulSlotsKey") == "item:1113" and wouldUse(slots[2], "NeedfulSlotsKey") == "item:2771" and wouldUse(slots[3], "NeedfulSlotsKey") == nil,
   "after combat key 1/2 map to the new slot 1/2 items, key 3 does nothing")
inCombat = true; T.Clear(); inCombat = false
ok(wouldUse(slots[1], "NeedfulSlotsKey") == "item:1113", "clear in combat: key keeps working until combat ends")
fire("PLAYER_REGEN_ENABLED")
ok(wouldUse(slots[1], "NeedfulSlotsKey") == nil and wouldUse(slots[2], "NeedfulSlotsKey") == nil, "after combat a cleared bar's keys do nothing")

clearChat(); T.Slash("help")
ok(chatHas("Keybindings > AddOns > Needful Slots") and chatHas("Use Needful Slot 1-4"), "help mentions the keybinds")
-- Tooltip mentions the bound key
local bound = {}
function GetBindingKey(cmd) return bound[cmd] end
function GetBindingText(k) return (k:gsub("ALT%-", "Alt-")) end
T.Add(1113)
ok(tipHas(slots[1], "Left-click: use"), "tooltip without a key: Left-click: use")
bound["CLICK NeedfulSlotsButton1:NeedfulSlotsKey"] = "ALT-1"
ok(tipHas(slots[1], "Left-click or Alt-1: use"), "tooltip shows the bound key")
GetBindingKey, GetBindingText = nil, nil
ok(tipHas(slots[1], "Left-click: use"), "tooltip works without GetBindingKey")
T.Clear()

-- Global-name audit: load a fresh copy in a sandbox and list every global it sets
do
  local created = {}
  local env = setmetatable({}, { __index = _G, __newindex = function(t, k, v) created[#created+1] = k rawset(t, k, v) end })
  rawset(env, "_G", env) -- _G["..."] writes are caught too
  local saveCF = CreateFrame
  local named = {}
  CreateFrame = function(ftype, name, ...) if name then named[#named+1] = name end return saveCF(ftype, nil, ...) end
  local f = assert(loadfile("../NeedfulSlots/NeedfulSlots.lua"))
  setfenv(f, env)
  local ns2 = {}
  f("NeedfulSlots", ns2)
  local evf = ns2.T._ev
  NeedfulSlotsCharDB = nil
  evf.scripts.OnEvent(evf, "ADDON_LOADED", "NeedfulSlots"); evf.scripts.OnEvent(evf, "PLAYER_LOGIN")
  ns2.T.Add(1113); alt = true; ns2.T._slots[1].scripts.PostClick(ns2.T._slots[1], "NeedfulSlotsKey"); alt = false
  CreateFrame = saveCF
  local allowed = { NeedfulSlotsCharDB = true, SLASH_NEEDFULSLOTS1 = true, SLASH_NEEDFULSLOTS2 = true, BINDING_HEADER_NEEDFULSLOTS = true }
  for i = 1, 4 do allowed["BINDING_NAME_CLICK NeedfulSlotsButton" .. i .. ":NeedfulSlotsKey"] = true end
  local bad = {}
  for _, k in ipairs(created) do if not allowed[k] then bad[#bad+1] = tostring(k) end end
  ok(#bad == 0, "audit: no unexpected Lua globals (" .. table.concat(bad, ",") .. ")")
  ok(#created == 8, "audit: exactly the 8 expected globals are set")
  local okNames = { NeedfulSlotsFrame = true, NeedfulSlotsGoalBox = true, NeedfulSlotsButton1 = true, NeedfulSlotsButton2 = true, NeedfulSlotsButton3 = true, NeedfulSlotsButton4 = true }
  local badN = {}
  for _, n in ipairs(named) do if not okNames[n] then badN[#badN+1] = n end end
  ok(#badN == 0 and #named == 6, "audit: named frames are only the bar, goal box and four buttons (" .. table.concat(named, ",") .. ")")
  print("audit globals: " .. table.concat(created, ", "))
  print("audit named frames: " .. table.concat(named, ", "))
end

if fails > 0 then print("passes="..passes.." fails="..fails) else print("passes="..passes.." fails=0") end
return fails
