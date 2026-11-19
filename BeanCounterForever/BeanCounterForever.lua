-- Bean Counter 1.0.2 by ClickIT, for WoW Forever (Interface 16001).
--
-- A small, quiet bar (title: Bean Counter; folder: BeanCounterForever, so it
-- does not clash with Auctioneer's BeanCounter module) that tracks up to four
-- items from your bags. Alt-right-click a bag item to start or stop tracking
-- it (one gesture). Alt-left-click is left alone: Bagnon uses it for Flash
-- Find (on by default) and Auctionator's default "select item to sell"
-- shortcut is also Alt-left-click when the auction house is open. Shift-clicks
-- stay with the default UI (stack split and chat linking). The bar is only
-- icons; when unlocked, left-drag an icon to move it. The count is bags only.
-- An optional goal turns the number green when you reach it; it keeps
-- counting past the goal. No sounds, popups or flashes. The bar hides when
-- nothing is being tracked.
--
-- Client API: C_Item.GetItemCount / GetItemInfo / GetItemIconByID, with
-- GetItemCount / GetItemIcon fallbacks (the same pattern as Alchemist's
-- Cookbook). Bag clicks are hooked with hooksecurefunc on
-- ContainerFrameItemButton_OnModifiedClick / _OnClick and, if present,
-- ContainerFrameItemButtonMixin, which is also what Bagnon/BagBrother's
-- item buttons inherit. Counts refresh on BAG_UPDATE, bucketed with
-- C_Timer.After so a burst of bag events does not scan every time.

local addonName = ... or "BeanCounterForever"

local T = {}
_G.BeanCounterForever = T
T.VERSION = "1.0.2"
T.NAME = "Bean Counter"
T.MAX = 4

local floor, format, tonumber, tostring, type, select = math.floor, string.format, tonumber, tostring, type, select
local pairs, ipairs, pcall = pairs, ipairs, pcall
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local DEFAULTS = {
	items = {}, -- { {id=itemID, goal=nil or number}, ... } max 4, keep order
	pos = nil,  -- { point, relPoint, x, y }
	locked = false,
}

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

local PREFIX = "|cffffd100Bean Counter|r: "
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

function T.InitDB(saved)
	saved = type(saved) == "table" and saved or {}
	-- If this character has no Bean Counter data yet, copy a leftover Tally save
	-- from the same session (Tally's WTF file is not loaded once that add-on is gone).
	if type(TallyCharDB) == "table" then
		local empty = type(saved.items) ~= "table" or #saved.items == 0
		if empty and type(TallyCharDB.items) == "table" and #TallyCharDB.items > 0 then
			saved.items = {}
			for i, it in ipairs(TallyCharDB.items) do
				if type(it) == "table" then
					saved.items[i] = { id = it.id, goal = it.goal }
				end
			end
			if saved.pos == nil then saved.pos = TallyCharDB.pos end
			if saved.locked == nil then saved.locked = TallyCharDB.locked end
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

local lastTouched -- itemID last added or clicked on the bar, for /beans goal N

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
	T.Refresh()
	return true
end

function T.Remove(id)
	id = tonumber(id)
	if not id or not db then return false end
	local _, i = T.Find(id)
	if not i then return false, "missing" end
	local link = itemLink(id)
	table.remove(db.items, i)
	if lastTouched == id then lastTouched = db.items[1] and db.items[1].id end
	out("Removed %s.", link)
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
	T.Refresh()
	return db.locked
end

function T.ResetPosition()
	if not db then return end
	db.pos = nil
	out("Bar moved back to the default position.")
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
		-- Skip bank / other non-inventory bags; /beans add still works for those.
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
		GameTooltip:AddLine("Alt-click: stop tracking · Right-click: set goal · Drag to move", 0.8, 0.8, 0.8)
	end
	if GameTooltip.Show then GameTooltip:Show() end
end

local function makeSlot(parent, i)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(36, 36)
	b.index = i
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	b.icon = tex
	local fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	b.count = fs
	if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
	if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
	b:SetScript("OnEnter", function(self) slotTooltip(self) end)
	b:SetScript("OnLeave", function()
		if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
	end)
	b:SetScript("OnDragStart", function(self)
		if db and db.locked then return end
		if not frame then return end
		dragged = true
		frame:StartMoving()
	end)
	b:SetScript("OnDragStop", function(self)
		if not frame then return end
		frame:StopMovingOrSizing()
		savePosition()
	end)
	b:SetScript("OnClick", function(self, button)
		if dragged then
			dragged = false
			return
		end
		if not self.itemID then return end
		-- Plain left-click does nothing. Alt-click (either button) stops tracking.
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
	frame = CreateFrame("Frame", "BeanCounterForeverFrame", UIParent, "BackdropTemplate")
	frame:Hide()
	frame:SetSize(40, 44)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if db and db.locked then return end
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
	goalBox = CreateFrame("EditBox", "BeanCounterForeverGoalBox", frame, "InputBoxTemplate")
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
	return frame
end

function T.Refresh()
	if not db then return end
	if not frame then
		if CreateFrame then buildFrame() else return end
	end
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
			local count = T.Count(it.id)
			if slot.count and slot.count.SetText then
				slot.count:SetText(T.CountText(count, it.goal))
				if slot.count.SetTextColor then slot.count:SetTextColor(T.CountColor(count, it.goal)) end
			end
			slot:ClearAllPoints()
			local x = 4 + (i - 1) * 38
			slot:SetPoint("LEFT", frame, "LEFT", x, 0)
			slot:Show()
		else
			slot.itemID = nil
			slot:Hide()
		end
	end
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
	out("/beans add [item]    Track an item (shift-click it into the chat box)")
	out("/beans goal [item] n Set a goal, or /beans goal n for the last item")
	out("/beans remove [item] Stop tracking an item (or the last one)")
	out("/beans clear         Remove every item")
	out("/beans lock          Lock the bar in place (or /beans unlock)")
	out("/beans reset         Move the bar back to the default position")
	out("/beans help          This list")
	out("/tally still works as an alias for /beans.")
end

local function pickTarget(rest, needId)
	local id = parseItem(rest)
	if id then return id, rest end
	if lastTouched and T.Find(lastTouched) then return lastTouched end
	if db and #db.items == 1 then return db.items[1].id end
	if needId then out("Shift-click an item into the command, e.g. /beans %s [item].", needId) end
	return nil
end

function T.Slash(msg)
	if not db then T.InitDB(BeanCounterCharDB) end
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
			out("Bar is %s. /beans help for commands.", db.locked and "locked" or "unlocked")
		else
			help()
		end
	elseif cmd == "add" then
		local id = parseItem(rest)
		if not id then out("Shift-click an item into the command: /beans add [item].") return end
		T.Add(id, rest)
	elseif cmd == "goal" then
		local idFromLink = parseItem(rest)
		local n = tonumber((rest or ""):match("(%d+)%s*$"))
		-- "/beans goal 20" vs "/beans goal [Item] 20" vs "/beans goal [Item]" (clear if no number after the link).
		local id
		if idFromLink and n and tostring(n) ~= tostring(idFromLink) then
			id = idFromLink
		elseif idFromLink and (rest or ""):find("item:", 1, true) then
			-- "/beans goal [Item] 20" — n is the last number, id is the item.
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

SLASH_BEANCOUNTER1 = "/beans"
SLASH_BEANCOUNTER2 = "/tally"
if SlashCmdList then SlashCmdList.BEANCOUNTER = function(msg) T.Slash(msg) end end

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
	ev:SetScript("OnEvent", function(_, event, a1)
		if event == "ADDON_LOADED" and a1 == addonName then
			BeanCounterCharDB = T.InitDB(BeanCounterCharDB)
			T.HookBags()
		elseif event == "ADDON_LOADED" then
			-- Bagnon / default bag UI may load after us.
			T.HookBags()
		elseif event == "PLAYER_LOGIN" then
			if not db then BeanCounterCharDB = T.InitDB(BeanCounterCharDB) end
			T.HookBags()
			T.Refresh()
		elseif not db then
			return
		elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
			T.RequestRefresh()
		end
	end)
end
