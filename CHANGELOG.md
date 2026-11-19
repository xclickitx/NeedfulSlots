# Changelog

All notable changes to Bean Counter are listed here.

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
