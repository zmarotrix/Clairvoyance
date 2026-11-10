# Changelog

## 0.14.2, 2026-11-09

- **Fixed the world map and quest log failing to open** ("NorgannonDB_Core tried to call the protected function
  Button:SetPassThroughButtons()"). 0.12.2 still opened Blizzard's map itself, through the client's own function, and
  that taints the map's quest pins for the rest of the session just the same. "Show on map" now never opens or switches
  the map. If the map is open on the right zone, the dots pulse right away. Otherwise Clairvoyance says which zone to
  open ("Open your map (M): it's in Durotar."), and the dots pulse when you open the map there.
- Changing the quest log settings no longer redraws Blizzard's quest log from Clairvoyance's code. The titles update
  right away, and anything left updates the next time the log redraws.

## 0.14.1, 2026-11-09

- **Quest item buttons show without a reload.** A quest's usable item often reaches your bags a moment after you take
  the quest, and the quest log doesn't report that as a change, so the tracker never looked again. It now checks
  when your bags change and when the game finishes loading an item's details. The backup check (the item the quest
  gives you) also works on WoW Forever now: it used a function the client no longer has.

## 0.14.0, 2026-11-09

- **A ring per objective** (setting under Map, off by default). A quest's dots keep its colour, and each of its
  objectives gets its own border colour, so "kill boars" and "kill wolves" read apart on the map. The colour goes by
  objective number (white, black, cyan, pink, lime, orange), so a ring keeps its meaning as objectives finish. Only
  quests with two or more objectives on the map get rings. The tracker shows each objective's ring in the card's
  margin. Needs NorgannonDB Core with ring pins (Map.RINGS); without it nothing changes.

## 0.13.0, 2026-11-09

- **Clairvoyance no longer picks quest rewards for you.** The "Choose rewards" switch is gone from the settings and the
  welcome. With a choice of rewards, auto turn-in now always stops and leaves the choice to you.
- **A gold coin marks the reward that sells for the most** (its vendor price times how many you get), on the quest
  frame's reward choices. Ties mark each one. The coin waits until every choice's price is known, and doesn't show
  when nothing sells. Setting: Mark the best-selling reward, under Automation, on by default.

## 0.12.2, 2026-11-09

- **Fixed "Clairvoyance tried to call the protected function Button:SetPassThroughButtons()"** when toggling the world
  map, mostly in combat. Clairvoyance opened Blizzard's map and quest log from its own code, which made the map
  build its quest pins in tainted code, and those pins stayed tainted until a /reload. "Show on map" now opens the map
  the client's own way (C_Map.OpenWorldMap), and in combat it waits until combat ends.
- **"Open in quest log" is gone from the quest menu.** Blizzard's quest log can't be opened to a quest from add-on code
  without the same taint. "Show on map" selects the quest instead, so the quest log beside the map is on it.
- `/clair maptaint` checks whether add-on code has touched the world map's own pins (open the map first). If a
  /reload doesn't clear it, it names who did.

## 0.12.1, 2026-11-09

- **Tracked items show the reasonable sources**, judged against the item's best one. A source is kept when you'd need
  at most 10 times the kills or loots of the best source. Wool Cloth's best drops are around 25%, so a 2.5% drop is
  kept and a 0.02% skeleton isn't. An item whose best source is 0.5% keeps everything from 0.05% up, so rare items still
  show. Vendors always show.
- **New setting, Tracked items show** (Tracking, gathering and rares): the best odds (within 3x), reasonable odds
  (within 10x, the default), most sources (within 30x), or everything, with the long shots small and faint.

## 0.12.0, 2026-11-09

- **Tracking an item shows everywhere it comes from**, not just its 8 likeliest sources: every enemy that can drop it,
  every chest or object that holds it, every vendor, and where the containers it comes in are found (a trunk fished
  from a pool marks the pool). Tracking Wool Cloth now marks 795 sources.
- Long shots (under 1%, like a skeleton's 0.02%) stay on the map but small and faint, so the real farming spots stand
  out. When an item has no likely source at all, every source is drawn full.
- The tracker's distance and the arrow go to the nearest likely source, and the tracker line counts sources
  ("795 sources") rather than map pins.

## 0.11.2, 2026-11-08

- **Quest-givers correct the "!" markers.** Many quests new to WoW Forever have no prerequisites in the data, so a
  later step of a chain could show as available too early (the second "A Friend of the Family" on Bolvar). When you
  talk to a quest-giver, the game lists what it will really give you. A quest Clairvoyance expected there but the game
  left out loses its "!" for this character. It comes back when the quest-giver lists it, when you level up, or when you
  turn in a quest from the same zone or to that quest-giver. Grey quests are never judged, since the game leaves those
  off its list while low-level quests are hidden. `/clair why` says "not offered by its quest-giver".

## 0.11.1, 2026-11-08

- **Hide an item's quest mark** with a key: set one in Key Bindings, under AddOns, Clairvoyance, then press it over the
  item. The same key shows it again. It's for good and across your characters, and "Show them all again" in the
  settings brings back every hidden mark.
- **An item's tooltip says why it's marked.** Quests in your log were already listed with your progress. Now quests
  you could take are listed too, up to four, with their level. A last faint line names the key to hide the mark, or
  says it's hidden.

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
