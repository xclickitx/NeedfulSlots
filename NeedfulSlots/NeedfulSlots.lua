-- Needful Slots 1.0.3 by ClickIT, for WoW Forever (Interface 16001).
-- Formerly "Bean Counter" (folder BeanCounterForever, SavedVariables
-- BeanCounterCharDB, /beans and /tally). Renamed in 1.0.3.
--
-- A small, quiet bar that tracks up to four items from your bags. Each icon
-- shows a live bag count (white, green once an optional goal is met, still
-- counting past it) and is also a use button: plain left-click uses the item
-- (eat, drink, open, place) through a SecureActionButtonTemplate.
--
-- Bag side: Alt-right-click a bag item to start or stop tracking it (one
-- gesture). Alt-left-click is left alone (Bagnon Flash Find; Auctionator's
-- default sell shortcut). Shift-clicks stay with the default UI.
--
-- Bar side: left-click uses, right-click sets a goal, Alt-click stops
-- tracking, left-drag moves the bar when unlocked. No sounds or flashes. The
-- bar hides when nothing is tracked.
--
-- Combat lockdown: the icons are protected frames, so their attributes,
-- Show/Hide, size and anchors (and the bar's, which becomes protected as their
-- parent) cannot change in combat. Any add/remove/lock/reset that happens in
-- combat is saved at once but the bar layout is queued and applied on
-- PLAYER_REGEN_ENABLED. Counts and colours still update during combat.
--
-- Client API (all present in the Forever 1.60.1 FrameXML / API docs):
-- C_Item.GetItemCount / GetItemInfo / GetItemIconByID / GetItemSpell /
-- IsUsableItem (with old global fallbacks), InCombatLockdown,
-- SecureActionButtonTemplate (type1 "item", useOnKeyDown false,
-- ATTRIBUTE_NOOP), hooksecurefunc on the container item button click
-- handlers. Bag counts refresh on BAG_UPDATE, bucketed with C_Timer.After.
--
-- Key Bindings (Bindings.xml, loaded by the client from the add-on folder):
-- "Use Needful Slot 1-4" under the Needful Slots header (AddOns category).
-- Each is a secure CLICK binding, "CLICK NeedfulSlotsButtonN:NeedfulSlotsKey",
-- so it works in combat without taint. The virtual button "NeedfulSlotsKey"
-- has its own attributes ("*type-NeedfulSlotsKey" / "*item-NeedfulSlotsKey"),
-- so a key bound with a modifier (Alt-1, Shift-F) still uses the item and
-- never triggers the bar's Alt-click "stop tracking".
--
-- Globals: only NeedfulSlotsCharDB (SavedVariables), SLASH_NEEDFULSLOTS1/2,
-- the named frames NeedfulSlotsFrame / NeedfulSlotsGoalBox /
-- NeedfulSlotsButton1-4 (the CLICK bindings need button names), and the Key
-- Bindings labels BINDING_HEADER_NEEDFULSLOTS and
-- BINDING_NAME_CLICK NeedfulSlotsButton1-4:NeedfulSlotsKey. The add-on table
-- lives in the private add-on namespace (the second vararg).

local addonName, ns = ...
addonName = addonName or "NeedfulSlots"
ns = ns or {}

local T = {}
ns.T = T
T.VERSION = "1.0.3"
T.NAME = "Needful Slots"
T.MAX = 4
-- Virtual mouse button the Key Bindings click with (see Bindings.xml).
T.KEY_BUTTON = "NeedfulSlotsKey"
T.BUTTON_PREFIX = "NeedfulSlotsButton"

-- Key Bindings menu labels (the client reads these globals by name).
BINDING_HEADER_NEEDFULSLOTS = "Needful Slots"
for i = 1, T.MAX do
	_G["BINDING_NAME_CLICK " .. T.BUTTON_PREFIX .. i .. ":" .. T.KEY_BUTTON] = "Use Needful Slot " .. i
end

