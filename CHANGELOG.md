# Changelog

## 0.11.0, 2026-11-08

- **Two quest marks in your bags, and none over the game's own.** A gold "?", the game's turn-in mark, is on items a quest
  in your log needs. A silver diamond is on items a quest you could pick up needs, so you know not to sell them. Items
  that start a quest keep only the game's "!", which our old "!" used to cover. Quest items with no quest we know of
  keep only the game's gold border. The marks show in Dimension's bag window too.

## 0.10.3, 2026-11-08

- **Low-level "!" markers are hidden again.** 0.10.2 rated quests you haven't taken by the game's rating, but the
  client doesn't rate quests outside your log properly, so every low-level quest showed as a normal "!". Quests you
  can pick up (grey markers, their tooltips, auto-accept's low-level skip) go by the level rule again. Quests in your
  log keep the game's rating from 0.10.1, so the tracker still matches the quest log.

## 0.10.2, 2026-11-08

- **Quests you can pick up are rated by the game too.** Whether a "!" is grey (and hidden unless low-level quests are
  shown), the colours in its tooltip, and which quests auto-accept skips as low level now follow the server's own
  rating, as the quest log does, instead of Classic's level ranges. "Far above your level" still goes by level.

## 0.10.1, 2026-11-08

- **Tracker colours match the quest log.** WoW Forever's quest log colours each quest by how the server rates it for
  you, not by Classic's level ranges. The tracker worked the colour out from the level, so a quest the log showed
  green could be grey on the tracker. It now asks the game the same way (falling back to the level rule on a client
  that can't say).
- `/clair why <questId>` also says how the game rates the quest next to the level rule.

## 0.10.0, 2026-11-07

Faster, with nothing changed in how it looks or behaves (docs/clairvoyance-perf-review.md in the suite workspace).

- **The tracker's timed update only moves distances and arrows.** It used to refill every card every half second.
  Standing still and facing the same way, it now does nothing at all. Everything else on the cards updates when it
  changes.
- **Each quest's nearest target is worked out once per update**, not twice in the Nearest sort, and not at all
  while you stand still.
- **Kills and loot cost much less.** Progress no longer re-runs the rules for which quests are available nearby,
  republishes the "!" markers or re-checks bag items. Those happen only when a quest joins or leaves your log. A
  quest's map pins are rebuilt only when an objective finishes or the quest completes, not on every count. Where an
  objective happens (an item's drop sources, say) is worked out once per quest, not on every kill.
- **`/clair perf [seconds | stop | report]`** measures Clairvoyance while you play: the suite profiler's report,
  plus how many quests and pins Clairvoyance holds and how fast its memory grew.

## 0.9.9, 2026-11-07

- **Level badges are centred.** The number now fills its badge and the game centres it in the badge's own bounds,
  instead of a hand-placed 1-pixel nudge that read off-centre at some widths. The soft glow behind the number is gone
  from inside the badge, where it smeared the digits; the badge's dark fill gives the contrast.

## 0.9.8, 2026-11-07

- **The Compact view is back.** 0.9.6 replaced it with a plain-text "Simple" view styled after Questie's tracker. That
  was a misreading of what was asked for, so the tracker is back to Detailed and Compact cards as before 0.9.6. The
  setting to turn off the quest colours on the left stays.

## 0.9.7, 2026-11-07

- Built on NorgannonDB Core 1.20's `Core:NewAddon`. The minimap row works as before: a click shows or hides the
  tracker, Shift-click opens Track anything and right-click opens settings. `/clair help` lists the commands, and
  `/clair` alone still opens settings.
- The "Show the minimap button" setting is gone: NorgannonDB > Minimap pins any add-on.
- Settings asked for in combat open when the fight ends.

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
