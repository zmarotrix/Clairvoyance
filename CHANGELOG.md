# Changelog

## 0.9.6, 2026-11-06

- **Quest colours in the tracker:** the colour down the left side of each row can now be turned off
  (Settings, Quest tracker, "Quest colours on the left").
- **Simple view:** the Compact view is now called Simple and looks like Questie's tracker: plain text
  with no cards, grey zone names, `[12] Quest name` in its difficulty colour, objectives underneath,
  and a green "Quest Complete!". Click a quest to fold its objectives. The sort and view switches
  appear above the tracker when you point at it. In the Detailed view, clicking a card still folds it
  to one line.

## 0.9.5, 2026-11-06

- **Quest items in your bags:** the mark is now the game's own "!", the one on the minimap, with no
  circle behind it.

## 0.9.4, 2026-11-06

- **Quest items in your bags:** a small "!" on items a quest in your log needs, items that start a
  quest you haven't done, and quest items. A needed item stays marked after you have enough, because
  you still have to turn it in. It's on by default, with a setting under Bags, and it also shows in
  Dimension's bag window.

## 0.9.3, 2026-11-06

- **Default quest tracker:** when the game brings it back during combat, it's now hidden straight
  away. Before, it stayed on screen until the fight ended.

## 0.9.2, 2026-11-05

- **Minimap:** Clairvoyance no longer draws its small "?" and "!" over the game's own marks. They
  stay on the world map, and a new setting under Map brings them back to the minimap.

## 0.9.1, 2026-11-04

- **Quest item buttons:** they can be clicked now (they were sitting underneath the tracker's
  cards). They hang off the outside of the quest's card, on the side away from the screen's edge,
  so quest titles all line up. A quest leaving the list takes its button with it.

## 0.9.0 (release candidate), 2026-10-19

The first complete build: every version 1 milestone is in. What's left before 1.0 is a week of
daily play against the in-game checklist (`docs/clairvoyance-checklist.md` in the suite
workspace) and the performance budgets (`/norg perf`).

- **Map, minimap and compass:** objectives in each quest's colour, turn-ins, available quests
  with full availability rules, level-less quests, shift-click hiding and the Hidden chip.
- **Quest tracker:** detailed and compact cards, four sorts, zone groups, pfQuest-style progress
  colours and percentages, finished quests in lime (optionally grouped), distance and direction
  with a set update rate, a drag-to-set length, combat-safe item buttons, party progress.
- **Tooltips** with your quests, progress and party progress (Questie-compatible).
- **Track anything** with the Finder: names and town services, the game's service icons,
  per-entry colours, right-click menu and Clear.
- **Gathering** chips per profession with the next-25-points band; **rares** with named loot and a
  nameplate alert.
- **Automation** (accept, turn in, reward by vendor value, skip gossip), off by default, Shift
  pauses it.
- **Quest log** levels, IDs and Show on map / Point arrow buttons.
- **Settings** per character or global; the welcome runs once per character (Simple, Balanced,
  Everything), and never again on a reload.

Requires NorgannonDB_Core 1.10 (performance profiler, colours for any key, service icons).