-- The binding command for slot i, e.g. "CLICK NeedfulSlotsButton1:NeedfulSlotsKey".
function T.BindingCommand(i)
	return "CLICK " .. T.BUTTON_PREFIX .. i .. ":" .. T.KEY_BUTTON
end

local floor, format, tonumber, tostring, type, select = math.floor, string.format, tonumber, tostring, type, select
local pairs, ipairs, pcall, tremove = pairs, ipairs, pcall, table.remove
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local DEFAULTS = {
	items = {}, -- { {id=itemID, goal=nil or number}, ... } max 4, keep order
	pos = nil,  -- { point, relPoint, x, y }
	locked = false,
}

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

local PREFIX = "|cffffd100Needful Slots|r: "
local function out(msg, ...)
	if select("#", ...) > 0 then msg = format(msg, ...) end
	local frame = DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then frame:AddMessage(PREFIX .. msg) elseif print then print(PREFIX .. msg) end
end
T.Print = out

local function after(sec, fn)
	if C_Timer and C_Timer.After then return C_Timer.After(sec, fn) end
	-- Fallback only when C_Timer is missing. One-shot, then the script is cleared.
	if not CreateFrame then return end
	local f, t = CreateFrame("Frame"), 0
	f:SetScript("OnUpdate", function(self, e)
		t = t + e
		if t >= sec then self:SetScript("OnUpdate", nil) fn() end
	end)
end

---------------------------------------------------------------------------
-- Item helpers
---------------------------------------------------------------------------

local function itemInfo(id)
	if not id then return end
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not get then return end
	local ok, name, link, quality, _, _, _, _, _, _, texture = pcall(get, id)
	if not ok then return end
	return name, link, quality, texture
end

local function itemIcon(id)
	local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
	if get then
		local ok, tex = pcall(get, id)
		if ok and tex then return tex end
	end
	local _, _, _, texture = itemInfo(id)
	return texture
end

local function itemLink(id)
	local name, link = itemInfo(id)
	if link then return link end
	if name then return format("|cffffffff|Hitem:%d|h[%s]|h|r", id, name) end
	return format("item %d", id)
end

local function parseItem(text)
	if type(text) ~= "string" then return nil, nil end
	local id = tonumber(text:match("item:(%d+)") or text:match("Hitem:(%d+)") or text:match("^%s*(%d+)%s*$"))
	if not id then return nil, text:match("^%s*(.-)%s*$") end
	return id
end

-- Bags only (includeBank = false). Charges and account/reagent banks stay out.
function T.Count(id)
	if not id then return 0 end
	local get = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not get then return 0 end
	local ok, n = pcall(get, id, false)
	if not ok then return 0 end
	return tonumber(n) or 0
end

function T.GoalMet(count, goal)
	goal = tonumber(goal)
	if not goal or goal <= 0 then return false end
	return (tonumber(count) or 0) >= goal
end

-- Count colour: white until the goal, then green, still counting past it.
function T.CountColor(count, goal)
	if T.GoalMet(count, goal) then return 0.2, 1.0, 0.2 end
	return 1, 1, 1
end

