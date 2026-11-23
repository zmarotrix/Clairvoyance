# Changelog

## 0.22.1 (2026-11-22)

- Objective dots are one size again, merged or not, and a little smaller than before.

## 0.22.0 (2026-11-22)

- **Fewer, bigger dots.** Where a mob was seen many times close together, one dot now stands for them all, a little
  larger the more it covers, instead of a trail or a crowd of small ones. Mount Hyjal goes from about 9,400 dots to
  1,400. "Merge nearby dots" under Map turns it off.

## 0.21.1 (2026-11-21)

- A finished quest's party line reads "[Dragonkin Menace] Quest Complete!".

## 0.21.0 (2026-11-21)

- **Pick what your party hears.** A new Party chat section in the settings holds the main switch and one per kind
  of line: every kill and item (off), finished objectives (on), finished quests (on), quests you pick up (off) and
  quests you abandon (on). "Abandoned [quest]" is new; a quest you hand in is never called abandoned.

## 0.20.2 (2026-11-21)

- Party chat lines give an objective's count once ("Black Broodling slain 15/15"), not twice.

## 0.20.1 (2026-11-19)

- Party chat lines start with Clairvoyance's name: "{diamond} Clairvoyance: [Dragonkin Menace] Black Broodling slain 15/15".

## 0.20.0 (2026-11-19)

- **Your party hears how your quests go.** When you finish an objective, party chat gets a line like
  "{diamond} [Dragonkin Menace] Black Broodling slain 15/15", and when the last one is done, "[Dragonkin Menace] is
  ready to hand in". Only finished objectives, never every kill, each said once. Never in raids, and quiet while
  Questie is running, since it says the same. Turn it off with "Tell your party" under Automation.

## 0.19.0 (2026-11-16)

- **A quest to pick up for a dungeon** (Oracle's Track pickups): clicking its row in the tracker opens a small map
  beside it, with the giver's eye pulsing on its zone, the coordinates and where you are when you're in that zone.
  Click the row again or press Escape to close it. The arrow points at the giver when it's on your continent, and
  its eye also pulses on your world map when you next open it on that zone. Hovering a row lights just its own giver.
- If you open your world map on another zone after clicking such a row, a strip at the top of the map says where to
  go: "Pick up Deviate Hides from Nalpak in The Barrens (46.0, 35.7)". It goes when you reach that zone on the map,
  where the giver's eye pulses, when you close it with its x, take the quest or after five minutes. Add-ons can't
  turn Blizzard's map to that zone for you without breaking its quest pins.
- A dungeon quest that starts from an item (The Essence of Eranikus) now shows who drops the item. The row says
  "from Shade of Eranikus", and its eye sits on the dungeon's entrance when the dropper is only inside. Givers who
  stand only inside a dungeon get an eye on its entrance too. Before, these said "isn't known yet", once per click.
- **A dungeon's quests get their own section in the tracker** (Oracle's "Track these quests"). It sits at the top,
  named for the instance, and holds the instance's quests in your log, including the earlier steps of their chains,
  so they aren't mixed in with the rest. Below them is a row for each quest still to pick up, with the eye from the
  map, what it comes before and an arrow to its nearest giver.
- Click the section's heading to fold it; right-click it for its colour and to stop tracking.
- Once every quest on the list is handed in, the section leaves the tracker on its own.
- Class and profession quests no longer show the 'NorgannonDB doesn't know this quest' mark; they're filed under
  their class or profession instead of a zone.
- **Hover a tracked quest to see your whole group on it.** Under the objectives, "Your group" lists you and each
  member: their count for each objective, "Ready to turn in", "Not on this quest", or "Not shared" for members
  whose add-ons don't share progress (it works with Clairvoyance and Questie). It replaces the small lines that
  used to sit under each objective.
- **Auto-accept leaves grey quests alone**, even while low-level quests show on the map. A new switch under
  Automation, "Accept grey quests too", takes them as well; it's off unless you turn it on.

## 0.18.1 (2026-11-15)

- A dungeon's pickups on the map are Clairvoyance's eye with a soft teal glow instead of a yellow !, so they stand
  out from the other quest marks. They sit above every other mark and are slightly see-through, so the marks under
  them still show.

## 0.18.0 (2026-11-15)

- **A dungeon's pickups on the map** (Oracle's "Show all on the map"): a ! on each quest's giver, or on the giver
  of the first quest before it you can take now. The tracker lists it under Tracking with how many are left to pick
  up and the distance to the nearest; each one leaves the map as you take it, and the next step of a chain comes on.
- Fixed: escort and exploring quests (The Forgotten Pools, The Defias Brotherhood, The Fargodeep Mine and about
  170 more) were treated as seasonal and never shown as available. Only world-event quests are seasonal now.

## 0.17.3 (2026-11-15)

- **Nameplate quest marks are smaller and sit left of the health bar**, with your progress beside them (3/10) instead of how many are left. Two quests wanting the same mob add up.

## 0.17.2 (2026-11-15)

- **/clair plates** lists each nameplate on screen and why it has a quest mark or not: its GUID is hidden, nothing is left to do on it, or the mark is drawn and where.

## 0.17.1 (2026-11-15)

- **Quest marks on nameplates are easier to read.** Each mark is now a badge: a dark disc with a thin gold ring, a full-colour sword or bag inside, and the count in bold white on its corner. The thin red cross was hard to read against red health bars, and its count was too small. Needs Norgannon Core 1.28.7.

## 0.17.0 (2026-11-15)

