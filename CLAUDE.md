# DiceBattles

A Roblox game. Code is synced into Studio by Rojo; the map, UI and models are built live in Studio through the Roblox Studio MCP tools and in Blender through the Blender MCP.

## Where things live (folder layout since 2026-10-17)

```
C:\FirstRobloxGame\           the git repo (GitHub joeycros13/DiceBattles), branch main
  CLAUDE.md  README.md  default.project.json  aftman.toml  .gitignore  .gitattributes
  src\        game code: shared\ server\ client\  (Rojo syncs it into Studio)
  art\        meshes\ (FBX + offsets JSON)  icons\ (weapons, materials, armor, cores)
              ui\ (hud, inventory, shop, quest, index, tiles; _older\ = superseded rounds)
              portraits\ (quest, enemies, worlds)  tools\ (the Python/HTML/SVG generators)
  blender\    models.blend            NOT in git; backed up to Google Drive
  place\      DiceBattles.rbxlx       the live place; NOT in git; backed up to Google Drive
  .claude\worktrees\   one per Claude session (managed by the app; not in git)
```

- Older notes below name files by their pre-2026-10-17 paths (`art/meshes/forest_w2.fbx`, `art/index/…`, `art/hud_buttons/…`). The FBX names follow the 2026-10-13 rename (`w2_forest.fbx`…; map in the `blender-modeling` skill), portraits are in `art/portraits/`, UI art in `art/ui/<area>/`, and generators in `art/tools/`. A full copy of the old layout is in `C:\Backups\DiceBattles_2026-10-17`.
- Never commit `place/` or `blender/` (the place is about 130 MB, over GitHub's 100 MB limit).
- This file is committed, so every session and worktree sees the same copy: update it on your branch and merge.

## Code: Rojo, files are the source of truth

- **Rojo 7.7.0** (Aftman): `default.project.json` maps `src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService.Server` and `src/client` → `StarterPlayer.StarterPlayerScripts.Client`, each with `$ignoreUnknownInstances`. So Rojo never deletes Studio instances it doesn't know: a deleted file's script must also be deleted in Studio by hand.
- Run `rojo serve` in the checkout or worktree you're working in, then press Connect in Studio's Rojo plugin. **Edit the `.luau` files**; never edit scripts in Studio's editor or through `.Source` while Rojo is connected (the next sync overwrites it).
- `.gitattributes` keeps `.luau` / `.json` / `.toml` LF (`core.autocrlf` is on here, and Rojo copies bytes as-is).
- The ServerStorage dev modules (`W2Swap`, `W3Swap`, `W3RimSolver`, `DevTools/*`…) and `StarterCharacter.Animate` stay in the place file only.
- Pre-Rojo Studio backup: `ServerStorage.CodeBackup_2026-10-17_PreRojo`.

## Studio

- Studio opens `place\DiceBattles.rbxlx`. Find the Studio instance with `list_roblox_studios` every session; its id changes whenever Studio reopens.
- Map, UI and model work uses `execute_luau` in the **Edit** datamodel. Edit mode is unavailable while a playtest runs, so stop play first.
- Changes live in Studio's memory until the user saves. Remind them to save the place (Ctrl+S) after a batch of work.

## Code layout (`src/`, synced into Studio)

- `ReplicatedStorage.Shared`: `Loader`, `Remotes`, `Animation/` (see below), `Config/` (`Balance`, `Weapons`, `Enemies`, `MapLayout`, `WorldTypes`, `Worlds/W01_SunnyMeadows` + `W02_RedwoodForest` / `W03_CrystalCaverns`, `Index`, `Leveling`, `Quests`, `Shop`, `Gates`).
- `ServerScriptService.Server.Services`: `PlayerDataService` (saves everything a player earns; first in `SERVICE_ORDER`), `ShopService` (the Robux shop, multipliers; last), `WorldEnemyService` (enemy registry, spawn, respawn), `MeleeService` (weapons + enemy AI), `AvatarService` (dresses R6 avatars), `IndexService` (the Index: kills, discoveries, weapon drops, the one saved DataStore), `CoinService` / `ExpService` (coins and EXP from kills), `QuestService` (every world's questline, run side by side: Dale, Rowan, Pip; content in `Config/Quests`), `GateService` (buying world gates; `Config/Gates`), `AdminService` (the admin panel; last in `SERVICE_ORDER`).
- `StarterPlayer.StarterPlayerScripts.Client`: `Util/` (`DamagePopup`, `HudFly`, `FontDrop`), `Controllers/` (`ChatTagController`, `PromptController`, `WorldEnemyController`, `EnemyAnimator`, `SprintController`, `PlayerAnimator`, `WeaponController`, `InteractionController`, `NpcIdleController`, `LootController`, `SpinnerController`, `FlowController`, `QuestController`, `GuideController`), `UI/` (`PanelWindow`, `RobuxShopUI`, `InventoryUI`, `PlayerCardUI`, `HotbarUI`, `ShopUI`, `IndexUI`, `IndexPopup`, `CoinsUI`, `DialogueUI`, `QuestTrackerUI`, `GateUI`, `WorldBannerUI`, `AdminUI`).
- Players start with the **Dagger** (`Weapons.default`, marked `starter = true`): always owned and can't be sold. Fists were removed.
- **One weapon in the hotbar.** `MeleeService` keeps a *selected* weapon (the player's `SelectedWeapon` attribute) that is either in hand or put away (`Holstered`). Every spawn starts with it put away. Clicking the hotbar's only slot (`WeaponHud/Hotbar/Slot1`, key 1) toggles it (`Remotes.HolsterWeapon`). Picking a weapon in the Inventory selects it and puts it in hand. The character's `Weapon` attribute is set only while the weapon is in hand. `WeaponController.current()` is the weapon in hand; `selected()` is the hotbar's. The hotbar is a frosted bubble-image slot that grows on hover, with no equipped highlight.

  The Inventory opens from `WeaponHud/InventoryButton`, on the left edge above `IndexButton` and `ShopButton`.
  - **Side buttons, style B "Puffy toy" (2026-10-10, user's pick on https://claude.ai/artifact/RgozkjSe1u9pmQNuzJXbAd):** glossy, inflated drawn icons with a dark outline, a soft shadow and a slight tilt. Backpack `95998562954903`, book with a star `117517869868002`, market stall `83448440638931` (source `art/hud_buttons_b.html` → `art/hud_buttons/`).
  - No circle: each `Content/Background` bubble is hidden.
  - `Content/Icon` is square, 1.4 × the button's width, at the top, shifted by its art's measured off-centre (`ArtOffsetX`).
  - `Content/Label` (Luckiest Guy, white, ink `2b1b3d` stroke 3.5, max 30) has its **centre on the drawing's bottom edge**, measured per PNG (the `LabelAt` attribute on the Icon: 0.904 / 0.891 / 0.898). It has a `LabelShadow` copy just below it, and HotbarUI runs `Util.FontDrop.watch` on all three buttons.

  Roblox's own Backpack CoreGui is disabled. **Weapon icons are drawn pictures (2026-10-09, user's request: the viewports didn't pop):** each def's `icon` in `Config/Weapons` is a cel-shaded render of the weapon's mesh with an ink outline and soft shadow (Blender `plants.blend` scene `Icons`, text block `icon_render` → `art/icons/weapons/raw/`, finished by `art/weapon_icons.py` → `art/icons/weapons/<Id>.png` + `sheet.png`). Inventory tiles show it in `ItemTile/Picture` (0.96 × 0.92, behind `ItemName` and the `Stat` pill); the hotbar in `Slot1/Content/Face/Picture` (1.3× the slot, so it pokes out). Without an `icon` both fall back to the `Icon` viewport (`showWeapon`, an outline-point perspective fit with `Fill` / `Aspect` attributes). The `Stat` pill is text only, "50 Dmg" (`DamageFormat` on `ItemTile`); the Damage card under the character keeps its sword. **The hotbar slot looks like the weapon's Inventory tile:** `Slot1/Content/Skin` takes the rarity image from the slot's `Skin_<Rarity>` attributes (copied from `ItemTile`); the old frosted `Background` bubble is hidden and the Face's fill/stroke off. The Hotbar sits at Y scale 0.955 (raised so the picture isn't cut off). A new weapon needs an icon rendered the same way.
- **All animation goes through `ReplicatedStorage.Shared.Animation`**, our own animation system; its root module's header maps every submodule. In short:
  - `Character.get(model)` gives one shared rig + `Animator` per character. Scripts `Play` clips on it at a `Priority` (Core < Idle < Movement < Hold < Action … < Override) instead of writing joints, so nothing fights. Additive clips layer on top.
  - Clip content lives in `Animation.Clips`: `Locomotion` (player idle/walk/sprint), `Weapons` (`HOLDS` / `SWINGS`), `Enemies` (walk, `MOVES`, flinch). Clips can carry markers (`Hit`, `Strike`, `TrailOn`…), and `Clip.fromKeyframeSequence` imports Animation Editor saves.
  - Enemies are `PartRig`s (part- or mesh-built). Only their Root is moved, and the limbs follow in one batched `BulkMoveTo`. Far or off-screen rigs update less often or not at all (`Animator.LOD`).
  - `Tween`, `Motion` (move/rotate/path/spin/bob), `Weld` (sockets; MeleeService welds weapons with `Weld.toSocket`), `Effects` (pooled bursts, shockwave, flash, trails), `CameraFX` (layered FOV zooms; it also has shake and kick, but **nothing may shake or kick the camera**: the user had every shake removed on 2026-10-09 as "a huge hassle").
  - **Every per-frame writer is an `Animation.Scheduler` system** (phases Joints / Render / Camera, ordered by priority). Never connect a new RunService handler that moves parts, joints or the camera: two connections to one event run in no guaranteed order. Profile with the `Profiling` attribute on the Scheduler module during a playtest, then read its `Stats` attribute.
- `PlayerAnimator` plays `Locomotion` on every character, and `WeaponController` plays holds, swings and the slash trail. Both expose `track(model)` / `untrack(model)` for display copies (the Inventory's character preview). `EnemyAnimator` plays enemy clips (walk, attack moves, flinch, mood faces). `SprintController` handles sprint speed (unlimited; no stamina since 2026-10-11), plus the `CameraFX` "Sprint" zoom.
- Weapon ownership is server-side and saved (`MeleeService`, the `weapons` section of PlayerDataService): players start with the starter weapon only and get the rest as **enemy drops**, published as the player's `OwnedWeapons` attribute (comma-separated ids). Only owned weapons can be equipped.
  - **Drops:** each enemy's `drops` list in `Config/Worlds/<world>` (placeholder rates) is rolled per entry on every kill by `IndexService`, which calls `MeleeService.grant`.
  - **Kill hook:** `WorldEnemyService.defeat(enemyId, killer)` credits the player whose weapon hit finished the enemy, and `onDefeated` listeners hear it (Index, coins, EXP, quests).
  - **Index:** state is published as the player attributes `IndexKills` (`"Chicken=3"`) and `IndexWeapons`. Each discovery fires `Remotes.IndexDiscovered { kind, id }` for the NEW popup. `Shared.Config.Index` holds the roster, drop and source lookups. `Remotes.SellItems` removes weapons; no coins are paid yet. The Inventory window (`StarterGui/Inventory`) lists owned weapons by damage, and has a filter dropdown (armour filters are empty for now), search, Equip Best and Sell Mode.
- Modules use the Loader `init(deps)` / `start()` pattern. A **new module must be added to the order list** in `ServerScriptService.Server` (`SERVICE_ORDER`) or the `Client` LocalScript (`UTIL_ORDER` / `CONTROLLER_ORDER` / `UI_ORDER`).
- New RemoteEvents are declared in `Shared.Remotes` (`EVENT_NAMES`).
- Style: `--!strict`, explanatory block comments at the top of each module and above non-obvious code, names that match the surrounding code.

## Game rules that are easy to break

- **Weapons are the only combat.** Hitting an enemy starts a real-time fight (`MeleeService`). The dice duel ("Challenge" prompt, `CombatService` / `CombatEngine`, `CombatUI`, `BattleScene` and its `BattleArena`, `BattleNumber`, the duel moves attack / heal / shield / nothing / hit, `Types`, `Balance.Dice` / `HandMultipliers` / `Player` / `Enemy`, enemy `attack` / `heal` / `shield` / `actions`, `EngagedBy`, `LogicTests`, `CombatSim`) was **scratched and deleted on 2026-10-08** at the user's request. Don't bring any of it back. Enemy max HP is just `hp` in `Config/Worlds` (the boss's 32 × 4 became 128).
- **Players are locked to R6** via `StarterPlayer.StarterCharacter` (an R6 rig) plus `AvatarService`, which re-applies each player's outfit. Keep both; the place is unpublished, so the Game Settings avatar option can't be used yet.
- Gear, talents, chests and leaderboards were removed on purpose. Don't reintroduce them unless asked.
- **Everything a player earns is saved (2026-10-09, user's request: "everything the player can obtain").** `PlayerDataService`: DataStore `PlayerData`, key `u_<UserId>`, one record `{ v = 1, [section] = value }`.
  - Each service registers its section in `init()` with `PlayerDataService.register(name, { load = fn(player, value), save = fn(player) -> value })`. Sections: `highestWorld` (own, the `HighestWorld` attribute, 1 until world gates exist; `unlockWorld(player, n)`), `weapons` (owned + selected), `coins`, `exp` (level follows), `quest` (step/state/progress), `shop` (passes, boost seconds left, starter pack, the last 50 receipt ids).
  - Loaders run in registration order (= `SERVICE_ORDER`), so coins/EXP are in place before the quest loads and never count as progress. A loader can run before the service's own PlayerAdded handler, so it must create state itself. **Savers read the published attributes** (or state kept a while after leaving), because PlayerRemoving handlers run in no set order.
  - Saved every 60 s, on leave, on shutdown, and by `saveNow()` for purchase receipts. A record that failed to load is never written over. Players get `DataLoaded` = true once applied.
  - DataStores only work once the place is published with Studio API access on; until then it warns once and progress lasts the session (as before). The Index still has its own store (`IndexService`).
- **Coins came back on 2026-10-07 (user's request); saved since 2026-10-09.** Kill coins × the player's `CoinBoost`.
  - Each kill gives a random amount from the enemy's `coins` range in `Config/Worlds`, via `CoinService`, published as the player's `Coins` attribute.
  - `Remotes.CoinsDropped` plays the spill: `LootController` flings 3–5 copies of `ReplicatedStorage/Assets/Effects/Coin`, which sit spinning for a second, then become `WeaponHud/Templates/FlyingCoin`s that fly to the counter (`Util.HudFly`).
  - `CoinsUI` counts the counter up over the `Coins` frame's `CountSeconds`, starting when the first coin lands.
  - The spill is announced before the balance changes, so the counter knows to wait.
- **EXP and levels (2026-10-07; saved since 2026-10-09):** kill EXP × `ExpBoost`.
  - Each kill adds the enemy's `exp` (`Config/Worlds`) to the player's `ExpTotal` attribute, via `ExpService`.
  - `Config/Leveling` turns the total into level, EXP into that level, and EXP needed. Players start at **level 1** (`Leveling.START`, user's request 2026-10-08; the `LevelBadge` placeholder reads 1). The placeholder curve is 100 to reach level 2, then +50 per level. `Level` is published too.
  - `Remotes.ExpDropped` spills 3–5 blue `Assets/Effects/ExpStar`s that fly to the `XP` bar as `FlyingStar`s.
  - `PlayerCardUI` counts the bar ("EXP", "x / y") and the `LevelBadge` up over a second.
- **No stamina (user, 2026-10-11):** sprinting is unlimited (`Balance.Sprint.speedMultiplier` only). The card's `Stamina` bar was deleted and `XP` moved up into its place.
- **Numbers read with commas everywhere (2026-10-11):** `Client.Util.Format` (`commas`, `ratio`) for coins, EXP, the level badge, health, enemy health bars, quest counts and reward chips, like the shop.
- **World banner (2026-10-11):** `Client.UI.WorldBannerUI` + hand-built `StarterGui/WorldBanner` (`Banner` CanvasGroup with `PopScale`, `Subtitle` "World 2", `Title` + `TitleShadow` = the world's `name`; `InSeconds` / `HoldSeconds` / `OutSeconds` / `PopFrom`). Shows on join and whenever the player walks into another world. A world's footprint is the X/Z box of its `Ground` parts (parts over 400 studs, World 1's Baseplate, ignored), smallest first.
- **Defeat burst (2026-10-11, user: kills were too quiet):** `WorldEnemyController.showDefeat`: `Poof` + new `DeathPop` stars (EffectPresets) + a `Shockwave` ring, sized by the body, and `ReplicatedStorage/Assets/Sounds/EnemyPop` (Creator Store "Cartoon Pop - Daily Sounds", `106984966606682`). Not for bodies already dead on join (`ready`).
- **Questlines, one per world (lines run side by side; each player has a step in every line).** A giver is a model tagged `QuestGiver` (plus `AmbientIdle`) whose `QuestLine` attribute names its line; adding a line = `lines.<Id>` + `Quests.order` + a giver. Full checklist: the `add-questline` skill.

  | Line | World | Giver | Levels | Step 8 item | Step 10 weapon |
  |---|---|---|---|---|---|
  | `DaleFarm` "Trouble on Dale's Farm" | 1 | Dale (`W01…/Npcs/Farmer`) | 5 / 8 | LuckyHorseshoe | WeathervaneSpear |
  | `RangerRedwoods` "Trouble in the Redwoods" | 2 | Ranger Rowan (`W02…/Npcs/Ranger`) | 12 / 15 | RangerBadge | LanternFlail |
  | `ExplorerCaverns` "Into the Crystal Caverns" (2026-10-17) | 3 | Explorer Pip (`W03…/Npcs/Explorer`, beside the boarded-up mine entrance at the end of the entry hall) | 20 / 23 | MinersLantern | DiamondPickaxe |

  - The level steps follow the armour sets: the first set's level + 1, then the second set's level (`Config/Armor`).
  - Each giver has its own `IdleStyle` in `NpcIdleController` (Farmer, Ranger, Explorer) and a portrait in `npc.portrait` (Pip `rbxassetid://111659781861627`).
- **Questline "Trouble on Dale's Farm" (2026-10-08, user's design; saved since 2026-10-09):**
  - Content is all in `Shared.Config.Quests`: 10 steps (kill 5 chickens, earn 75 coins, kill 10 chickens, 3 bulls, level 5, give 200 coins, 5 bulls, the boss, level 8, the boss 5 times), with rewards, Dale's lines (`offer` / `reminder` / `complete`), the Objective text and the tracker line. In lines `[...]` is the bold red objective; in `track` `{...}` is the red enemy or thing name (user: only the name red, the rest white).
  - The final reward's `weapon` is empty until the quest-only weapon is designed; once set, hand-in grants it through `MeleeService.grant`.
  - `QuestService` (server) publishes `QuestStep`, `QuestState` (Offer / Active / Ready / Done) and `QuestProgress`, and takes `Remotes.QuestAction` ("accept" / "turnIn") only within 16 studs of the giver. Kills come from `onDefeated`; "earn" counts rises of `Coins` after accepting; "level" / "give" re-read `Level` / `Coins` (a give step drops back to Active if coins are spent). Hand-in takes the coins for "give", moves on, then pays the reward.
  - The giver is a model tagged **`QuestGiver`** with `QuestLine = "DaleFarm"` (`Npcs/Farmer`); Rowan (`RangerRedwoods`) and Pip (`ExplorerCaverns`) work the same way. `Client.Controllers.QuestController` gives it a **Talk prompt on E** (it was briefly on F while the enemies' Challenge prompts competed for E). The prompt is drawn by us, not Roblox (Talk prompt **B "speech bubble"**, user's pick 2026-10-10): QuestController sets the prompt's `Style = Custom` and a `ShortName` attribute (Dale), and `Client.Controllers.PromptController` clones `ReplicatedStorage/Assets/UI/TalkPrompt` (or the template named by the prompt's `Template` attribute) on `PromptShown`. Names: `Content` (`PopScale`), `Shadow`, `Tail`, `Bubble/Label` (the gui's `TextFormat` "Talk to %s" with `ShortName` or `ObjectText`), `Key/Label` (keyboard key, gamepad button, or "Tap"), and `Hit` (a click/tap holds the prompt). `PopSeconds` sets the pop in/out. Both labels' boxes are centred (the bubble's in the body, clear of the E badge on the corner: x 0.15–0.85, y 0.17–0.83) with an empty `UIPadding`, and PromptController runs `Util.FontDrop.watch` on each clone (measured centred 2026-10-10). Any future custom prompt can reuse it. Talking hides `WeaponHud` and `QuestTracker`, freezes the player and hides their body, and eases the camera to Dale's face (a Scheduler Camera system, priority 40, re-asserting Scriptable), framed right of the card and swung 18° to his left so the pitchfork clears his face. Hand-in carries straight on into the next offer.
  - `Client.UI.DialogueUI` plays `StarterGui/Dialogue` (Dialogue B "Side card"): types each line at the gui's `CharsPerSecond` (60) with `MaxVisibleGraphemes`; click / E / Space / Enter finishes, then advances. Names: `Window` (`PopScale`, `Skin`, `Portrait/Photo`, `NpcName`, `QuestTag` ("Quest 1 of 10", plain outlined text like the name; no bubble, user's request), `Text`, `Tap`, `NextHint`, `Objective` (`Icon`, `Caption`, `Goal`; attributes `CoinIcon`, `LevelIcon`), `Reward` (`Caption`, and `Chips`: a wrapping UIListLayout row holding `Coins` "25 Coins", `Exp` "20 EXP", `Weapon` chips with `Amount` and `Icon`; a chip that doesn't fit flows onto a second line (user, 2026-10-11, for quests with more rewards); the Weapon chip shows the weapon's drawn icon), `Choices` (`Accept` "Accept Quest" / "Claim Reward" = the Inventory's green button, `Later`, each with `Label`)).
  - `Client.UI.QuestTrackerUI` fills `StarterGui/QuestTracker/Tracker` (**Tracker C "Target badge"**, user's switch 2026-10-08; right side, shown only while Active / Ready): `Tab/Label` "Dale's Farm · 1/10" / "Complete! · 1/10", `Badge` with `Portrait` (enemy portrait, coin, level icon, or Dale once done) and `Ring` (`Track`, plus `Right` / `Left` halves whose hard-edged `UIGradient`s are rotated: right 0–50%, left 50–100%), `Verb` (words before `{}` in `track`, upper-cased), `Target` (the red name), `Count` ("3 / 5", or `returnNote`). State colours are `Tab*` / `Rim*` / `Lip*` / `Fill*` / `Track*` attributes on `Tracker`.
  - **Attribute order matters (bug fixed 2026-10-08):** quests 3, 4, 7, 8 and 10 showed as done right after accepting. The client read the new `QuestStep` paired with the old step's `QuestProgress` / `Ready`, and the tracker's "caught up" latch locked it. Now `QuestService.publish` sends Progress, then State, then Step; `QuestTrackerUI` defers its render to read all three together; and a latch needs server Ready and clears on any step change or non-Active/Ready state. Test each step with the Studio-only `DevQuestStep_<lineId>` player attribute (a bare `DevQuestStep` means Dale's line; set it from the Server datamodel; set it to nil first if it already holds that number).
  - **Shown state:** the tracker publishes `QuestShownState` on the local player (client-only: "Active" until the counters catch up, then "Ready"). `GuideController` follows that, so the arrow no longer turns to Dale before the HUD shows the level or coins.
  - **Talking locks input:** `QuestController` sets the local `InputLocked` attribute and anchors the HumanoidRootPart as well as disabling controls. `WeaponController.swing`, `SprintController` and HotbarUI's key 1 check `InputLocked`. `Dialogue/Catcher` is a full-screen transparent button behind the card: a click anywhere advances, and it never reaches the world.
  - **Progress follows the HUD, not the server (user's report):** the server adds coins / EXP the moment an enemy dies, but the counters wait for the coins and stars to fly in. So "earn" / "give" steps show `CoinsUI.shown()` and "level" steps `PlayerCardUI.Exp.shownLevel()` (both have `onShown` signals), and a step only turns green once the counter has caught up. Kill steps update immediately.
  - **Guide arrow (user's request):** the tracker's round `Guide` button (left of the badge; `OnColor` / `OffColor` / `OnIconColor` / `OffIconColor` / `OnShadowColor` / `OffShadowColor` attributes, an `IconShadow` under the icon) toggles `Client.Controllers.GuideController`, on by default. Held down, it drops onto its `GuideLip` and darkens by `PressDarken` (0.18), and only flips on release. It points at Dale whenever a step is Ready, at the **nearest living enemy** of the target kind on an Active kill step, and nothing otherwise (earn / level / give-without-the-coins hide the button). The arrow is a clone of `ReplicatedStorage/Assets/Effects/GuideArrow` (invisible flat part, arrow `Decal` on Top; **a Top-face decal's top edge is the part's +Z**, so the code faces −Z away from the target), floating flat at **chest height** (`Height` 0.5 above the HumanoidRootPart; it used to sit on the raycast ground and climbed onto roofs) `Distance` studs ahead of the player, creeping `Slide` studs every `SlideSeconds`, hidden within `HideWithin` (9) studs. A black copy of the decal (`GuideArrowShadow`) lies on the ground straight below, found by a ray down from the arrow (`ShadowReach` 8, `ShadowTransparency` 0.55, fainter the higher it floats). A Render Scheduler system at priority 60, client-only, parented to `Workspace.Runtime`.
  - Designs: https://claude.ai/artifact/M6s1p4LLoAErQGcy347KVt. Skins are in `art/quest_ui.html` → `art/quest/` (see the `roblox-ui-icons` skill).
- **Temporary: `Balance.Melee.testDamageMultiplier = 10`.** It multiplies weapon damage in Studio only. Set it back to 1 when the user is done testing.
- **Quest rewards are shown (2026-10-11):** hand-in coins / EXP use `CoinService.spill` / `ExpService.spill` at a spot 4 studs from Dale toward the player, with `afterTalk`: `LootController` holds the counters, waits until `InputLocked` clears (the conversation ends), then flings the coins / stars there and flies them to the HUD. A reward weapon also gets the Index NEW popup (`IndexService.showWeapon`, which announces even if already found).
- **Temporary: `Balance.Melee.testStartWeapons = { "CornCob" }`** (2026-10-09, user's request). In Studio only, every player owns these from spawn and the first starts selected in the hotbar (`MeleeService.stateOf`). Empty it (`{}`) when the user is done testing.
- **The Index has its own save** (user's request 2026-10-07): `IndexService` uses DataStore `Index`, key `u_<UserId>`, and merges on every save. Weapon drop chances there are multiplied by the killer's `LuckBoost`, capped at 100% (luck applies to every weapon, the Corn Cob too: a 20% drop at 5× luck is certain).

- **Robux shop (2026-10-09, user's list; canvas https://claude.ai/artifact/QcrPKYYkNLD9YSVGkqzF7N, picks: HUD button B "market stall", window Layout B "storefront").**
  - Content in `Shared.Config.Shop`: `Bundles` Handful 250 / Pouch 750 / Sack 2,000 / Chest 5,000 / Vault 12,500 coins (× `WorldScale` {1, 4, 16} for the player's highest unlocked world; repeatable), `Passes` VIP (1.25× luck, coins, EXP + `[VIP]` chat tag), 2× Luck, 1.5× Luck, 1.5× Coins, 1.5× EXP, `Boosts` (2× Luck / Coins / EXP for 15 min, stackable time, the clock runs only in game), `StarterPack` (once: 500 coins + 30 min 2× Luck, `weapon` empty for now). Prices are placeholders the user can change; keep them equal to the website's.
  - **Every `productId` / `passId` is 0 until the place is published and the items are created on the Roblox website.** With id 0, Studio grants a Buy press at once (a test purchase) and live servers refuse it.
  - `ShopService`: `Remotes.ShopBuy { kind, id }` → Roblox prompt (real id) or Studio test grant; `ProcessReceipt` grants once per PurchaseId and saves before confirming; passes from `UserOwnsGamePassAsync` + `PromptGamePassPurchaseFinished`, saved too. **All multipliers multiply together** (user's call): publishes `LuckBoost`, `CoinBoost`, `ExpBoost`, `OwnedPasses`, `VIP`, `Boost_<id>` (seconds left), `StarterPackBought`. Quest rewards and bought coins are never multiplied.
  - `Client.Controllers.ChatTagController` adds the gold Luckiest Guy `[VIP]` prefix through `TextChatService.OnIncomingMessage`. The user switched `ChatVersion` to TextChatService (scripts can't change it).
  - **Chat restyled in the game's look (2026-10-10):** TextChatService's `ChatWindowConfiguration` / `ChatInputBarConfiguration` use FredokaOne 18, white text with a dark (1b1726) stroke, on teal (0a5464). `BubbleChatConfiguration` is FredokaOne ink on cream (fff8ec). `ChannelTabsConfiguration` is LuckiestGuy with yellow selected tabs.
  - UI v2 (2026-10-10, user: everything must "pop" and look buyable, be scrollable, tiles a touch larger): `StarterGui/RobuxShop` (`Panel` = "RobuxShop"), `Window` (aspect 1100/712, `PopScale`, `Skin` = `shop_window`), fixed header: `Title` centred in the band (box y 23–69 because Luckiest Guy draws high), `Balance/Amount`, and `Close` (an ImageButton, drawn `btn_close2` `135369290207222`, 44 × 47 units centred on the band's middle, with a `PressScale`), and a **scrolling `Content`** (window units x 18, y 80, 1068 × 606; canvas 1068 × 1332 units, every child placed as a fraction of the canvas, so it scales with the screen). In it, top to bottom:
    - `VIP` (crown, three `Perk` chips, `TagChip` + `TagNote`, "Best perks" badge) and `Starter` (gift, "One time!" badge, `Desc`).
    - Section bars `PassesHeader` / `BoostsHeader` / `CoinsHeader`: teal gradient and `Title` only (the user removed their icons and descriptions on 2026-10-10). The coins bar keeps `WorldNote` with `Format` and a `Label`.
    - Pass cards `Luck2` (gold clover on a gold card) / `Luck15` (green clover on a green card; the user rejected the horseshoe and wants the luck tiers as different-coloured clovers) / `Coins15` (coin stack, teal card) / `Exp15` (blue), 246 × 310: `Rays`, `Glow`, `Icon`, `Badge` ("2×"), `Name`, `Desc`, `Buy`.
    - Boost cards `BoostLuck` / `BoostCoins` / `BoostExp` (potions), 334 × 210, with `Timer` (`IdleText`, `ActiveFormat` m:ss, `ActiveHourFormat` h:mm:ss once stacked boosts pass an hour, `ActiveColor`, `IdleColor`).
    - Bundle cards `Handful`…`Vault`, 197 × 320, on silver / green / blue / purple / orange cards, with `Amount`, `Unit`, `Bonus` (`Format` "+%d%% extra": coins per Robux compared with the smallest bundle, computed from Config/Shop) and the `Ribbon` on Sack / Vault.
    - Every item card, its `Buy` and `Close` are **anchored at (0.5, 0.5)**, because a UIScale grows from the anchor point (with (0, 0) the hovered cards grew from the top left and overlapped).
    - Every item: `ShopKind` / `ShopId`, a `HoverScale` UIScale, and `Buy`: a 9-slice `Skin` (`btn_buy`), a `PressScale`, and a `Price` frame whose UIListLayout centres the built-in Robux icon (`Robux`, `rbxasset://textures/ui/common/robux.png`, RelativeYY 0.72) and the `Label` together. The label has AutomaticSize X and a TextSize the code sets to the button height × `TextScale` (0.46). `Price` covers only the green face: `FaceTop` 4 / `FaceBottom` 12 px attributes on `Buy` (the 9-slice rim and lip are fixed pixels), pulled left by TextSize × 0.1 for Luckiest Guy's side bearing, only while the Robux icon shows ("Owned" alone is centred). Measured within 1 px on 2026-10-10 (see the `roblox-ui-text-centering` skill). Attributes `SkinBuy`, `SkinOwned`, `OwnedText`, `PriceFormat` "%d".
    - **Every Luckiest Guy label on a card is centred by `Client.Util.FontDrop`** (2026-10-10, user: "make sure it is all centered"): each has an empty `UIPadding`, and `FontDrop.watch(panel)` keeps it at ±0.14 × `TextBounds.Y`, because Luckiest Guy draws its letters that far above the middle of its box. Pill labels (`Badge`, `Bonus`, `Ribbon`, `TagChip`, `Perk*`) have boxes exactly centred in their pill. Don't add position nudges. The `Coins15`, `Pouch` and `Handful` `Icon`s are shifted left by their art's measured off-centre (`ArtOffsetX`). The header and section-bar titles are not yet converted.
    - Item cards have ZIndex 3, above the section bars (2), so the ribbons on their top edges show.
  - `Client.UI.RobuxShopUI` fills prices, owned states (hides the Robux icon), amounts, bonuses, timers and the balance. While the shop is open it turns every `Rays` image, grows a hovered card to 1.04 and dips a pressed Buy button.
  - Item art v2: `art/shop_items.html` → `art/shop_items/` (`sheet.png` to review). Bundles handful `77927769862389`, pouch `73247288759025`, sack (v4: open mouth with the coins inside, rope tie under the lip) `80043831456467`, chest `113481215581201`, vault (v4: a 3/4 steel safe, door swung open, gold bars on a shelf, coins tumbling out) `93004610170922`; passes green clover `115510327791385`, gold clover `100827510966282`, coin stack (v3) `122054027414289`, exp `140267519217471`; crown `78924645529806`, gift `106906240083318`; potions luck (v4, a white clover straight on the liquid like the other potions) `86470387882010`, coins `71275351764138`, exp `119844928896095`. Vivid 9-slice cards `vcard_*` (SliceCenter 50,50,350,196, SliceScale 0.45): green `88140848213979`, teal `122869014777579`, gold `96684365943066`, blue `93074261607577`, purple `122430238712786`, orange `109336854507139`, silver `110346667127974`, pink `112397188026859`, vip `127795968616121`; `btn_buy` `90256382669157` (SliceCenter 44,40,356,88), `btn_owned2` `120742026874749`. The window skin is still `art/robux_shop.html`'s `shop_window` `119697451231129`.

- **Admin panel (2026-10-11, user's request; layout A "Tabbed console" on https://claude.ai/artifact/VGyCNhGop9tZDV5LnqQvZB):**
  - Who: `Config/Admin` (`userIds`, the place owner once published, anyone in a Studio playtest). `AdminService` publishes `IsAdmin` and answers the `Remotes.AdminAction` RemoteFunction (`{ action, ... } -> ok, message`), re-checking admin on every call: `coins` / `exp` { amount } (negative takes, never below 0), `level` { level }, `levelUp`, `give` / `remove` { weapon } (never the starter; `MeleeService.revoke`), `respawn` { archetype } (`WorldEnemyService.respawnArchetype`: every copy back at full HP; a per-enemy `lives` counter stops a stale timed respawn).
  - UI: hand-built `StarterGui/AdminPanel` (`Panel` = "Admin", PanelWindow pops it), opened with **F2** (`Admin.toggleKey`), wired by `Client.UI.AdminUI`. Every word is `Admin.Text`; quick chips are `Admin.quick`. Names: `Window/Header/Title`, `Close`; `Tabs/Tab<Player|Weapons|Mobs>` (attribute `Tab`), `Hint`; `Content/PagePlayer` (`CoinsCard` / `ExpCard`: `Icon`, `Title`, `Have`, `Amount`, `Add`, `Take`, `Quick1`, `Quick2`; `LevelCard`: `Badge`, `Title`, `Amount`, `Set`, `LevelUp`), `PageWeapons/List` (UIGridLayout of `Templates/WeaponTile`: `Picture`, `WeaponName`, `Rarity`, `Action`), `PageMobs/List` (`Templates/WorldHeader` + `Templates/MobRow`: `Portrait`, `MobName`, `Note`, `Respawn`), `Status/Label`. Buttons are a TextButton + `Label` + `PressScale` with a UIGradient lip (white → 160 grey: a UIGradient multiplies the face colour). Gui attributes `TabSelected` / `TabIdle`, `StatusOk` / `StatusError` / `StatusSeconds`; tile attributes `Skin_<Rarity>`, `<Give|Remove|Starter>Face` / `Dark`.
  - Aspect-sized grid cells and rows need a huge offset height to shrink from (`UDim2.new(0.315, 0, 0, 100000)`): an aspect constraint only shrinks, and a 0 height collapsed the tiles. Playtested end to end (F2, all three tabs, give, respawn, Close).

## UI is hand-built; code only wires it

**Everything scales; nothing is fixed in pixels (user's rule, 2026-10-11: the game ships on phones too).**
- Sizes and positions are scale only (no Offset), with `UIAspectRatioConstraint` / `SizeConstraint` keeping shapes. Content of varying length is laid out by layouts, never placed by hand: `UIListLayout` (with `Wraps` for chip rows), `UIGridLayout`, `UIFlexItem` (`Fill`) and `AutomaticSize`. An aspect-sized list item starts tall (`UDim2.new(x, 0, 0, 100000)`) so the constraint can shrink it, and a ScrollingFrame's `CanvasSize` follows its layout's `AbsoluteContentSize` in code.
- **`Client.Util.Responsive`** (first in `UTIL_ORDER`) scales every pixel-only value by screen height / 1080: `UIStroke.Thickness`, `UITextSizeConstraint` Max/Min, `ScrollBarThickness`, 9-slice `SliceScale`, the Offset part of `UICorner` / `UIPadding` / `UIListLayout.Padding` / `UIGridLayout.CellPadding`, and `BillboardGui.Size`. The authored value is kept in a `Base<Property>` attribute (clones carry it). Covers PlayerGui and BillboardGuis in Workspace; SurfaceGuis (world signs) are left alone. Code that sets one of these itself uses `Responsive.px(n)` / `Responsive.setStroke(stroke, px)` (InventoryUI rims, RobuxShopUI `FaceTop` / `FaceBottom`). Text is TextScaled (with a cap) or sized in code from a box's height.
- Code may still place things in pixels when they come from live measurements (HudFly paths, canvas sizes, IndexUI's slip shift).
- **Quest card (Dialogue) is a bottom-up stack (user, 2026-10-11):** `Window/Body` (UIListLayout, bottom-aligned) holds `Text` (UIFlexItem Fill: takes what is left), `Objective`, `Reward` (AutomaticSize Y; `Caption` + `Chips`, a wrapping row whose chips keep their shape by aspect) and `Choices`. Buttons sit at the bottom, rewards right above them, the objective right above the rewards; an extra reward row pushes the objective up and the text box gives way.
- HUD side buttons are in `WeaponHud/SideButtons` (UIListLayout); code finds them with `FindFirstChild(name, true)`.
- Checked on a simulated 844 x 390 phone screen: proportions hold. Everything is physically small on a phone (it scales with screen height); a phone-size boost is a design decision still open.


The user wants every UI designed by hand in Studio, not generated by code. **Never build UI from scratch in a script** (no `Instance.new("Frame")` trees). Code may only show and hide, fill in live values, and clone hand-built templates for lists that come from data.

- Screens are ScreenGuis in `StarterGui`: `WeaponsShop`, `CraftingShop`, `Inventory`, `Index`, `RobuxShop` (each has a `Panel` attribute; `PanelWindow` shows one at a time and wires any button named `Close`), `WeaponHud`, `IndexPopup`, `Dialogue` (NPC talk, pops itself via its own `PopScale`), `QuestTracker`. All have `ResetOnSpawn` off.
- **Panels pop open and shut:** each panel's `Window` has a `UIScale` named `PopScale`. `PanelWindow` grows it from 0 with an overshoot over the panel's `OpenSeconds`, and shrinks it to 0 over `CloseSeconds` before turning the panel off. A new panel needs a centre-anchored `Window` with its own `PopScale`.
- In-world templates are in `ReplicatedStorage.Assets.UI`: `EnemyHealthBar`, `DamagePopup`. List templates live in a `Templates` folder inside their ScreenGui (`Inventory/Templates/WeaponCard`) and are kept `Visible = false`.
- Styling that changes with state (equipped/locked/disabled colours, end-screen wording, popup colours) lives in **attributes on the template**, so the user can restyle without code.
- Code finds pieces **by name**, so keep names stable when editing, and tell the user which names the code depends on.
- Sizes are in scale, with `UIAspectRatioConstraint` / `SizeConstraint = RelativeYY` and `UITextSizeConstraint` on text. That way the editor preview matches the game on any screen.
- **Index** (`StarterGui/Index`, `Panel` = "Index", layout C "Open book") is wired by `Client.UI.IndexUI`.
  - The book `Window` holds `LeftPage` (`Title`, `Progress`, `AllButton`, `Worlds`), `RightPage` (`Heading`, `Grid`, `Empty`), `Close`, `Ribbon`, and `DropSlip` (`Portrait`, `EnemyName`, `Kills`, `Rows` (a ScrollingFrame since 2026-10-11; IndexUI sets its CanvasSize from the UIListLayout's AbsoluteContentSize, because AutomaticCanvasSize ignores aspect-ratio rows), `NoDrops`) to the left of the book.
  - `Templates`:
    - `WorldCard`: the world's `profile` image, with `Rim`, `WorldName` and `Count`.
    - `LockedWorld`: used when a world has no enemies yet.
    - `EnemyCard`: skins, colours, ??? wording and `Tilt` are attributes.
    - `DropRow`: `Tile` with an `Icon` viewport, and `Skin_<Rarity>` attributes.
  - Silhouettes are `ImageColor3` tinted to `SilhouetteColor`.
  - The HUD button is `WeaponHud/IndexButton`.
- **NEW popups** (`StarterGui/IndexPopup/Popup`, ray-burst style) are played by `Client.UI.IndexPopup` from `Remotes.IndexDiscovered`, one at a time. Enemies use the `*Enemy` attributes (teal). **Weapon popups scale with rarity** (user's request 2026-10-09: "all of the pop up colours being green is lame"): every `<Name>_<Rarity>` attribute on `Popup` sets that tier's look: `Banner`, `Rays` (image, "" = none), `RaysColor`, `RaysTransparency`, `RaysSpin`, `SparklesSpin` / `SparklesColor`, `GlowColor`, `GlowPulse`, `NameStroke`, `ChanceColor`, `PopFrom` (>1 = slams down from that size), `PopSeconds`, `ShowSeconds`, `Flash` / `FlashColor`, `Dim`, `Rainbow`, `NewText`. Common: plain grey, no rays. Uncommon / Rare: green / blue rays. Epic: purple, sparkles, a breathing glow, a faint flash. Legendary: gold banner with shine stripes, sparkles, a gold flash and a light dim. Secret: slams in at 2.6× over a dimmed screen with a white flash, rainbow rays and hue-cycling glow, sparkles and name outline, and the tag reads "SECRET!". Hand-built pieces: `Popup/Sparkles`, `Popup/Picture` (the weapon's drawn icon; `Icon` viewport is the fallback), and the full-screen `IndexPopup/Dim` and `Flash` frames. Art: `art/rarity_popup.html` → `art/popup/` (banners common `91383673106322`, rare `76928168410683`, epic `89709582915826`, legendary `116001337083129`, secret `128195849513219`; uncommon keeps the old green `89942307214175`; rainbow rays `126242731276012`; sparkles `78047475344560`). The Weathervane Spear and Pumpkin King's Mace (2026-10-11) are the first Legendaries. `Templates/Chip` holds the drop chances.
- Index portraits (`portrait` on enemy defs) and world pictures (`profile` on world defs) are uploaded images from `art/index/`. A new enemy needs a portrait rendered the same way: turned slightly right, seen slightly from above, on a green screen and chroma-keyed.
- Shop stall items are hand-placed cards with `ItemId` / `Price` attributes. Buying is disabled until coins exist. The Weapons shop (`WeaponsShop/Window/List/Item_<id>` rows) is wired by `Client.UI.ShopUI`: it fills each `Art/Icon` viewport and `Coins/Amount`, and styles each `Buy` button from its `SkinBuy` / `SkinLocked` / `SkinOwned` attributes.
- Stall rings are hand-built parts (`Merchants/<Stall>/ShopRing`) tagged `Interactable`, with a `Station` attribute and a SurfaceGui holding `Idle` and `Inside` looks.
- Studio's `screen_capture` may not show BillboardGuis (enemy bars, damage numbers), and in a playtest it doesn't always follow a scripted camera. Verify those with property checks.

## Map and assets

- Map contract is in `Config/MapLayout`: `Workspace.Worlds.<W##_Name>/` with `Ground`, `Structures`, `Decorations`, `Spawns/EnemySpawns`, `Spawns/BossSpawns`, `Enemies`, `Bosses`, `Chests`, `Ambience`.
- Enemy templates: `ServerStorage.Assets.Enemies` / `.Bosses`. Weapon models: `ReplicatedStorage.Assets.Weapons`.
- Visual style: blocky, flat colours, mostly `SmoothPlastic`. Forward is **-Z** for every model.
- **Parts or meshes (agreed 2026-10-07):**
  - **Studio parts** for the map's base (ground, paths, hedges, mounds, waterfall, gates), building shells, and anything players stand on.
  - **Blender meshes** for decorations, props, building dressing, weapons, enemy pieces (one mesh per moving piece, still rigged with PartRig) and pickups.
  - Meshes stay low-poly and flat-shaded, with one MeshPart per colour and no textures, coloured in Studio.
  - The user imports each FBX from `art/meshes/` with File → Import 3D; I do the rest (see the `blender-modeling` skill).
  - First meshes: `Assets/Effects/Coin` and `ExpStar`, each with a star symbol.
  - World 1's flowers and grass tufts are mesh clusters cloned from `ServerStorage.Assets.Decorations`:
    - `Tulips_N` / `Daisies_N`, where N is 1/3/5/7 flowers, coloured per cluster;
    - `GrassTuft_A/B/C`.

    World 1 is down to 4,638 parts.
  - Bushes are mesh too, also cloned from `Assets.Decorations`: `Bush_<Plain|Flowering|Berry|Apple>_<A|B|C>`, 1–3 MeshParts each.
    - **Apple bushes** are new (user's request): 12 of the plain bushes nearest the farm and apple trees became apple bushes.
    - World 1 is now 4,217 parts.
  - Trees are mesh too: `Assets.Decorations/Tree_<Pine|Oak|Birch|Apple|Blossom>_<A|B>`, 2–3 MeshParts each.
    - The `Trunk` keeps collision (`CanCollide`, Hull fidelity); leaves, apples and petals are walk-through.
    - World 1 is now 3,865 parts (it was 8,213 before any optimisation).
  - Rocks are mesh too: `Assets.Decorations/Rock_<Boulder|Mossy>_<A|B>` and `Rock_<Cliff|Standing|Pebbles>_A`, 2–3 MeshParts each.
    - Every stone has bevelled edges and cut corners.
    - Rock pieces are solid; moss and pebbles are walk-through.
    - World 1 is now 3,820 parts.
  - Fallen logs are mesh too: `Assets.Decorations/Log_<A|B>`, 5 MeshParts each (`Bark`, `Ends`, `Moss`, `Caps`, `Stalks`, where `Stalks` includes the cap spots).
    - Log A has 2 mushrooms and log B has 3. Only `Bark` is solid.
    - World 1 is now 3,779 parts.
  - Ledge fences are mesh too: `Assets.Decorations/Fence_A` (`Posts`, `Rails`; solid, Box collision).
    - Each keeps the old fence's exact pivot, with its diagonal brace turned toward the nearest path.
    - World 1 is now 3,757 parts.
  - The farm props (`Decorations/Farm/<HayYard|BarnYard|CottageYard|CropField>`) are one MeshPart per colour per area, placed directly in each area model. The `Soil` rows in the crop field stay parts.
    - The front crop row is **carrots** (user's request).
    - Solid pieces use `PreciseConvexDecomposition`, because one mesh holds several props: hay, barrels, crates, trough, scarecrow pole and shirt, field fence. Crops, straw, hat and bands are walk-through.
    - World 1 is now 3,643 parts.
  - Pond plants are mesh too: `Assets.Decorations/Reeds_<A|B|C>` (`Stems`, `Heads`) and `LilyPad_A` (plain `Pad`) / `LilyPad_B` (`Pad`, `Bloom`, `Centre`; a water lily). All walk-through.
    - **Every World 1 decoration group is now mesh.** World 1 is at 3,510 parts, down from 8,213.
    -
  - **Building details (2026-10-07):** each is rebuilt in place, one mesh per colour, inside the building model.
    - The flower beds are in `Fountain/Details` and `House/Details`: petal meshes per colour, plus `Centres`, `Stems`, `Leaves`, and the fountain's `Coins`.
    - The windmill sails are the `Windmill/Sails` model (`Wood`, `Cloth`, `Axle`), tagged **`Spinner`**. It sits 1.5 studs above the old hub, so the hub clears the top window.
    - The bed stems run up into each bloom (fixed 2026-10-07; the old part stems stopped short).
    - The cottage window boxes are meshes directly in `Cottage`: `Box`, `Soil`, `Leaves`, `Red`/`Yellow`/`Pink` petals and yellow `Centres` (user's request).
    - The silo ladder (`Farmstead/Silo/Ladder`) and the barn door X trim (`Farmstead/Barn/Trim`) are meshes too.
    - World 1 is now 2,722 parts.
  - **Lamp posts (2026-10-07)** are mesh too: `Assets.Decorations/Lamp_A` (`Base`, `Wood`, `Iron`, Neon `Glass` holding the `PointLight`), cloned into `Ambience/Lamps` at each old pivot. The lantern hangs 2.1 studs out along the pivot's +Z.
    - Only `Wood` is solid (`PreciseConvexDecomposition`).
    - World 1 is now 2,618 parts.
- **Lighting (first pass 2026-10-07):** Roblox removed `Lighting.Technology`. It is now `LightingStyle` (Soft, kept for the cartoon look) plus `PrioritizeLightingQuality`, and scripts can set both.
  - Sun and ambient: `ClockTime` 14.4, `Brightness` 2.4, `ExposureCompensation` −0.25, a warm `ColorShift_Top`, a blue-grey `OutdoorAmbient` for tinted shade, and `EnvironmentDiffuseScale` 0.45.
  - Lighting children: `Atmosphere` (density 0.3, light haze), `Bloom` (threshold 1.6, so mostly Neon glows), `ColorCorrection` (+saturation, +contrast) and faint `SunRays`. There's also a `Sky` and `Terrain.Clouds`.
  - Later clock times put the plaza in the cliff's shadow.
  - The Lighting settings apply to every world; per-world presets will be needed for W02/W03.
- **Ambient sound (2026-10-07):** no code; looping Sounds with `Playing = true` start for every player on join. They live in `W01_SunnyMeadows/Ambience/Sounds`:
  - Global beds, as Sounds directly in the folder: `Birds` (ProSoundEffects "Birds Park 1") and `Music` (APM "Polska från Flackarp (b)", a rustic violin folk tune).
  - Positional water, as Sounds inside invisible anchor parts: `Stream` at the stream steps into the pond, and `Fountain`.
  - Volumes: each Sound uses a `SoundService` SoundGroup, `Ambience` (0.7) or `Music` (0.4). Balance the mix there.
  - Alternatives to audition are in `ServerStorage.AudioCandidates_2026-10-07`. To swap one in, copy its `SoundId`.
  - A third positional sound, `Waterfall`, sits at the falls.
  - The blue wall at the far end is `Shared.Gates.World2Gate.Barrier`, not water.
- **World 2 gate, style B "Ranger's Lodge Gate" (2026-10-10, user's pick on https://claude.ai/artifact/72mLsePFyuCMFgXfafDYid; World 2 is a forest).** The model is `Workspace.Shared.Gates.World2Gate`, between the rim cliffs at z −287. The user approved it, and the old stone gate's backup was deleted on 2026-10-10.
  - **Parts:** `Post_L` / `Post_R` (log cylinders d 7, 2 studs into the cliffs, tops above the beam at y 39) with `PostEnd_*` discs. `Barrier` is the green see-through vine curtain (24.4 wide, from the ground to local 29.6, so its top runs up into the arch beam everywhere; user's request). `SignBoard` is invisible and carries the sign; its bottom is 7 above the ground, so players walk under it. `Rope_L/R` hang it from the beam.
  - **Blender details** (`gate_build` text block, collection `Gate`, `art/meshes/gate_world2.fbx` + `gate_world2_offsets.json`, placed at the gate pivot (0, 8, −287) × offset): `Beam` (curved, carved `Carving` dashes), `Leaves` / `LeavesLight` garland, `Flowers` / `FlowerCentres`, `Vines` (bands round the posts), `Bark` grooves, `EndRings`, `LanternFrame` / Neon `LanternGlass`, and `CurtainVines` / `CurtainLeaves`, which open with the curtain. Placed 2026-10-10: `Beam` is solid (Hull), the rest walk-through; `LanternGlass` is Neon with a PointLight in the middle of each lantern's glass (`Light` attachments). The lanterns hang at x ±8.1, the widest gap between the curtain vines (0.29 clear of the nearest leaf). Each is one connected piece (user's report, 2026-10-10): base, four posts running into the base and a rim, glass filling the frame, a roof on the rim, and a knob with the hanger rod going up into the beam. The sign's `Rope_L/R` run down behind the sign, past its drawn top edge. `Bushes` holds two `Assets.Decorations` bush clones at the posts' feet.
  - **Config/Gates** holds the gates (`World2`: world 2, level 10, 5,000 coins, placeholders) and **every word the sign shows** (`Gates.Text`, the user's rule: UI text lives in code). The title is the world's `name` in `Config/Worlds` (W02 renamed to the placeholder "The Whispering Woods").
  - **Sign:** `StarterGui/GateSign_World2`, a hand-built SurfaceGui (`GateId` = "World2", Back face, 30 px per stud = 360 × 340). Its pieces are `Banner/Label`, `Title`, `LevelRow` / `CoinsRow` (`Icon`, `Label`, `Check`, `Have`), and `Buy` (`Content`: `Label`, `Coin`, `Amount`; `PressScale`) with `BuyLip`. State colours are `FillTop_` / `FillBottom_` / `Lip_` / `Ink_<Met|Locked|Unlocked>` and `ShortColor` attributes on the gui. The `SignBoard` part is invisible, so only the rounded sign shows. The template's text is realistic placeholder ("World 2", "Buy" 5,000), and its UIPaddings hold the FontDrop correction, so the sign is centred in Edit mode too. Measured: the banner within 1 px, Buy within 2.
  - **Buying:** `Client.UI.GateUI` fills the sign from Level / Coins / HighestWorld and fires `Remotes.GateBuy { id }` when both requirements are met. `GateService` re-checks everything (within `BUY_RANGE` 40 of the board), spends the coins, calls `PlayerDataService.unlockWorld` and saves. For a player whose HighestWorld reaches the world, every gate part with the **`OpensWithGate`** attribute turns invisible and walk-through, locally: the curtain, and since 2026-10-11 the `SignBoard` and `Rope_L/R` too, and the sign gui switches off (user: the sign goes once bought). **Hover (2026-10-11):** while Buy can be pressed, hovering grows it and `BuyLip` (its `HoverScale`) by the gui's `HoverGrow` (1.05) and lightens the fill by `HoverLighten` (0.18); Buy and BuyLip are centre-anchored. Playtested: 6,000 → 1,000 coins, HighestWorld 2, curtain open, sign "Unlocked!".
- **World 2 ground (started 2026-10-10, user's spec; a forest).** It's in `Workspace.Worlds.W02_FrozenCaverns/Ground`, behind the gate: floor x −106..106, z −640..−290, top y 8 like World 1.
  - **Colours a step darker than World 1:** grass `3e7631` (World 1 `58a040`; darkened 2026-10-10 to sit between the old `4b8a37` and the hedges, user's request), path `bf9a68` (World 1 `d2b07c`). **No dirt in World 2** (user, 2026-10-10): the grass, path and ruins floor are solid from y 2 up to their tops at 8.
  - **One shared 4-stud grid** (cell i, j covers x −106+4i.., z −290−4j..) holds the path, the ruins floor and the grass. Each kind is merged into world-aligned rectangles with tops at 8, so **the path is flush with the grass** (user: not raised) and nothing overlaps. `Grass` is 115 greedy-merged blocks on a 1-stud grid: the open ground inside the hedges (flood-filled from the gate) plus the World 3 corridor, minus the path and the ruins.
  - `Paths` is **blocky like World 1** (75 blocks). The route's Catmull-Rom curves are rasterised with a 3-cell (12-stud) square brush:
    - from the gate to the fork at (−6, −394), a third of the way;
    - west and east lanes rejoining at (2, −500), two thirds;
    - then out to the left (−X) a little, and almost straight right into the ruins' **west** side at z −584, so the boss area sits east of the path's end (user's requests).
  - To reshape the path, change the control points and re-run the build.
  - `BossArena`: the **mossy ruins** floor, x 26..78, z −558..−610 (centre (52, 8, −584)). It is set in from the hedges so 18+ studs stay free on the east, north and south sides for trees and decorations (user's request). It's 169 one-cell flagstones in three greys (`7d7f78` / `6e706a` / `8a8b84`) with moss cells (`5f8a45` / `567f3f`), mossier at the edges.
  - **Ruins meshes** (`ruins_build` text block, collection `Ruins`, `art/meshes/ruins_w2.fbx` + `ruins_w2_offsets.json`, placed at `CFrame.new(52, 8, −584) * CFrame.Angles(0, −π/2, 0)` × offset, which turns the arch (built facing local +Z) to face the path in the west; the model is `W02/Structures/Ruins`. Stone and StoneDark are solid (PreciseConvexDecomposition); moss and ivy are walk-through): `Stone` `9a9b93` and `StoneDark` `74766f` (masonry courses), `Moss` `5f8f44`, `Ivy` `2f7a34`, `IvyLeaves` `4a9a3e`. Built so far:
    - a broken entrance arch on the path side (+Z): a tall pillar and a broken one, with a snapped lintel;
    - a jagged back wall with an arched window gap;
    - crumbled west walls and an east stub;
    - columns: one standing, one broken, a stump and a toppled one;
    - rubble, moss caps with drips, floor moss and ivy.
  - **Forest decorations** (2026-10-11, user's request; designed in Blender, `forest_build` text block, collection `Forest`, `art/meshes/forest_w2.fbx` + `forest_w2_offsets.json`). The templates are in `ServerStorage.Assets.Decorations`, each pivoted at its foot or edge:
    - **Pines only** (user, 2026-10-11: not a fan of the square oaks, which were deleted): `Tree_Spruce_A` (32 tall), `_B` (35, slim, 9 tiers), `_C` (27, wide, 6 tiers), `_D` (31, tiers twisted 30° and slightly off-centre, darker needles `1f4426` / `29552c`). Tiers come in two greens; 215–265 faces each.
    - `Log_Big_A/B`: 22 / 16 long. They have a hollow end, moss with tongues down the sides and red mushrooms; A has a ringed cut end, B a torn-up root plate.
    - `Vines_Hedge_A/B`: 8 / 12-wide drapes hooked over a hedge's top edge, strands 6–20 long. Their stems `3d7a33` and leaves `6bb84a` are lighter than the trees' vines, so they show on the dark hedges.
    - Only `Trunk` (Hull) and log `Bark` (PreciseConvexDecomposition) are solid. Everything is SmoothPlastic.
    - **Kept light (user, 2026-10-11: "the face count is just way too high").** The oaks' side lumps (60% of their faces), their hanging vines and all bevels were cut, and the hedge vines are 4-sided with fewer segments. Faces per copy: oak 150 / 182, spruce 238 / 264, log 254 / 258, vines 416 / 572 (oaks were 1,416 / 1,650). Check `len(evaluated mesh.polygons)` per model before adding many copies.
  - **Hills** (`Ground/Hills`, 2026-10-11, user's request): six all-grass hills that step up **1 stud at a time to at most 6**, in `Step_<level>` layers. Each layer is one stud thick, greedy rectangles on a 2-stud grid (402 parts). Each level is 2.5% lighter, so the steps read. The terraces are about 6 studs deep, so trees can stand on every level: the first build with 2-stud rings only fitted trees on the tops. Shapes are wobbly squashed rings round each site; the bottom step stays 2+ studs from the path, ruins and gate approaches. **Hills run under the hedges** (fixed 2026-10-11, user's report): the height field covers grass cells *and* cells under `Rim` blocks, so a hill meets a hedge as ground rising against it. **Cell membership is inclusive** (`>= lo − ε`, `<= hi + ε`): a strict test missed every cell whose centre sat on the seam between two merged grass blocks, which cut 252 one-cell holes in rows through the hills ("cutoffs going through the hills"). The site list is now written out (it no longer depends on a random pick), and a check confirms 0 one-cell holes. 411 parts. One hill sits in the path loop. Sites: (−61,−523) H6, (−5,−443) H3, (−11,−617) H3, (−77,−361) H3, (79,−507) H6, (93,−375) H3.
  - **Placed** in `W02/Decorations`: `Trees` (85 pines, A–D in even turns, 19 standing on hill steps), `Logs` (7: 4 draped down hill steps, the rest on the meadow / a terrace), `Vines` (18), all by script.
    - **No tree may touch another tree** (user, 2026-10-11), nor a log, vine, hedge or the ruins. Clashes are found with `GetPartsInPart` on every piece, with **CanQuery switched on for every part, including each fresh clone's pieces** (the templates' needles have it off, and missing that once let new trees overlap). The trees with the most clashes are removed first, then the gaps are refilled under the same test. Verified 0 contacts.
    - **On hills:** a tree's pivot sits on the step under it, and its footprint (9 rays round the trunk, radius 2.6 × scale) must all hit one height. A hill step only counts as cutting into a tree if its top is above the tree's base (every trunk reaches 0.1 into its own ground).
    - A **draped log** is tilted to the height difference between its ends (≥ 2), then lowered in 0.1 steps until its bark touches the steps, and backed off one step.
    - Trees: spots nearest the hedges first, the four kinds in turn, random turn, scale 0.9–1.1, then 10 more spaced out on the open meadow.
    - A tree is rejected if its roots come within 1 stud of the path, ruins or gate approaches (keep-out boxes from 0.5 below to 2.5 above), or its canopy touches a hedge, the ruins or another tree's spacing.
    - A second pass added 50 trees with denser spacing (canopies may touch, centres ≥ 0.62 × the radii sum), trunks kept 4 studs from the path and ruins, and the gate approaches clear.
    - Logs go on open grass clear of trees. Vines go on hedge faces that face into the world and aren't covered by another hedge (pivot on the top edge, `CFrame.lookAt(edge, edge + outward)`).
  - `PathDetails/Trims`: the path's edging (221 strips, `86653e`), built with `ServerStorage.DevTools.PathTrims`.
  - `Rim`: **the user's own hedge layout**: they moved the hedges by hand to round the inside (dark green `2f5d2b`, one big block each). Their 34 hedges are kept as placed, and the map is **not boxed into a square**: the user objected to filling out to a rectangle, which gave the corners a stepped depth. Only real gaps get a block:
    - `CorridorWall_S` / `CorridorWall_N` close the old right-side gap round the World 3 corridor;
    - `FrontFill_E` (x 76..106, z −310..−290) closes an opening to World 1's side.
    - A flood fill on a 1-stud grid checked 0 leaks.
  - **World 3 gate at the back of the boss**, which is the **east** side, opposite where the path enters the ruins (user's correction). A 34-wide corridor through the right-hand hedges is **centred on the boss pad** (z −601..−567, centre −584) and runs out to x 138. `Shared.Gates.World3Gate` (a copy of the forest gate for now) is set back like World 1's: 3 studs in from the end, at `CFrame.new(135, 8, −584) * CFrame.Angles(0, −π/2, 0)`, facing the ruins. Its sign is `StarterGui/GateSign_World3`, and `Config/Gates` has `World3` (level 20, 25,000 coins, placeholders). The ruins' back-wall window frames it.
  - World 2 has no enemies or spawns yet.
- **Waterfall (2026-10-08, user's request):** the stream's top pool used to end at the cliff (`Hedges/OuterRim/RimBlock_R12`).
  - Now `Ground/River/Waterfall` (`Sheet`, moving `Dash`es and `Ripple`s, `Lip`, `Foam`, `TopChannel`, and `Spray` with a `Mist` emitter) falls the full height of the cliff.
  - It sits in a 12-wide, 6-deep notch cut into R12 at z −150..−138, now 10 parts instead of 2. The notch is centred on the upper stream's open water (z −144); the user spotted the first build 2 studs off.
  - A channel along the top ends 6 studs before the rim's back edge.
  - The upper `River/Channel/Water` was lengthened to reach the notch.
- **River restyle (2026-10-08, user's request: match the waterfall):** the extra pieces are in `Ground/River/Details`.
  - `Cascades`: each 1-stud stream step (x 50/54/58/62) gets a `Lip`, `Sheet` and two `Foam` slabs, plus a foam spill into the pond.
  - `Streaks`: flow lines, on the upper pool only. The 4-stud steps are too short for them and they crossed the foam.
  - `Deep`: 11 dark-blue boxes under the pond surface, made from the open water shrunk 3 studs from every bank, so the shallows stay light.
  - The stream's water parts are now 0.12 transparent (pond 0.25), so the stepped dirt bed no longer shows through.
  - World 1 is now 2,674 parts.
- **Flowing water:** `Client.Controllers.FlowController` slides anything tagged `Flow` from its placed position along `FlowDir` (default down) at `FlowSpeed`. Every `FlowRange` studs it loops, fading in and out over `FlowFade` of the run. `FlowOffset` staggers copies.
  - It's a single Render-phase Scheduler system (priority 25) that moves parts through `PartBatch`. It runs on the client only and skips parts more than 320 studs from the camera.
  - The waterfall has 9 falling `Dash`es (3 columns) and 6 `Ripple`s running along the top channel to the edge.
  - The stream `Streaks` drift 7 studs downstream (−X) and loop.
- **Enemies are Blender meshes (2026-10-08).**
  - **Chicken is done:** 13 MeshParts plus the invisible `Root`, from 23 parts.
    - Limbs: `Torso` (body, chest and tail fan), `Head`, `LeftArm` / `RightArm` (one-piece tapered wings), `LeftLeg` / `RightLeg` (shin and 4 toes).
    - Head pieces (`Follows = Head`): `Comb` (comb and wattle), `Beak`, `Eyes`, `Shine`, `BrowsCalm`, `BrowsAngry`.
    - Each limb keeps its old `Joint` pivot. The user asked for all-white feathers (no cream) and one-piece wings.
    - The 12 spawn markers were swapped in place.
  - **Mood brows (user's idea):** parts with a `Mood` attribute (`Calm` / `Angry`) show only in that mood (`EnemyAnimator`).
    - A body is Angry while `AiState == "Chase"` and Calm otherwise. The template keeps `BrowsAngry` hidden.
    - The part-built chicken's brows were slanted inner-end-up, which reads as worried, not angry.
  - **Portraits show the calm face (user, 2026-10-11; they feed the Index and the quest icons):** Chicken `rbxassetid://119866244895251`, Bull `105217136953827`, Scarecrow King `122472392610626` (the mesh King with his black face). Old angry ones: `art/index/portrait_<id>_angry_2026-10-08.png`.
  - **Bull is done (2026-10-08):** 23 MeshParts plus `Root`, from 30 parts.
    - Limbs: `Torso` (barrel body, rump step, neck), `Head`, and the ears as `LeftArm` / `RightArm`.
    - Legs: `LeftLeg` / `RightLeg` / `LeftBackLeg` / `RightBackLeg`, each with a cloven `*Hoof` that wraps the foot (no dewclaws, per the user).
    - Torso pieces: `Hump` (with the tail rooted in the rump's top), `Belly`, `TailTuft`.
    - Head pieces: `Snout`, `Forelock` (with the nostrils), `Horns` (curved, tapering), a round gold `NoseRing`.
    - Mood face: `EyesCalm` / `BrowsCalm` (dark eyes, flat brows) vs `EyesAngry` (red Neon) / `BrowsAngry`. It's calm while grazing and turns angry when hit (tested in a real chase).
    - The user kept the two browns.
    - Portrait: `rbxassetid://111758085550694` (old: `art/index/portrait_Bull_parts_2026-10-07.png`).
  - **Scarecrow King is done (2026-10-08):** 53 MeshParts plus `Root`, from 91 parts. `ArmStyle = Hanging` is kept.
    - **Head:** one-orange lobed `Head` (pumpkin), carved face as `FaceCalm` (dark) / `FaceAngry` (glowing Neon jack-o'-lantern) with `Mood` attributes, `Brows`, a stitched `Crack`, `Stem`.
    - **Hat:** one continuous curved witch-hat cone (`Hat`, 9 sections), `HatBand`, `HatPatch`.
    - **Hands:** both are closed fists the full size of the arm's end (`*Glove`), with flared `*GloveCuff` gauntlets.
    - **Straw:** pokes up out of the glove tops and the boots (`*WristStraw`, `*AnkleStraw`), plus the `Collar`.
    - **Pitchfork:** the player's Pitchfork weapon mesh scaled 1.44× (`Fork*`), without its grip `Wrap` / `Bind`.
    - **Legs:** the trousers end inside the boots.
    - Portrait: `rbxassetid://73438461076709` (old: `portrait_BossScarecrow_parts_2026-10-07.png`).
  - **Every World 1 enemy is now mesh.** World 1 is at 2,510 parts.
- **Plaza paving (2026-10-08, user's request):** the plaza is no longer plain grey.
  - The `Ground/Hub/HubFloor` rects are now the darker border stone (a48d6c). `Ground/Hub/Paving` holds the rest:
    - `Field`: the hub outline inset 2 studs, sandstone d6c5a2.
    - `FountainRing`: a stepped circle r 21.
    - `Walkway`s to the N/W/E exits and south to the spawn, each W/E/N walkway with a cream `WalkwayInlay` centre line.
    - 46 `Flagstone`s.
  - Layers sit 0.03 apart (tops 8.00 / 8.03 / 8.05 / 8.06 / 8.09), so nothing z-fights and there's no step to trip on.
  - **Spawn dais** (`Spawns/SpawnDais`): two stepped tiers (border stone, then cream) with a gold 8-point compass star.
    - `Spawns/PlayerSpawn` is still the SpawnLocation, now invisible and non-colliding, with its top at the dais top (8.85). Its decal was removed.
- **Path and arena details (2026-10-08, user's request):**
  - `Ground/PathDetails/Trims`: 96 skinny edging strips (0.35 wide, 0.12 proud, 9c7a4e) along every `Ground/Paths` edge that meets grass or a drop. None where a path meets another path, the plaza, a bridge, the arena or a ramp `Step` within 1.1 studs of height.
    - **Rebuilt 2026-10-10 with `ServerStorage.DevTools.PathTrims`** (a dev tool: `loadstring(module.Source)()`, then `.build(opts)`; the old strips are in `ServerStorage.TrimsBackup_2026-10-10`). The user's rules: a strip lies **entirely on its own path block** and **sits on its top** (0.12 tall, nothing below the path top), so it never pokes into the ground or shows in a cliff face. **It never intersects anything.** **Corners (the user's call):** a path's **outer** corners have the normal joined outline; the Z-side strip runs to the corner and the X-side strip stops against it. **Inner** corners, where the path bends round a corner of grass and two blocks' strips meet, keep a small gap where the strips touch only at their corners. Strips are cut around bridges, fences, flowers and stones (all parts are made queryable while scanning), and collinear strips are joined. **Bug fixed 2026-10-10:** the edge test's downward rays used to hit strips laid earlier in the run (and World 1's stepping stones), read them as "not path", and stretched strips half a stud into inner corners. New strips now wait in a holding folder outside the rays' reach, and the rays include only the ground folders, never `PathDetails`. Checked: 0 inner corners joined in both worlds. Checked: 0 overlaps and 0 corners off a path in both worlds.
    - The edges were found by sampling each path rect's sides every 0.5 studs and raycasting just inside and just outside.
  - `Ground/PathDetails/SteppingStones`: 136 darker tan stones (bf9a66 ± shade), about one per 45 sq studs, each fully on bare path.
  - `Ground/BossArena/Seal`: a boss seal in the King's colours under the boss spawn (0, −232).
    - `ArenaFloor` is now the dark rim (45464c); a `Field` (6e7076) is inset 2 studs.
    - Rings and spokes: purple `OuterRing`, 4 dark `Spoke` bars (8 spokes), orange `Stud`s where the spokes meet the ring, orange `InnerRing`.
    - Centre: an orange 8-point `Star` with a purple `StarCore` and gold `StarEye`, plus 17 dark `Flagstone`s outside the ring. Layers are 0.03 apart.
  - World 1 is now 2,904 parts.
- **Ambient particles (2026-10-08):** `Ambience/Particles`. All sprites are uploaded from `art/particles/`:
  - `Petals`: one invisible box emitter under each of the 15 blossom canopies. Pink teardrop sprite `rbxassetid://122818573202948`, drifting down and spinning.
  - `Butterflies`: 15 box emitters over every 12th flower patch. A 2×2 flipbook of wing-flap frames, `rbxassetid://127401329185094`. The sprite is white with ink outlines, so each emitter's `Color` tints it yellow, blue, orange, white or pink.
  - `PollenSource`: one large box over the valley, soft speck `rbxassetid://112717098998481`, rate 30, drifting on a light breeze.
  - Particles work in Edit mode too, with no code.
- **Roof contact (2026-10-08, user's report):** the barn's white corner `Trim`s, the cottage's corner `Timber`s and (before the wells became meshes) both wells' `Post`s ran from the top of the foundation (or their old bottom, for the wells) up into the roof's underside.
  - The top is found by raycasting up from each corner of the post and taking the highest roof hit.
  - The barn and cottage corner posts no longer overlap the foundation.
- **Crafting stall remodel (2026-10-08, user's request: "a touch sloppy"):** `Structures/Merchants/CraftingStation` is now 28 MeshParts built in Blender (`craft_build` text block, collection `Stalls`, `art/meshes/crafting_stall.fbx` + `crafting_stall_offsets.json`). They're placed at the stall's own pivot × offset, in the stall's local frame (front = +Z).
  - **Pieces:**
    - Base and frame: `Platform` / `PlatformRim` (octagon); `Wood` (posts, beams, knee braces, sign board, frame and posts).
    - Awning: `AwningGreen` / `AwningWhite` (stripes down the slope, chamfered valance tabs).
    - Counter: `CounterTop` / `CounterBody` (planks) / `CounterTrim`.
    - Furnace: `Furnace` (one U-shaped body with the hearth open to the front, shorter chimney), `FurnaceTrim`, `Soot`.
    - Anvil and logs: `Stump` / `StumpTop` / `Anvil` / `AnvilFace`; `Logs` / `LogEnds` (five logs, flats just touching).
    - Barrels: three in a ring, `Barrel` / `BarrelHoops`.
    - Shelf and goods: `Shelf`, plus `IronIngots`, `GoldIngots`, `Planks`, `Rope`, `Jars`, `JarLids`, `Bottles`, `Tools`.
  - **Kept:** `Crafter`, `ShopRing`, `Candle` / `Platter` / `Wick` (on the front barrel), `Details` (furnace fire and candle flame) and `SignFace` with its `SignText` SurfaceGui, resized to exactly fill the sign frame's opening (9.28 × 2.7, between the board face and the frame face).
  - The candle group (`Platter`, `Candle`, `Wick`, `Details/CandleFlame`) sits on the front barrel's lid (y 3.0). The `Embers` cover the whole hearth floor (1.65 × 1.42).
  - **Removed:** the old part/mesh pieces, including the two furnace knobs.
  - Solid pieces use `PreciseConvexDecomposition`; the awning, goods and trims are walk-through.
  - No bevels except the counter top and platform, about 1,250 faces. The stall is 59 parts.
- **Weapons stall remodel (2026-10-08):** `Structures/Merchants/WeaponStation` is now 23 MeshParts (`weapon_stall_build` text block, collection `Stalls`, `art/meshes/weapon_stall.fbx` + `weapon_stall_offsets.json`). It's placed the same way as the Crafting stall and shares its frame, awning (red `AwningRed`), counter, platform and sign code, so the two match.
  - **Props:**
    - `Rack` on the back wall with two shields (`ShieldRed` / `ShieldBlue`, steel rims, gold bosses) and a spear on two pegs. The round `Shafts` and a rounded leaf head end in one point (user's request).
    - `Chest` with `Iron` straps and a gold lock.
    - A training dummy: `Stump` / `StumpTop`, all-straw body, arms and head (`Straw`), and `Rope` bands, neck tie and stitched X eyes. Only the post is wood, hidden inside the body; no target (user's request).
    - `Barrel` / `BarrelInside` with three swords.
    - One sword lying on the counter.
  - **Shared meshes:** `Steel` (blades, spear head, shield rims), `Gold` (guards, pommels, bosses, lock), `Grips`.
  - **Kept:** `Weaponsmith`, `ShopRing`, and `SignFace` with its SurfaceGui, fitted to the frame opening like the Crafting sign.
  - **Removed:** the old pieces and `Details/Swords`.
  - About 1,120 faces, no bevels except the counter top and platform. The stall is 41 parts.
- **Shopkeeper NPCs (agreed 2026-10-08):** the bodies stay Studio parts (classic R6 shape, standard Roblox head and face decal, Humanoid), so they look like the players. Their gear becomes Blender meshes.
  - Each gear mesh carries a `Bone` attribute (`Torso` / `Head` / `LeftArm` / `RightArm`), and `NpcIdleController` carries it with no code changes.
  - **Crafter's gear is done:** 10 MeshParts in `CraftingStation/Crafter`, built in the Torso frame (`crafter_gear_build` text block, collection `NPCs`, `art/meshes/crafter_gear.fbx` + `crafter_gear_offsets.json`, placed at `Torso.CFrame * offset`).
    - Torso: `Apron` (bib, flared skirt, straps over the shoulders), `ApronPocket`, `ToolBelt` (with pouch and hammer loop), `PouchFlap`, `Brass` (buckle and stud), `HammerHandle`, `HammerHead`.
    - Head: `GoggleBand`, `GoggleRims`, `GoggleLenses`.
    - Playtested: zero drift against the torso and head while idling.
  - **Weaponsmith's gear is done (2026-10-08):** 9 MeshParts in `WeaponStation/Weaponsmith` (`smith_gear_build`, `art/meshes/smith_gear.fbx` + `smith_gear_offsets.json`).
    - Torso: `Breastplate` (flat front with chamfered corners and a centre ridge), `BackPlate`, `Gold` (neck and waist trims, rivets, square buckle, dagger guard, pommel and tip), `Belt`, `Straps` (side straps, dagger sheath and grip).
    - Arms: `PauldronL` / `PauldronR` (square stepped caps over a lame) with `PauldronTrimL` / `PauldronTrimR`.
    - The user asked for squarish, not rounded, armour.
    - Playtested: zero drift while the arm waved through 65°.
  - **Material:** every stall and shopkeeper mesh is `SmoothPlastic`. `Metal` adds a brushed texture that clashes with the flat style, so it was switched off on all 15 pieces.
- **House rebuilt in Studio parts (2026-10-08, user's request):** the Blender-mesh house (13 MeshParts with Box/Hull collision) had an object bug, so `Structures/House` is now 63 ordinary parts on the same footprint (walls x 16.5..31.5, z −97..−67, wall top 15.5, ridge 20).
  - **Shell (solid):** `Foundation` (stone, 0.4 wider), `Walls` (one block), two `Gable` WedgeParts forming the roof prism along Z, two `Roof` slabs on the slopes (1.05 eave and 0.9 gable overhang), `Chimney` / `ChimneyCap`, `Step`, `Canopy`.
  - **Dressing (walk-through):** `Ridge` cap, timber corner `Post`s and a top `Beam` band, and four shuttered windows on the long walls plus one small window in each gable (`WindowFrame` / `Window` / `Muntin` / `Sill` / `Shutter`, layered 0.04 apart outward from the wall).
  - **Door** on the west wall facing the path: `DoorFrame`, `Door`, `DoorPanel`, `DoorKnob`. A porch `Canopy` slopes down away from the wall on two 45° `Bracket`s.
  - The flower beds (`House/Details`) were kept. The old mesh house is in `ServerStorage.HouseBackup_2026-10-08` until the user approves.
- **Bridges rebuilt in Studio parts (2026-10-08, user's pick: style A arched wooden footbridge, wooden rails, no lamps):** `Structures/Bridges/CenterPathBridge` (0, −130, ground 8) and `RightPathBridge` (68, −142, ground 12), 44 parts each, same 24 × 14 footprint as the old 9-part slabs.
  - 16 `Plank`s (1.5 studs, alternating b07a45 / 9c6a3a, 0.6 thick) whose tops follow a parabola rising 1.4 at the middle and flush with the path at the ends; 4 `Post`s per side (1 × 1, 7a4e2a, planted below the deck) with lighter `Cap`s (c8955a); a `Rail` (0.5) and `MidRail` (0.35) per post gap at 2.9 / 1.5 above the deck, along the chord.
  - Walk-tested: a character crosses each in 1.5 s, rising 1.4 and back down without catching.
  - The user approved both; the old part bridges' backup was deleted the same day.
- **Fountain rework (2026-10-08, user's request: steps and fences too small):** `Structures/Fountain` is 12 Blender MeshParts built in world coordinates around (0, 0) (`fountain_build` text block, collection `Fountain`, `art/meshes/fountain.fbx` + `fountain_offsets.json`, placed at `CFrame.new(offset)`).
  - **Steps:** `Tier1` / `Tier2` / `Tier3`, three octagonal steps (radius 17.2 / 15.6 / 14.0, tops 8.65 / 9.30 / 9.95), flat sides facing N/E/S/W. Each is one convex solid with Hull collision, so it walks exactly like it looks (checked by raycast).
  - **Basin:** `Basin` (octagon ring r 7.5 / 6.7, to 11.75), `BasinLip`, dark `BasinFloor`, `Water` (main water to 11.25 plus the upper bowl's water, 0.2 transparent).
  - **Centre:** `Column` (column, hollow upper bowl, stem, spout head). `Gold` holds the bowl rim, a collar, the finial, four spout pipes and coins in the basin.
  - **Fence:** `FencePosts` / `FenceRails` (2.4 tall, capped posts) on the four diagonal edges only; the walkway sides are open (user's request). Also a `FloorInlay` ring. No planters (user removed them).
  - **Collision:** Basin, lip, column and fence use `PreciseConvexDecomposition`; water and gold are walk-through.
  - **Sprays:** the four old spray attachments (`Spout1-4` with their `WaterStream` emitters) sit on an invisible `Spouts` part, at the gold pipe tips (radius 1.31, y 17.08).
    - Each attachment's +Y (`EmissionDirection = Top`) points along its pipe, outward and 10° up, at speed 2.5–2.7, lifetime 0.6–0.66. The arc lands in the upper bowl (inner r 2.98).
    - The old 45°-down aim made the water drop beside the pipes (user's report).
  - Four `LilyPads` clones float in the basin. The old fountain (with its flower beds) is in `ServerStorage.FountainBackup_2026-10-08` until approved.
- **Wells are mesh (2026-10-08, user's request):** both `Structures/Wells/Well_East` / `Well_West` are clones of `ServerStorage.Assets.Decorations/Well_A` (11 MeshParts, `well_build` text block, collection `Wells`, `art/meshes/well.fbx` + `well_offsets.json`).
  - Each is placed at its old centre on the ground (y 8), turned so its winch runs along the old beam (`CFrame.Angles(0, yaw, 0)`, East 15°, West −20°).
  - **Pieces:** a hollow octagon `Stone` ring with raised stones, `Cap`, a dark `Shaft` lining, and `Water` 1.8 below the cap. `Wood`: posts on the cap reaching the roof, a winch log with a crank, and a tie beam. Also `Roof`, `Ridge`, `Rope` (coil plus one drop), `Bucket`, `BucketWater`, `Hoops` (with the bucket's iron handle).
  - The rope runs unbroken from the coil to the handle (user's request).
  - Stone, cap and wood are solid (`PreciseConvexDecomposition`); the rest is walk-through.
- **Quest NPCs (started 2026-10-08):** these live in `W01_SunnyMeadows/Npcs`. Dale the Farmer gives the questline below.
  - **Farmer** (`Npcs/Farmer`, tagged `AmbientIdle`, `IdleStyle = "Farmer"`):
    - Body: an R6 body cloned from the Crafter (standard head and face), with tanned skin `e0a86f`.
    - Gear: 24 Blender meshes (`farmer_gear_build`, `art/meshes/farmer_gear.fbx` + offsets).
      - `Shirt` / `ShirtPlaid` and rolled `SleeveL`/`R` + `SleevePlaidL`/`R` (a modelled red plaid shirt).
      - `Overalls` (bib, straps, waistband), `OverallPocket`, `Brass`, `Trousers`, `Cuffs`, `Boots`, `Soles`.
      - A straw `Hat` / `HatDetail` / `HatBand`, and `Fork*` (the player's Pitchfork mesh).
    - **Pose (final, user's choice):** he stands upright beside the front door, back **2 studs** off the house's west wall (wall x 16.5, torso origin 13.90, 11, −77.6), facing the path (−X).
      - No wall lean, so the hat sits level on the head (dropped 0.25 onto it) and the face shows. Two earlier wall-lean versions were rejected: leaning made the brim hit the wall and tipping it hid his eyes.
      - The right arm is raised 45° forward about the shoulder; the pitchfork stands upright through the fist, butt on the ground.
      - The fork pieces have `Bone = "Tool"`, and the model's `HandPoint` (Vector3, torso space) is the fist they hang from.
    - The pink flower clump that was at his feet moved 4.2 studs along the wall.
  - **`NpcIdleController` model attributes:**
    - `IdleActions`: a comma list of gestures (`wave`, `wipe`, `hatTip`, `brow`, `stamp`); `""` for none. Defaults come from the style.
    - `IdleStyle`: `"Farmer"` gives his own idle: a slow weight shift side to side, the look-around, and every ~10 s one of `hatTip` (left hand up to the brim with a nod), `brow` (wipes his brow) or `stamp` (lifts the pitchfork and thumps it down). The right arm holds still so the fork stays put. Other NPCs default to `wave,wipe`.
    - `HandPoint`: the fist a `Bone = "Tool"` piece follows, so a held tool moves with the arm's gestures and stays upright.
- **Spinning decorations:** `Client.Controllers.SpinnerController` turns anything tagged `Spinner` around its pivot.
  - The turning is a client-only `Animation.Motion.spin`.
  - Attributes: `SpinSpeed` (degrees per second, default 20, negative reverses, live-editable) and `SpinAxis` (`Vector3` in pivot space, default X).
  - The windmill sails spin at 20.
- **All six weapons are Blender meshes (2026-10-07).**
  - **Dagger is done:** 8 MeshParts (`Blade`, `Edge`, `Fuller`, `Ricasso`, `Guard`, `Tips`, `Handle`, `Wrap`), each welded to the unchanged invisible `Grip` with a `WeldConstraint`. `WeaponId` and `Handed` are kept.
    - The user asked for a longer blade, wider at the hilt and staying broad until near the point. The dagger is now 2.93 long overall, with a 1.64 blade about 0.52 wide.
  - **All six World 1 weapons are mesh now (2026-10-07).** Each is one MeshPart per colour, welded to its unchanged `Grip` (and `OffGrip`). Every weapon passed a playtest: hands exactly on `Grip` and `OffGrip`, a real click-swing, and the hotbar icon.
    - Sickle (7): one curled blade keeping the 45° kink.
    - Machete (9): one clipped-point blade. The handle runs as one piece into the hooked end, the rivets are centred on the strap, and there's no lanyard.
    - Shovel (7): a dished spade with a pointed nose. The sleeve and socket are one surface flaring into a clamp curved like the spade. The D-grip sides are single mitred bars. No grain strips.
    - Pitchfork (8): forged crossbar, curved tines, and points that continue each tine's axis.
    - Scythe (7): one sweeping blade.
  - To test drops quickly, temporarily set every `chance` in `Config/Worlds/W01` to 1 and restore the source afterwards (done 2026-10-07, restored).
- **Corn Cob, the secret weapon (2026-10-09, user's idea):** `Weapons.CornCob`, rarity **Secret** (a new last tier in `Weapons.Rarities`), `secret = true`, one-handed, **50 dmg** (user's request 2026-10-09) / 1.0 s / reach 8 / arc 90 / 3 targets / knockback 10, swing `CornBonk`. Dropped only by the Scarecrow King at **2%**.
  - **Shown on its secret tile (user, 2026-10-11; it used to be hidden until found):** the drop slip lists it like any drop, as a silhouette on the black rainbow `Skin_Secret` tile.
  - **Secret tile:** option B (user's pick 2026-10-09): a black gradient with white sparkles and a dashed rim whose rainbow colours fade smoothly into each other along the diagonal (`art/secret_tile.py` `black_tile("b_smooth")` → `art/inventory_v3/tile_secret_b_smooth.png`, `rbxassetid://95740901951853`), set as `Skin_Secret` on `Inventory/Templates/ItemTile`, `Index/Templates/DropRow` and the hotbar `Slot1` (plus `Color_Secret` b03a9e). The first rainbow tile (`134863331106274`) and options A/C are unused. Not in the Weapons shop.
  - **Model:** `Assets/Weapons/CornCob`, 8.7 studs long, cob about 2.4 across (2.8 with kernels), 1,315 faces. Pieces `Stalk` (handle), `Cut` (butt), `Twine` (three grip bands), `Cob` (core), `Kernels` (10 columns × 13 rows of 6-face blocks that follow the cob's curve to the tip), `HuskDark` / `HuskLight` (4 leaves from the stalk that wrap the cob edge to edge and flare at the tips). Blender: `corn_build` text block, `art/meshes/corn_cob.fbx` + `corn_cob_offsets.json`. The user asked for fewer faces (2,627 → 1,315), a thinner and longer cob, and husks that hug the cob.
  - **Animation:** `HOLDS.CornCob` is the Dagger's hold (user's call 2026-10-09: only two holds in the game, one-handed and two-handed; it replaced an upright hold, an over-the-shoulder carry, a trophy hold and a two-handed caveman club). `handed = 1`, no `OffGrip`. `SWINGS.CornBonk`: raised overhead tipped back, slammed down in front (the cob's surface just meets the ground, measured −3.05), held, back. Body lean on the slam stays small (`wp` 6), because lean adds to the downward angle and an 8.7-stud cob went 3 studs into the ground at `wp` 16.
  - **Slam impact** (`impact = "Slam"` in the def): on the swing's `Hit` marker, `WeaponController.slam` raycasts down from 3/4 along the held weapon and plays, there, 10 outward `SlamDust` bursts (a low dust ring), `SlamDebris` clods and a `SlamRing` shockwave (`EffectPresets`). No camera shake. It plays for every client's view of every swing (hit or miss); the spot lands about 8 studs ahead.
- **The first Legendaries (2026-10-11, canvas https://claude.ai/artifact/Xiq7CR3mir1Ymy3mNy62Jz):**
  - **Weathervane Spear** (`Weapons.WeathervaneSpear`): Dale's quest-10 reward (`reward.weapon` in `Config/Quests`), dropped by nothing. Two-handed, 8.7 long like the Corn Cob (user), 45 dmg / 1.1 s, reach 10.5, arc 60, 4 targets, knockback 8; it must out-damage the mace (user). Model `Assets/Weapons/WeathervaneSpear`: Grip + `OffGrip` (0, 0, -1.9), meshes `Gold` (rooster, compass hub, tip collar), `GoldShade` (wing, feathers), `Comb`, `Steel` (tail edge + spear tip), `Iron`, `Plates` / `Ink` (N/E/S/W knobs, eye), `Shaft`, `Wrap`. 697 faces.
  - **Pumpkin King's Mace** (`Weapons.PumpkinMace`): the Scarecrow King drops it at 5%. One-handed, 6.6 long, 38 dmg / 1.0 s, reach 7.5, arc 100, 3 targets, knockback 10. Model `Assets/Weapons/PumpkinMace`: the King's own pumpkin `Head`, `FaceAngry` (Neon) / `FaceCalm` and `BrowsAngry` / `BrowsCalm` (with `Mood` attributes; the template shows angry, calm hidden; no code switches them yet), `Crack`, `Stitches`, `Stem`, `Spikes` (+ collar rivets), `Collar`, `Stake`, `Knots`, `Point`, `Twine`. 548 faces.
  - Blender: `weathervane_build` / `mace_build`, `art/meshes/quest_weapons.fbx` + `quest_weapons_offsets.json`. Playtested: hands 0.00 from `Grip` and `OffGrip`, clean console.
  - Icons (2026-10-11): spear `rbxassetid://106253639238840`, mace `136992838361197` (calm black face). The mace template now shows its calm face (angry hidden).
  - **Still to do:** their own swings (spear: the planned wide "Gust" sweep; for now the Pitchfork's hold + `Thrust`; mace: Dagger hold + `CornBonk`) and the mace's calm/angry switch in a fight.
- **Scarecrow King drops (2026-10-11):** Pitchfork 25%, Scythe 20%, Pumpkin King's Mace 5%, Corn Cob 2%. The Shovel was removed from the boss (user); the Bull still drops it.
- **Scythe `Sweep` is one stroke (2026-10-11):** keys ease to rest, so a key mid-stroke paused the swing. Swing keys take `ease = "out"` / `"linear"` (Animation.Clips.Weapons) for the move into them.
- **The dated backup folders were deleted on 2026-10-08** (user's request), after every conversion was approved. The old part versions are gone; the `.blend` and FBX sources in `art/meshes/` remain.
- Avoid z-fighting: overlapping parts must not share a face plane; make one slightly larger or offset it.
- **Part-count tool:** `ServerStorage.DevTools.MapOptimizer` is a dev-only module; load it in Edit mode with `loadstring(...Source)()`. It provides:
  - `merge`: exact greedy merges.
  - `remesh`: rebuilds each look of world-aligned blocks as the fewest boxes, running through buried space only, so nothing visible changes.
  - `buried`: parts hidden inside another solid block.
  - `nudgeClear`: slides a decoration out of whatever it's stuck in.

  World 1 was optimized with it on 2026-10-07.
- **Blossom trees on mounds (2026-10-08, user's report):** each `Tree_Blossom` has a flat `FallenPetals` ring (about 6×7) that floated where a tree stood near a mound tier's edge. 7 of the 8 mound trees were fixed.
  - Three were turned and shifted under 1.5 studs.
  - One moved 5 studs along its tier.
  - One moved up onto Hill_R02's top tier.
  - On the crowded Hill_R01 / Hill_L02 tiers, two trees stayed put and only their `FallenPetals` were slid (one also shrunk to 80%).
  - Growing the mound blocks was rejected: it would bury ledge fences, hit the house and break path/plaza clearance.
  - **Check:** sample an 11×11 grid under each `FallenPetals` and raycast down onto `Ground` / `Hills`. Every hit must be at the ring's own height.
- Decorations rest on `Ground` and `Decorations/Hills` but shouldn't push into anything else. A flower or tuft stuck in a rock or wall is wasted parts.
- **Keep every decoration at least 1 stud from the paths, the plaza and the boss arena** (`Ground/Paths`, `Ground/Hub`, `Ground/BossArena`), the user's rule from 2026-10-07.
  - Bridges are the exception, and so are the map's base pieces that border the plaza (the `Hedges/OuterRim` blocks and `Hill_R01`).
  - Two bushes in narrow strips between the cliff and the plaza were scaled to 70–80% to fit.
  - Check: grow each path part by 1 stud on each side, covering from 0.5 below its top to 2.5 above, and look for decoration parts inside.
  - On 2026-10-07, 102 items were moved out this way (grass, flowers, bushes, a boulder). None were removed.
- **Keep every decoration at least 1 stud from the pond's open water** (`Ground/River` water not covered by ground), the user's rule from 2026-10-07. That includes the reeds; lily pads are the only exception.
  - Check:
    1. Raycast a 0.5-stud grid over each water part; cells where water is the first `Ground` hit are open water.
    2. Merge each row into strips, and grow every strip 1 stud on all sides, from 0.5 under the water surface to 10 above it.
    3. Look for decoration parts inside the strips.
  - The 10-stud height catches tree canopies hanging over the water.
  - On 2026-10-07 this moved 18 reed clumps, 9 grass tufts, 7 flower patches, 4 rocks (2 shrunk slightly) and 1 oak. Bridges, rim hedges and hills are map base and stayed.

## Skills

The skills are **personal skills** in `~/.claude/skills/` (not in this repo), so they work in any session:
- `add-enemy` and `animate-enemy`: enemies.
- `add-weapon` and `animate-weapon`: weapons (one- and two-handed).
- `animate-player`: idle, walk and sprint (`Clips.Locomotion`) and previewing R6 poses.
- `roblox-part-modeling`: building and redesigning any part-built model, with the preview-and-approve workflow.
- `blender-modeling`: blocky meshes made in Blender (Blender MCP), exported as FBX and set up in Studio.
- `roblox-ui-icons`: drawing UI icons as PNGs, uploading them, and swapping them into hand-built UI. Icon sources live in `art/`.
- `roblox-ui-text-centering`: centring text and icon + text groups on buttons, badges and bubbles. It covers Luckiest Guy's measured 0.16 × TextSize lift, face vs lip, fixed-pixel 9-slice insets and scaled screenshots, and measuring with `art/ui_center_check.py`. Use it before calling any label centred.

Use them for those jobs, and update them when a job teaches something new.

## Testing in Studio

- There are no automatic test suites any more (`LogicTests` / `CombatSim` tested the deleted dice duel). After a change, start a playtest and check `get_console_output` for errors and warnings, then exercise the feature for real (kill an enemy, talk to Dale…).
- Each `execute_luau` call runs in its own Luau VM: `require` gives a **fresh** module instance, so you can't read or call a running service's state. Drive the game through remotes, attributes and instances instead.
- Tool calls take seconds, so an enemy keeps fighting between steps. For combat tests, raise the player's `MaxHealth`/`Health` from the **Server** datamodel (client-side changes don't count).
- Screenshots of poses mislead; when it matters, measure directions numerically (e.g. a part's `LookVector` relative to `HumanoidRootPart`).
- After a scripted camera shot, set `workspace.CurrentCamera.CameraType` back (Custom in play, Fixed in edit). Stop the playtest when done.
