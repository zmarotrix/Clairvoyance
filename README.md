# Clairvoyance

A modern quest helper for WoW Forever, built on **NorgannonDB** and **NorgannonDB Core**. It's
part of the NorgannonDB suite, together with Oracle, Foresight and Archivum.

Clairvoyance shows you where things are. It never tells you which quest to do next: there's no
leveling guide, and the waypoint arrow only points where you ask.

**v0.9 (release candidate)**

- **On the map, minimap and compass:**
  - your unfinished objectives, in each quest's own colour (click a pin for a new colour,
    right-click to choose one)
  - turn-ins (the game's "?"), and quest givers with quests you can take (the game's "!", with
    level-correct filtering: prerequisites, chains, race, class, profession, reputation)
  - shift-click any marker to hide that quest; the "Hidden" chip brings them back
- **Track anything:** the magnifier in the tracker (or "Track…" on the map) finds NPCs, objects,
  items and town services (flight masters, mailboxes, innkeepers…, with the game's own icons).
  Tracked things get their own colour, a compass marker and a row in the tracker.
- **Gathering:** with Herbalism, Mining or Fishing, a map chip ("Herbs · 145") shows the nodes you
  can gather now and, dimmed, the next 25 skill points' worth.
- **Rares:** rare NPCs with their level and their own loot, and an optional quiet alert when one
  appears on your nameplates.
- **The quest tracker:** every quest in your log, sorted Nearest, Zone, Level or Log; detailed or
  compact cards (click a quest to switch it); pfQuest-style progress colours; finished quests in
  lime, grouped at the top or bottom if you like; distance and direction; a "use item" button
  that works in combat; party members' progress (Questie-compatible). Drag the bottom edge to set
  its length.
- **Tooltips:** which of your quests an NPC, object or item is for, your progress and your party's.
- **Quest log:** levels, optional quest IDs, and Show on map / Point arrow buttons.
- **Automation, off unless you turn it on:** accept, turn in, choose the best-value reward, skip
  gossip. Hold Shift to pause it.
- **Settings per character or global.** The first-run welcome offers three starting points
  (Simple, Balanced, Everything) once per character.

Commands: `/clair` (settings), `/clair why <questId>` (why a quest is or isn't available),
`/clair welcome` (this character's first-time setup again). Suite-wide: `/norg perf` measures
performance against the suite's budgets.

Requires NorgannonDB and NorgannonDB Core. Made by **Maro**. All rights reserved for now; see
`LICENSE`.