- **Quest mobs are marked on their nameplates.** A mob you still need to kill for a quest in your log shows a red sword to the right of its health bar, with how many are left. A mob that drops something you need shows a gold bag. A mob that's both shows both. The marks update as you make progress and go away once an objective is done. Turn them off under Settings, Nameplates. Needs Norgannon Core 1.28.6.
- **The quest you clicked stays selected in the map's quest list.** Clicking a quest's name in the tracker marks its row in the list for as long as the map stays open, instead of only glowing for a few seconds. It also waits a moment for the list to finish laying out, so the mark lands even when the map has just opened.

## 0.16.4 (2026-11-11)

- **Clicking a quest's name in the tracker shows it in the quest log.** Its row in the log glows for a few seconds, so it's easy to find. With the map already open, clicking the name opens the quest's text, just as clicking it in the log does. It's the game's own click on the quest's row, so the map stays clean.
- A quest under a collapsed header in the log can't glow or open. The map still opens and the quest's dots still pulse.

## 0.16.3 (2026-11-11)

- **Forever's own quests show their level again.** Quests from new content, such as Shen'dralas, showed a dash in the tracker's level badge instead of their level. They were treated like quests anyone can do at any level, because the database has their level but not the minimum level to take them. Now a quest counts as having no real level only when its minimum level is known. This also fixes their colours, and whether their givers count as low level or far above you.

## 0.16.2 (2026-11-11)

- **Quest givers on zoomed-out maps.** On a continent map, every giver with quests for you shows as a small "!". Givers standing close together, such as a town's, merge into one mark, and its tooltip lists them. The same filters apply as on zone maps: low-level and far-above quests stay hidden unless their settings are on. The continent's zones are worked out one per frame the first time you open it, so the marks fill in over a moment. Needs Norgannon Core 1.28.5.
- Gathering spots and rares still cover only your zone and the zones you look at up close.

## 0.16.1 (2026-11-11)

- **Quest givers show in every zone on the map.** On OpenMap's stitched map, available quests showed only in your own zone and the zone under the middle of the map. Neighbouring zones showed their objectives but no givers. Now every zone in view gets its givers. Each new zone is worked out on its own frame, so panning across the map doesn't stall. Needs Norgannon Core 1.28.4.
- Gathering spots and rares cover the zones in view too.
- `/clair available` lists, for your zone and each zone on the map, how many quest givers are on the map and how many are hidden: low level, far above you, or hidden by you.

## 0.16.0 (2026-11-11)

- **Every quest's name in the tracker opens the map.** Click a quest's name and the map opens with the quest log beside it, and that quest's dots pulse. If the quest is in another zone, chat says which one. It works in combat too, the same clean way as the map button: the game opens the map as if you had pressed its quest log button. When the map is already open, clicking a name leaves it open and shows that quest. One exception: in combat, a click on a name closes an open map, because the game's button toggles the map.
- The name underlines when you point at it. Clicking elsewhere on the card still expands or compacts the quest. Ctrl-click, shift-click and right-click do the same thing on the name as anywhere else on the card.
- The quest tooltip's hints name the new click.

## 0.15.0 (2026-11-11)

- **A map button in the tracker's header** (the pin, beside search). It opens the map and makes the focused quest's dots pulse, or the top quest's if none is focused. It works in combat too. It clicks the game's own quest log button for you, so the game opens the map as if you had, and the map's pins stay clean. The map opens on your zone; for a quest in another zone, chat says which zone it's in.
- While the tracker is being dragged, the map button hides, and it comes back over its spot when you let go. You can't drag the tracker in combat, as before.
- `/clair maptaint` says when only OpenMap has touched the map's pins: that's OpenMap's own features, not the suite.
- `/clair mapprobe` is gone; it found the way the map button works.

## 0.14.12 (2026-11-11)

- `/clair maptaint` no longer counts OpenMap's combat fix as damage. OpenMap puts its own mouse setup on every map pin on purpose, so the map doesn't error in combat. Those pins are now reported apart, and only other changes count as tainted.

## 0.14.11 (2026-11-10)

- `/clair maptaint` works on this client: it reads the map's pins from its pin pools, as this map has no single pin list.

## 0.14.10 (2026-11-10)

- `/clair maptaint` says why when it can't check the map (the map not loaded yet, say) instead of only "Can't check the map on this client."

## 0.14.9 (2026-11-10)

- `/clair mapprobe`: a test for opening the map from "Show on map" without breaking it. It shows a button that clicks one of the game's own map buttons for you, then reports whether the map opened and whether its pins stayed clean. Research only for now.

## 0.14.8 (2026-11-10)

- Pressing "Show on map" again right away no longer repeats "Open your map" in chat. It still waits for you to open the map, then the quest's dots pulse.

## 0.14.7 (2026-11-10)

- A creature or object's tooltip no longer lists your quest twice. When the game's own tooltip already shows the quest and your progress, Clairvoyance leaves it to the game and adds only what the game doesn't show.

## 0.14.6 (2026-11-10)

- The turn-in ? and the distance on a detailed card sit level with the quest's name, at the same height as on a compact card. The ? sat too high before.

## 0.14.5 (2026-11-10)

- A quest NorgannonDB doesn't know yet shows the Collector's small mark beside its name in the tracker. Its tooltip says what's missing: with the Collector running it asks you to share what it notes (/ndbc share), and without it, it says what the Collector is.
- A complete quest's turn-in ? now shows beside its name in the detailed view too, as it does in the compact view. The "Turn in" line stays below it.

## 0.14.4 (2026-11-10)

- Quests NorgannonDB doesn't know yet, such as The Drowned City's, now group under the zone your quest log shows instead of "Other" in the tracker's Zone order. Needs Norgannon Core 1.28.3.

## 0.14.3 (2026-11-09)

- Asks for Norgannon Core 1.22 or newer, the first Core with everything it needs; the map features from Core 1.28 switch on by themselves when Core has them. An older Core now gets a clear "update Norgannon Core" message instead of errors.

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
