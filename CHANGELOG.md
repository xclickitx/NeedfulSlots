# Changelog

All notable changes to Needful Slots (formerly Bean Counter) are listed here.

## 1.0.3

- **Renamed to Needful Slots.** Folder, TOC and Lua file are now `NeedfulSlots`, saved variables are `NeedfulSlotsCharDB`, and the slash commands are `/needful` and `/nslots` (`/beans` and `/tally` are gone). Chat messages start with "Needful Slots:".
- **Left-click an icon to use the item.** Each icon on the bar is now also a use button: eat or drink tracked food, open a container, place a fishbowl, and so on. Items with no use do nothing. The tooltip shows "Left-click: use" when the item has a use.
- Only a plain left-click uses the item. Alt-click still stops tracking (and never uses the item), right-click still sets a goal, and left-drag still moves the bar when it is unlocked (the release after a drag does not use the item).
- Combat: WoW does not let add-ons change use buttons during combat. Tracking, untracking, lock, reset and the bar hiding/showing are saved right away but the bar itself updates when combat ends (chat says so once per fight). Counts, colours and goals still update in combat, and using an item works in combat.
- **Keybinds.** Esc > Options > Keybindings > AddOns > Needful Slots has "Use Needful Slot 1" to "Use Needful Slot 4". Each key uses the item in that slot, like left-clicking its icon, and works in combat. An empty slot's key does nothing. The tooltip shows the bound key.
- Settings carry over from Bean Counter: if `NeedfulSlotsCharDB` is empty and the old `BeanCounterCharDB` is loaded, it is copied over and the old table is cleared.
- No public Lua global for the add-on table any more (it lives in the private add-on namespace).

## 1.0.2

- Alt-right-click a bag item now toggles it: first click starts tracking, a second click on the same item stops. Chat says "Tracking" or "Removed".
- On the bar, Alt-click an icon also stops tracking. Right-click still sets a goal. Ctrl-click was removed, so there is only one click gesture.
- The "Beans" label is gone. The bar is just the icons. When it is unlocked, left-drag an icon to move it (`/beans lock`, `/beans unlock`, and `/beans reset` still work).

## 1.0.1

- Tracking an item in your bags is now Alt-right-click, because Shift-right-click also split stacks in Bagnon. Alt-left-click is left alone: Bagnon uses it for Flash Find, and Auctionator's default "select item to sell" shortcut is Alt-left-click when the auction house is open.
- On the bar, Alt-click (or Ctrl-click) an icon to stop tracking it. Right-click still sets a goal.
- The bar hides when nothing is being tracked, including at login, and comes back when you add an item.

## 1.0.0

- First release for WoW Forever (Interface 16001).
- Shift-right-click an item in your bags to track it (up to four). Shift-left-click is left alone so stack-splitting and chat linking still work.
- A small movable, lockable bar shows each item's icon and a live bag count. An optional goal turns the number green when you reach it; the count keeps going past the goal.
- Right-click an icon to set a goal, Shift-right-click or Ctrl-click to remove it.
- `/beans` commands (with `/tally` as an alias): add, goal, remove, clear, lock, unlock, reset, help.
- Saved per character: tracked items, goals, bar position and lock.
- Folder name is BeanCounterForever so it does not clash with Auctioneer's BeanCounter module.