function T.CountText(count, goal)
	count = tonumber(count) or 0
	goal = tonumber(goal)
	if goal and goal > 0 then return format("%d/%d", count, goal) end
	return tostring(count)
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local db
local function copyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			if k ~= "items" and k ~= "pos" then copyDefaults(dst[k], v) end
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function sanitizeItems(list)
	local outList, seen = {}, {}
	if type(list) ~= "table" then return outList end
	for _, it in ipairs(list) do
		local id, goal
		if type(it) == "table" then
			id, goal = tonumber(it.id), tonumber(it.goal)
		else
			id = tonumber(it)
		end
		if id and id > 0 and not seen[id] and #outList < T.MAX then
			if not goal or goal <= 0 then goal = nil end
			outList[#outList + 1] = { id = id, goal = goal }
			seen[id] = true
		end
	end
	return outList
end

local function copyOld(saved, old)
	saved.items = {}
	for i, it in ipairs(old.items) do
		if type(it) == "table" then
			saved.items[i] = { id = it.id, goal = it.goal }
		end
	end
	if saved.pos == nil and type(old.pos) == "table" then
		saved.pos = { old.pos[1], old.pos[2], old.pos[3], old.pos[4] }
	end
	if saved.locked == nil then saved.locked = old.locked end
end

local function hasItems(t)
	return type(t) == "table" and type(t.items) == "table" and #t.items > 0
end

-- Settings migration. If this character has no Needful Slots data yet, copy
-- an old save that is loaded in this session:
--   1. BeanCounterCharDB (Bean Counter 1.0.0-1.0.2), then nil it so it is
--      not copied again and does not linger in memory.
--   2. TallyCharDB (the pre-release "Tally" build), left untouched.
-- Note: WoW stores SavedVariables per add-on folder, so the old
-- BeanCounterForever.lua file is only loaded while the old BeanCounterForever
-- folder is still installed. Listing BeanCounterCharDB in this TOC would not
-- read that file (it would read/write NeedfulSlots.lua), so it is NOT listed.
-- The installer instead copies WTF/.../SavedVariables/BeanCounterForever.lua
-- to NeedfulSlots.lua with the table renamed; this code covers the case where
-- both folders happen to be loaded together.
function T.InitDB(saved)
	saved = type(saved) == "table" and saved or {}
	if not hasItems(saved) then
		if hasItems(BeanCounterCharDB) then
			copyOld(saved, BeanCounterCharDB)
			BeanCounterCharDB = nil
			T.migrated = "BeanCounter"
		elseif hasItems(TallyCharDB) then
			copyOld(saved, TallyCharDB)
			T.migrated = "Tally"
		end
	end
	copyDefaults(saved, DEFAULTS)
	saved.items = sanitizeItems(saved.items)
	if saved.locked ~= true then saved.locked = false end
	if type(saved.pos) ~= "table" then saved.pos = nil end
	db = saved
	T.db = db
	return db
end

---------------------------------------------------------------------------
-- Tracked list (no UI)
---------------------------------------------------------------------------

local combatNoted -- "after combat" chat note already shown this fight

-- WoW's own "do nothing" attribute value (SecureTemplates.lua).
local NOOP = ATTRIBUTE_NOOP or ""

local function inCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end
T.InCombat = inCombat

-- One short chat note per fight when a change has to wait for combat to end.
local function noteQueued()
	if combatNoted then return end
	combatNoted = true
	out("The bar will update when combat ends.")
end

local lastTouched -- itemID last added or clicked on the bar, for /needful goal N

function T.Items()
	return db and db.items or {}
end

function T.Find(id)
	id = tonumber(id)
	if not id or not db then return end
	for i, it in ipairs(db.items) do
		if it.id == id then return it, i end
	end
end

function T.Add(id, link)
	id = tonumber(id)
	if not id or not db then return false, "noid" end
	local found = T.Find(id)
	if found then
		lastTouched = id
		out("Already tracking %s.", link or itemLink(id))
		return false, "dup"
	end
	if #db.items >= T.MAX then
		out("You can only track %d items. Remove one first.", T.MAX)
		return false, "full"
	end
	db.items[#db.items + 1] = { id = id, goal = nil }
	lastTouched = id
	out("Tracking %s.", link or itemLink(id))
	if inCombat() then noteQueued() end
	T.Refresh()
	return true
end

function T.Remove(id)
	id = tonumber(id)
	if not id or not db then return false end
	local _, i = T.Find(id)
	if not i then return false, "missing" end
	local link = itemLink(id)
	tremove(db.items, i)
	if lastTouched == id then lastTouched = db.items[1] and db.items[1].id end
	out("Removed %s.", link)
	if inCombat() then noteQueued() end
	T.Refresh()
	return true
end

function T.Toggle(id, link)
	if T.Find(id) then
		return T.Remove(id)
	end
	return T.Add(id, link)
end

function T.Clear()
	if not db then return end
	wipe(db.items)
	lastTouched = nil
	out("Cleared all tracked items.")
	if inCombat() then noteQueued() end
	T.Refresh()
end

function T.SetGoal(id, goal)
	id = tonumber(id)
	local it = T.Find(id)
	if not it then return false, "missing" end
	goal = tonumber(goal)
	if not goal or goal <= 0 then
		it.goal = nil
		out("No goal for %s.", itemLink(id))
	else
		it.goal = floor(goal)
		out("Goal for %s is %d.", itemLink(id), it.goal)
	end
	lastTouched = id
	T.Refresh()
	return true
end

function T.SetLocked(locked)
	if not db then return end
	db.locked = locked and true or false
	out("Bar %s.", db.locked and "locked" or "unlocked")
	if inCombat() then noteQueued() end
	T.Refresh()
	return db.locked
end

function T.ResetPosition()
	if not db then return end
	db.pos = nil
	out("Bar moved back to the default position.")
	if inCombat() then noteQueued() end
	T.Refresh()
end

---------------------------------------------------------------------------
-- Bag-click hook (Alt+right-click only)
---------------------------------------------------------------------------

local function isInventoryBag(bag)
	bag = tonumber(bag)
	if bag == nil then return nil end
	local maxBag = tonumber(NUM_BAG_SLOTS) or 4
	if NUM_REAGENTBAG_SLOTS then maxBag = maxBag + (tonumber(NUM_REAGENTBAG_SLOTS) or 0) end
	return bag >= 0 and bag <= maxBag
end

-- Read an itemID from a bag button, supporting Blizzard bags and Bagnon.
function T.ItemFromButton(btn)
	if type(btn) ~= "table" then return end
	local bag, slot
	if btn.GetBag then
		local ok, b = pcall(btn.GetBag, btn)
		if ok then bag = b end
	end
	if bag == nil and btn.GetBagID then
		local ok, b = pcall(btn.GetBagID, btn)
		if ok then bag = b end
	end
	if bag == nil and (btn.bag or btn.bagID) then
		bag = btn.bag or btn.bagID
	end
	if btn.GetID then
		local ok, s = pcall(btn.GetID, btn)
		if ok then slot = s end
	end
	if bag == nil and slot and btn.GetParent then
		local ok, parent = pcall(btn.GetParent, btn)
		if ok and parent and parent.GetID then
			local ok2, b = pcall(parent.GetID, parent)
			if ok2 then bag = b end
		end
	end
	if bag ~= nil and slot then
		-- Skip bank / other non-inventory bags; /needful add still works for those.
		if isInventoryBag(bag) == false then return end
		if C_Container and C_Container.GetContainerItemInfo then
			local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
			if ok and type(info) == "table" and info.itemID then
				return tonumber(info.itemID), info.hyperlink
			end
		end
		local getID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
		if getID then
			local ok, id = pcall(getID, bag, slot)
			if ok and id then return tonumber(id) end
		end
	end
	if btn.info and btn.info.itemID then
		return tonumber(btn.info.itemID), btn.info.hyperlink
	end
end

local lastHookID, lastHookTime = nil, 0
function T.OnBagClick(btn, button)
	-- Alt+right-click only. Alt+left is Bagnon Flash Find and Auctionator's
	-- default "select to sell" shortcut at the auction house. Shift is split/link.
	if button ~= "RightButton" then return end
	if not (IsAltKeyDown and IsAltKeyDown()) then return end
	if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
	if not db then return end
	local id, link = T.ItemFromButton(btn)
	if not id then return end
	local now = (GetTime and GetTime()) or 0
	if id == lastHookID and now - lastHookTime < 0.05 then return end
	lastHookID, lastHookTime = id, now
	T.Toggle(id, link)
end

local hooked = {}
local function hookOne(...)
	if not hooksecurefunc then return end
	local a, b, c = ...
	local key, fn
	if type(a) == "table" then
		if type(a[b]) ~= "function" then return end
		key, fn = tostring(a) .. "." .. b, c
		if hooked[key] then return end
		hooked[key] = true
		pcall(hooksecurefunc, a, b, fn)
	else
		if type(_G[a]) ~= "function" then return end
		key, fn = a, b
		if hooked[key] then return end
		hooked[key] = true
		pcall(hooksecurefunc, a, fn)
	end
end

function T.HookBags()
	hookOne("ContainerFrameItemButton_OnModifiedClick", T.OnBagClick)
	hookOne("ContainerFrameItemButton_OnClick", T.OnBagClick)
	if ContainerFrameItemButtonMixin then
		hookOne(ContainerFrameItemButtonMixin, "OnModifiedClick", T.OnBagClick)
		hookOne(ContainerFrameItemButtonMixin, "OnClick", T.OnBagClick)
	end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local frame, slots, goalBox, pendingRefresh
slots = {}
local dragged
local layoutPending -- a layout change is waiting for combat to end

local function savePosition()
	if not (db and frame and frame.GetPoint) then return end
	local point, _, rel, x, y = frame:GetPoint()
	if point then db.pos = { point, rel or point, x or 0, y or 0 } end
end

local function applyPosition()
	if not frame then return end
	frame:ClearAllPoints()
	local p = db and db.pos
	if type(p) == "table" and p[1] then
		frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
	end
end

local function applyLock()
	if not frame then return end
	local locked = db and db.locked
	if frame.EnableMouse then frame:EnableMouse(not locked) end
	if frame.RegisterForDrag then
		if locked then frame:RegisterForDrag() else frame:RegisterForDrag("LeftButton") end
	end
	for i = 1, T.MAX do
		local s = slots[i]
		if s and s.RegisterForDrag then
			if locked then s:RegisterForDrag() else s:RegisterForDrag("LeftButton") end
		end
	end
end

local function hideGoalBox()
	if not goalBox then return end
	goalBox:Hide()
	if goalBox.ClearFocus then goalBox:ClearFocus() end
	goalBox.itemID = nil
end

local function showGoalBox(slot, id)
	if not goalBox then return end
	local it = T.Find(id)
	if not it then return end
	goalBox.itemID = id
	goalBox:SetText(it.goal and tostring(it.goal) or "")
	goalBox:ClearAllPoints()
	goalBox:SetPoint("TOP", slot, "BOTTOM", 0, -2)
	goalBox:Show()
	if goalBox.SetFocus then goalBox:SetFocus() end
end

-- True when the item has a Use: effect or the client calls it usable.
function T.HasUse(id)
	if not id then return false end
	local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
	if getSpell then
		local ok, spell = pcall(getSpell, id)
		if ok and spell then return true end
	end
	local usable = (C_Item and C_Item.IsUsableItem) or IsUsableItem
	if usable then
		local ok, u = pcall(usable, id)
		if ok and u then return true end
	end
	return false
end

local function slotTooltip(slot)
	if not GameTooltip or not slot.itemID then return end
	if GameTooltip.SetOwner then GameTooltip:SetOwner(slot, "ANCHOR_RIGHT") end
	local id, it = slot.itemID, T.Find(slot.itemID)
	local name = itemInfo(id)
	if GameTooltip.SetHyperlink then
		local link = itemLink(id)
		if link and link:find("Hitem:", 1, true) then pcall(GameTooltip.SetHyperlink, GameTooltip, link) end
	elseif GameTooltip.SetText then
		GameTooltip:SetText(name or ("item " .. id))
	end
	local count = T.Count(id)
	if GameTooltip.AddLine then
		GameTooltip:AddLine(format("Bags: %d", count), 1, 1, 1)
		if it and it.goal then
			GameTooltip:AddLine(format("Goal: %d", it.goal), 1, 1, 1)
		else
			GameTooltip:AddLine("Goal: none", 0.7, 0.7, 0.7)
		end
		if T.HasUse(id) then
			local key = slot.index and T.BoundKey(slot.index)
			if key then
				GameTooltip:AddLine(format("Left-click or %s: use", key), 0.8, 0.8, 0.8)
			else
				GameTooltip:AddLine("Left-click: use", 0.8, 0.8, 0.8)
			end
		end
		GameTooltip:AddLine("Alt-click: stop tracking · Right-click: set goal · Drag to move", 0.8, 0.8, 0.8)
	end
	if GameTooltip.Show then GameTooltip:Show() end
end

-- Secure use action for a slot. Only a plain (no modifier) left-click uses
-- the item: "type1" matches only with no modifier held, and "alt-type1" is set
-- to ATTRIBUTE_NOOP as an explicit guard. Right-click has no secure action.
-- The Key Bindings click with the virtual button T.KEY_BUTTON, which has its
-- own "*" (any modifier) attributes, so a bound key uses the item whatever
-- modifier it was bound with. An empty slot has no type: the key does nothing.
local KEY_TYPE = "*type-" .. T.KEY_BUTTON
local KEY_ITEM = "*item-" .. T.KEY_BUTTON
local function setUse(slot, id)
	if not slot.SetAttribute then return end
	local item = id and ("item:" .. id) or nil
	slot:SetAttribute("type1", id and "item" or nil)
	slot:SetAttribute("item", item)
	slot:SetAttribute(KEY_TYPE, id and "item" or nil)
	slot:SetAttribute(KEY_ITEM, item)
end

-- Bound key text for slot i ("Alt-1"), or nil.
function T.BoundKey(i)
	if not GetBindingKey then return end
	local ok, key = pcall(GetBindingKey, T.BindingCommand(i))
	if not ok or not key then return end
	if GetBindingText then
		local ok2, text = pcall(GetBindingText, key)
		if ok2 and text and text ~= "" then return text end
	end
	return key
end

-- After a drag, the release can also count as a click. Swallow that one
-- click in PostClick and pause the secure use for this frame.
local function endDrag(slot)
	after(0, function()
		dragged = false
		if not slot.itemID then return end
		if inCombat() then layoutPending = true return end
		setUse(slot, slot.itemID)
	end)
end

local function makeSlot(parent, i)
	-- Named so the Key Bindings (CLICK NeedfulSlotsButtonN:...) can find it.
	-- Button N always shows the Nth tracked item.
	local b = CreateFrame("Button", T.BUTTON_PREFIX .. i, parent, "SecureActionButtonTemplate")
	b:SetSize(36, 36)
	b.index = i
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	b.icon = tex
	local fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	b.count = fs
	-- Fire on release only, whatever the ActionButtonUseKeyDown CVar says,
	-- so one click or key press is one use and PostClick runs once. "AnyUp"
	-- (not just Left/RightButtonUp) so the Key Bindings' virtual button
	-- T.KEY_BUTTON is delivered too; other mouse buttons have no type and do
	-- nothing.
	if b.SetAttribute then
		b:SetAttribute("useOnKeyDown", false)
		b:SetAttribute("alt-type1", NOOP)
	end
	if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end
	if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
	b:SetScript("OnEnter", slotTooltip)
	b:SetScript("OnLeave", function()
		if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
	end)
	b:SetScript("OnDragStart", function(self)
		if (db and db.locked) or not frame or inCombat() then return end
		dragged = true
		if self.SetAttribute then self:SetAttribute("type1", NOOP) end
		frame:StartMoving()
	end)
	b:SetScript("OnDragStop", function(self)
		if not frame then return end
		frame:StopMovingOrSizing()
		savePosition()
		if dragged then endDrag(self) end
	end)
	-- OnClick belongs to the secure template (it uses the item). Our
	-- non-secure clicks run after it, in PostClick.
	b:SetScript("PostClick", function(self, button)
		-- A Key Binding press only uses the item (secure OnClick above). It
		-- never removes (even if bound with Alt) or opens the goal box.
		if button == T.KEY_BUTTON then return end
		if button ~= "LeftButton" and button ~= "RightButton" then return end
		if dragged then return end
		if not self.itemID then return end
		if IsAltKeyDown and IsAltKeyDown() then
			hideGoalBox()
			T.Remove(self.itemID)
			return
		end
		if button == "RightButton" then
			showGoalBox(self, self.itemID)
			lastTouched = self.itemID
		end
	end)
	return b
end

local function buildFrame()
	if frame or not CreateFrame then return frame end
	frame = CreateFrame("Frame", "NeedfulSlotsFrame", UIParent, "BackdropTemplate")
	frame:Hide()
	frame:SetSize(40, 44)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if (db and db.locked) or inCombat() then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 12, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0.7) end
	end
	for i = 1, T.MAX do
		slots[i] = makeSlot(frame, i)
	end
	goalBox = CreateFrame("EditBox", "NeedfulSlotsGoalBox", frame, "InputBoxTemplate")
	goalBox:SetSize(48, 20)
	goalBox:SetAutoFocus(false)
	if goalBox.SetNumeric then goalBox:SetNumeric(true) end
	if goalBox.SetMaxLetters then goalBox:SetMaxLetters(6) end
	goalBox:Hide()
	goalBox:SetScript("OnEnterPressed", function(self)
		local id = self.itemID
		hideGoalBox()
		if id then T.SetGoal(id, tonumber(self:GetText())) end
	end)
	goalBox:SetScript("OnEscapePressed", hideGoalBox)
	T._frame = frame
	T._goalBox = goalBox
	T._slots = slots
	return frame
end

-- Count text and colour only. Safe in combat (FontStrings are not protected).
-- Uses the item each icon currently shows; a goal change applies right away.
function T.UpdateCounts()
	for i = 1, T.MAX do
		local slot = slots[i]
		if not slot then break end
		local id = slot.itemID
		if id and slot.count and slot.count.SetText then
			local it = T.Find(id)
			local goal = it and it.goal
			local count = T.Count(id)
			slot.count:SetText(T.CountText(count, goal))
			if slot.count.SetTextColor then slot.count:SetTextColor(T.CountColor(count, goal)) end
		end
	end
end

-- Full layout: icons, secure use attributes, size, anchors, visibility.
-- In combat only the counts update; the layout waits for PLAYER_REGEN_ENABLED.
function T.Refresh()
	if not db then return end
	if inCombat() then
		layoutPending = true
		T.UpdateCounts()
		return
	end
	if not frame then
		if CreateFrame then buildFrame() else return end
	end
	layoutPending = false
	applyPosition()
	applyLock()
	local n = #db.items
	local width = 8 + n * 38
	if width < 44 then width = 44 end
	frame:SetSize(width, 44)
	for i = 1, T.MAX do
		local slot, it = slots[i], db.items[i]
		if not slot then break end
		if it then
			slot.itemID = it.id
			local tex = itemIcon(it.id)
			if slot.icon and slot.icon.SetTexture then slot.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark") end
			if not dragged then setUse(slot, it.id) end
			slot:ClearAllPoints()
			slot:SetPoint("LEFT", frame, "LEFT", 4 + (i - 1) * 38, 0)
			slot:Show()
		else
			slot.itemID = nil
			setUse(slot, nil)
			slot:Hide()
		end
	end
	T.UpdateCounts()
	if n == 0 then
		hideGoalBox()
		frame:Hide()
	else
		frame:Show()
	end
	if goalBox and goalBox.IsShown and goalBox:IsShown() then
		if not goalBox.itemID or not T.Find(goalBox.itemID) then hideGoalBox() end
	end
end

-- Leaving combat: apply anything that was queued.
function T.OnRegenEnabled()
	combatNoted = false
	if layoutPending then T.Refresh() end
end

function T.LayoutPending()
	return layoutPending and true or false
end

function T.RequestRefresh()
	if pendingRefresh then return end
	pendingRefresh = true
	after(0.1, function()
		pendingRefresh = false
		T.Refresh()
	end)
end

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------

local function help()
	out("Alt-right-click a bag item to start or stop tracking it (up to %d).", T.MAX)
	out("On the bar: left-click uses the item, right-click sets a goal, Alt-click stops tracking.")
	out("Keybinds: Esc > Options > Game > Keybindings > AddOns > Needful Slots (Use Needful Slot 1-4).")
	out("/needful add [item]    Track an item (shift-click it into the chat box)")
	out("/needful goal [item] n Set a goal, or /needful goal n for the last item")
	out("/needful remove [item] Stop tracking an item (or the last one)")
	out("/needful clear         Remove every item")
	out("/needful lock          Lock the bar in place (or /needful unlock)")
	out("/needful reset         Move the bar back to the default position")
	out("/needful help          This list")
	out("/nslots works the same as /needful.")
end

local function pickTarget(rest, needId)
	local id = parseItem(rest)
	if id then return id, rest end
	if lastTouched and T.Find(lastTouched) then return lastTouched end
	if db and #db.items == 1 then return db.items[1].id end
	if needId then out("Shift-click an item into the command, e.g. /needful %s [item].", needId) end
	return nil
end

function T.Slash(msg)
	if not db then T.InitDB(NeedfulSlotsCharDB) end
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "help" or cmd == "status" then
		if cmd == "" and db and #db.items > 0 then
			for _, it in ipairs(db.items) do
				local count = T.Count(it.id)
				if it.goal then
					out("%s  %s", itemLink(it.id), T.CountText(count, it.goal))
				else
					out("%s  %d", itemLink(it.id), count)
				end
			end
			out("Bar is %s. /needful help for commands.", db.locked and "locked" or "unlocked")
		else
			help()
		end
	elseif cmd == "add" then
		local id = parseItem(rest)
		if not id then out("Shift-click an item into the command: /needful add [item].") return end
		T.Add(id, rest)
	elseif cmd == "goal" then
		local idFromLink = parseItem(rest)
		local n = tonumber((rest or ""):match("(%d+)%s*$"))
		-- "/needful goal 20" vs "/needful goal [Item] 20" vs "/needful goal [Item]" (clear if no number after the link).
		local id
		if idFromLink and n and tostring(n) ~= tostring(idFromLink) then
			id = idFromLink
		elseif idFromLink and (rest or ""):find("item:", 1, true) then
			-- "/needful goal [Item] 20" — n is the last number, id is the item.
			id = idFromLink
			local afterLink = rest:match("|h|r%s*(%d+)%s*$") or rest:match("%]%s*(%d+)%s*$")
			n = tonumber(afterLink)
		else
			id = pickTarget(nil, "goal")
			n = tonumber(rest)
		end
		if not id then return end
		T.SetGoal(id, n)
	elseif cmd == "remove" or cmd == "rm" or cmd == "del" then
		local id = parseItem(rest)
		if not id then id = pickTarget(nil, "remove") end
		if not id then return end
		if not T.Remove(id) then out("That item is not being tracked.") end
	elseif cmd == "clear" then
		T.Clear()
	elseif cmd == "lock" then
		T.SetLocked(true)
	elseif cmd == "unlock" then
		T.SetLocked(false)
	elseif cmd == "reset" then
		T.ResetPosition()
	else
		out("Unknown command %q.", cmd)
		help()
	end
end

SLASH_NEEDFULSLOTS1 = "/needful"
SLASH_NEEDFULSLOTS2 = "/nslots"
if SlashCmdList then SlashCmdList.NEEDFULSLOTS = function(msg) T.Slash(msg) end end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

if CreateFrame then
	local ev = CreateFrame("Frame")
	T._ev = ev
	ev:RegisterEvent("ADDON_LOADED")
	ev:RegisterEvent("PLAYER_LOGIN")
	pcall(ev.RegisterEvent, ev, "BAG_UPDATE")
	pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED")
	pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event, a1)
		if event == "ADDON_LOADED" and a1 == addonName then
			NeedfulSlotsCharDB = T.InitDB(NeedfulSlotsCharDB)
			T.HookBags()
		elseif event == "ADDON_LOADED" then
			-- Bagnon / default bag UI may load after us.
			T.HookBags()
		elseif event == "PLAYER_LOGIN" then
			if not db then NeedfulSlotsCharDB = T.InitDB(NeedfulSlotsCharDB) end
			T.HookBags()
			T.Refresh()
		elseif not db then
			return
		elseif event == "PLAYER_REGEN_ENABLED" then
			T.OnRegenEnabled()
		elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
			T.RequestRefresh()
		end
	end)
end
