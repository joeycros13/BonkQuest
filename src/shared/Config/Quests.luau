--!strict
-- Quests: every questline, one per quest giver, shared by QuestService (server:
-- progress, rewards) and the client (QuestController's dialogue, QuestTrackerUI,
-- GuideController's arrow).
--   DaleFarm        Dale the Farmer, "Trouble on Dale's Farm" (World 1, 2026-10-08,
--                   the user's design)
--   RangerRedwoods  Ranger Rowan, "Trouble in the Redwoods" (World 2, 2026-10-11);
--                   the final reward is the Firefly Lantern (LanternFlail)
--   ExplorerCaverns Explorer Pip, "Into the Crystal Caverns" (World 3, 2026-10-17,
--                   picked on the design canvas); the final reward is the Diamond
--                   Pickaxe.
-- No line has a "level" step since 2026-10-26 (the user): each became a gathering step (step 5)
-- or an elite step (step 9), every line sends the player after its world's elite, and kill and
-- gather counts went up about half (art/tools/balance/rescale.py QUESTS mirrors the numbers).
-- Lines run side by side: each player has a step in every line, published as
-- per-line attributes (Quests.attr). A giver model (tagged QuestGiver) names its
-- line in its "QuestLine" attribute. Add a line to `lines` and `order` and give it
-- a giver; nothing else needs to change.
--
-- Each line has an id, name, short (the tracker tab), world (the world whose
-- tracker shows it first), npc { name, short, portrait }, returnTrack, returnNote,
-- finished, and steps. Steps run one at a time. Each step has:
--   kind       "kill"  defeat `count` of enemy `target` (a Config/Worlds id)
--              "earn"  earn `amount` coins, counted from accepting
--              "level" reach level `level`
--              "give"  hand Dale `amount` coins (taken when handing in)
--              "gather" gather `count` of material `target` (a Config/Materials id),
--                      counted from accepting (2026-10-19: chopping, mining)
--              "bring" hand over `items` ({ { id, count } } materials, taken when
--                      handing in); progress is the total held toward the total
--                      needed. Fish never go in quests (user: they're for potions)
--              "hunt"  defeat several kinds at once: `targets` ({ { id, count } } Config/Worlds
--                      ids, 2026-10-26, the user: quests that kill several enemies); each
--                      kind counts up to its own count (the kills go out as the
--                      "QuestKills_<line>" attribute, "Chicken=5,Bull=2"), progress is
--                      the total toward the total needed
--   objective  the red objective line in the dialogue's Objective box
--   track      the tracker line: the words before {braces} become the small
--              label ("DEFEAT"), the part in braces the red name (the enemy or
--              thing to look for)
--   reward     coins / exp given when handing in (weapon = a Config/Weapons id;
--              item = a Config/Materials quest item, given once: each line's
--              "defeat the boss" step hands over the item its world's second
--              armour set needs, 2026-10-12)
--   offer      the giver's lines when giving the quest
--   offerHasTool  (optional) the offer when the step's tool is already owned: the lines
--              that send the player shopping are left out (issue 21; Quests.offerLines)
--   reminder   their line if you talk to them mid-quest
--   complete   their lines when you hand it in
-- In dialogue lines, [square brackets] mark the objective: bold and red.
--
-- A gather / bring step whose material comes from a node the player has no good
-- enough tool for runs in two phases on the tracker (2026-10-21, the user): first
-- "Buy a {Wooden Axe}" / "Upgrade to a {Stone Axe}" at the Weaponsmith
-- (Quests.toolNeeded, Quests.ToolText; the guide arrow points at that world's
-- Weapons stall), then the gathering itself. The server's step doesn't change: the
-- tool phase is only what the tracker and the arrow show while the tool is missing.
-- The Weaponsmith opens on that tool's row, glowing, with a "Needed for Dale's quest"
-- ribbon (Quests.shopNeeds, ShopUI; issue 21, 2026-10-25). A "gather" step counts what
-- is already held, like "bring", but takes nothing at hand-in.
--
-- All the wording and numbers here are free to edit.

local Enemies = require(script.Parent:WaitForChild("Enemies"))
local Gathering = require(script.Parent:WaitForChild("Gathering"))
local Materials = require(script.Parent:WaitForChild("Materials"))
local Tools = require(script.Parent:WaitForChild("Tools"))
local Weapons = require(script.Parent:WaitForChild("Weapons"))

-- Each line's rewards are written for its world (about x10 the last world's, coins and EXP alike); nothing
-- scales them in code.

local Quests = {}

-- The tracker's tool phase: the line (a tool's name goes in the braces) and the note
-- under it (the stall's name).
Quests.ToolText = {
	buy = "Buy a {%s}",
	upgrade = "Upgrade to a {%s}",
	note = "at the Weaponsmith",
}

export type Reward = { coins: number?, exp: number?, weapon: string?, item: string? }
export type Step = {
	kind: string,
	target: string?,
	count: number?,
	items: { { id: string, count: number } }?,
	targets: { { id: string, count: number } }?,
	amount: number?,
	level: number?,
	objective: string,
	track: string,
	reward: Reward,
	offer: { string },
	offerHasTool: { string }?,
	reminder: { string },
	complete: { string },
}
export type Line = {
	id: string,
	name: string,
	short: string,
	world: number,
	npc: { name: string, short: string, portrait: string },
	returnTrack: string,
	returnNote: string,
	finished: { string },
	steps: { Step },
}

local lines: { [string]: Line } = {}

lines.DaleFarm = {
	id = "DaleFarm",
	name = "Trouble on Dale's Farm",
	world = 1,
	-- the tracker's title
	short = "Dale's Farm",
	npc = {
		name = "Dale the Farmer",
		short = "Dale",
		-- art/quest/portrait_Dale.png
		portrait = "rbxassetid://72658452496108",
	},
	-- the tracker line once a step is done
	returnTrack = "Return to {Dale the Farmer}",
	returnNote = "to claim your reward",
	-- what he says once every step is done
	finished = { "Thanks to you, the farm's peaceful again. Come by anytime, partner!" },
	steps = {
		{
			kind = "kill",
			target = "Chicken",
			count = 8,
			objective = "Defeat 8 Angry Chickens",
			track = "Defeat {Angry Chickens}",
			reward = { coins = 25, exp = 20 },
			offer = {
				"Well howdy there, partner! Name's Dale. I've been farmin' this here meadow for forty years.",
				"Lately my chickens have gone plumb mad. Peckin' my crops, peckin' my boots, peckin' ME!",
				"Reckon you could [defeat 8 Angry Chickens] for me? I'll make it worth your while.",
			},
			reminder = { "Them chickens are still runnin' wild! [Defeat 8 Angry Chickens], would ya?" },
			complete = { "Well I'll be! Eight fewer feathered menaces. Here, take this for your trouble." },
		},
		{
			-- 2026-10-19 (user): was "earn 75 coins"; teaches the axe early
			kind = "gather",
			target = "OakLog",
			count = 8,
			-- "Collect", not "Chop" (issue 21, 2026-10-25): logs already held count
			objective = "Collect 8 Oak Logs",
			track = "Collect {Oak Logs}",
			reward = { coins = 30, exp = 30 },
			offer = {
				"Now, a farmhand's gotta keep the stove burnin', and that means firewood.",
				"You can't chop a tree with that little dagger, though. The Weaponsmith on the plaza sells all the tools: axes, pickaxes, fishin' rods.",
				"Pick yourself up a [Wooden Axe] first. Then head to them big oaks by the cliffs and [collect 8 Oak Logs].",
			},
			offerHasTool = {
				"Now, a farmhand's gotta keep the stove burnin', and that means firewood.",
				"I see you've already got yourself an axe. Head to them big oaks by the cliffs and [collect 8 Oak Logs].",
			},
			reminder = { "Them big oaks by the cliffs are full of firewood. [Collect 8 Oak Logs] and come see me." },
			complete = { "Now that's a fine stack of firewood! Hang on to it, I'll be needin' logs for the barn soon. Here's a little somethin' for the sweat." },
		},
		{
			-- 2026-10-26 (the user): a mixed hunt
			kind = "hunt",
			targets = { { id = "Chicken", count = 12 }, { id = "Bull", count = 3 } },
			objective = "Defeat 12 Angry Chickens and 3 Raging Bulls",
			track = "Defeat {Chickens and Bulls}",
			reward = { coins = 40, exp = 40 },
			offer = {
				"Bad news, partner. Them chickens multiplied overnight, and now the bulls are joinin' in.",
				"[Defeat 12 Angry Chickens and 3 Raging Bulls] before they flatten my whole carrot patch!",
			},
			reminder = { "Still a whole lotta cluckin' and stompin' out there! [Defeat 12 Angry Chickens and 3 Raging Bulls]." },
			complete = { "My carrots thank ya. So do I. Them bulls are another story, though..." },
		},
		{
			kind = "kill",
			target = "Bull",
			count = 5,
			objective = "Defeat 5 Raging Bulls",
			track = "Defeat {Raging Bulls}",
			reward = { coins = 60, exp = 60 },
			offer = {
				"Them bulls up the paths are seein' red. They knocked my fence clean over!",
				"[Defeat 5 Raging Bulls] and teach 'em some manners.",
				"Mind you, they hit hard. Some proper armor from the crafter wouldn't go amiss.",
			},
			reminder = { "Watch them horns! [Defeat 5 Raging Bulls]." },
			complete = { "Five bulls! You're tougher than you look, friend." },
		},
		{
			-- 2026-10-26 (the user): the level step went; mining in its place
			kind = "gather",
			target = "Stone",
			count = 10,
			objective = "Collect 10 Stone",
			track = "Collect {Stone}",
			-- + the Rusty Blade (Relic), the start of the secret super weapon (2026-10-12)
			reward = { coins = 50, exp = 60, weapon = "RustyBlade" },
			offer = {
				"Them bulls kicked my old well clean in half. I need stone to build it back up.",
				"A pickaxe'll crack them grey boulders; the Weaponsmith on the plaza sells those.",
				"Grab yourself a [Wooden Pickaxe] and [collect 10 Stone].",
			},
			offerHasTool = {
				"Them bulls kicked my old well clean in half. I need stone to build it back up.",
				"That pickaxe of yours'll crack them grey boulders. [Collect 10 Stone] for me.",
			},
			reminder = { "Them grey boulders are full of good stone. [Collect 10 Stone]." },
			complete = {
				"Now that's good honest stone! Hang on to it, the barn's gonna need some too.",
				"Oh, and diggin' out the old well I found this. Rusty as anything... but that empty socket's always made me wonder.",
			},
		},
		{
			-- 2026-10-19 (user): was "give 200 coins"; the logs and stone are taken at hand-in
			kind = "bring",
			items = { { id = "OakLog", count = 15 }, { id = "Stone", count = 15 } },
			objective = "Bring Dale 15 Oak Logs and 15 Stone",
			track = "Bring Dale {Logs and Stone}",
			reward = { coins = 80, exp = 100 },
			offer = {
				"I hate to ask, but them bulls flattened my barn door and knocked the wall stones loose.",
				"Could you [bring me 15 Oak Logs and 15 Stone] for the repairs? A pickaxe'll crack them boulders; the Weaponsmith sells those too.",
			},
			offerHasTool = {
				"I hate to ask, but them bulls flattened my barn door and knocked the wall stones loose.",
				"Could you [bring me 15 Oak Logs and 15 Stone] for the repairs? That pickaxe of yours'll crack them boulders.",
			},
			reminder = { "No rush... but my barn door's still flat. [Bring me 15 Oak Logs and 15 Stone]." },
			complete = { "Bless ya! That door'll be standin' by sundown. Here, it ain't much, but it's honest." },
		},
		{
			-- 2026-10-26 (the user): a mixed hunt with the elites
			kind = "hunt",
			targets = { { id = "Bull", count = 6 }, { id = "Stallion", count = 3 } },
			objective = "Defeat 6 Raging Bulls and 3 Wild Stallions",
			track = "Defeat {Bulls and Stallions}",
			reward = { coins = 100, exp = 100 },
			offer = {
				"Word is the bulls are gatherin' near the boss platform, and the wild stallions are runnin' with 'em now.",
				"Head up there and [defeat 6 Raging Bulls and 3 Wild Stallions] before they stampede the whole valley.",
			},
			reminder = { "That herd ain't gonna round itself up! [Defeat 6 Raging Bulls and 3 Wild Stallions]." },
			complete = { "The valley's quiet for the first time in weeks. And now I see who's been stirrin' 'em up..." },
		},
		{
			kind = "kill",
			target = "BossScarecrow",
			count = 1,
			objective = "Defeat the Scarecrow King",
			track = "Defeat the {Scarecrow King}",
			reward = { coins = 150, exp = 150, item = "LuckyHorseshoe" },
			offer = {
				"Now I know who's behind all this ruckus. The Scarecrow King!",
				"He's been riling up my animals from that platform up north. [Defeat the Scarecrow King]!",
			},
			reminder = { "That pumpkin-headed menace is still up there! [Defeat the Scarecrow King]." },
			complete = {
				"You beat the Scarecrow King?! Well, I'll be a monkey's uncle!",
				"Here, take my [lucky horseshoe]. The crafter in town can work it into some fine armor.",
			},
		},
		{
			-- 2026-10-26 (the user): the elites and the boss together
			kind = "hunt",
			targets = { { id = "Stallion", count = 4 }, { id = "BossScarecrow", count = 1 } },
			objective = "Defeat 4 Wild Stallions and the Scarecrow King",
			track = "Defeat {Stallions and the King}",
			reward = { coins = 120, exp = 150 },
			offer = {
				"Bad news. That old scarecrow's stitched himself back together.",
				"And now he's got the wild stallions guardin' his platform. They kick like thunder.",
				"[Defeat 4 Wild Stallions and the Scarecrow King] again. That Harvest Knight armor'd help, if you've a mind to craft it.",
			},
			reminder = { "Them stallions are still guardin' that pumpkin-head! [Defeat 4 Wild Stallions and the Scarecrow King]." },
			complete = { "Stallions scattered and the King knocked flat again! The strongest farmhand this meadow's ever seen." },
		},
		{
			-- 2026-10-26 (the user): the Clean Up, a long hunt through the whole world
			kind = "hunt",
			targets = { { id = "Chicken", count = 10 }, { id = "Bull", count = 8 }, { id = "Stallion", count = 5 }, { id = "BossScarecrow", count = 3 } },
			objective = "Clean up the farm: defeat 10 Angry Chickens, 8 Raging Bulls, 5 Wild Stallions and the Scarecrow King 3 times",
			track = "Clean up {the farm}",
			-- The quest-only Weathervane Spear (Legendary, 2026-10-11).
			reward = { coins = 300, exp = 300, weapon = "WeathervaneSpear" },
			offer = {
				"This is it, partner. Time for the big clean up.",
				"Every critter on this farm's still sore from that scarecrow's spell, and he keeps stitchin' himself back together.",
				"[Defeat 10 Angry Chickens, 8 Raging Bulls, 5 Wild Stallions and the Scarecrow King 3 times], and this farm'll finally have some peace.",
				"Do this, and I'll give ya somethin' I've been savin' a long, long time.",
			},
			reminder = { "Still some cleanin' up to do! Chickens, bulls, stallions, and that pumpkin-headed menace." },
			complete = {
				"You did it! The farm's clean, quiet and safe at last.",
				"Here. This was my granddaddy's. I reckon it's yours now.",
			},
		},
	} :: { Step },
}

-- Ranger Rowan on the cabin porch at the World 2 camp (2026-10-11). Numbers are
-- starting values (the user will tune them later).
-- Rewards are x10 Dale's, step for step (2026-10-24, the rescale: coins and EXP x10 a world).
lines.RangerRedwoods = {
	id = "RangerRedwoods",
	name = "Trouble in the Redwoods",
	world = 2,
	short = "The Redwoods",
	npc = {
		name = "Ranger Rowan",
		short = "Rowan",
		-- art/quest/portrait_Rowan.png
		portrait = "rbxassetid://92115376888229",
	},
	returnTrack = "Return to {Ranger Rowan}",
	returnNote = "to claim your reward",
	finished = { "Thanks to you, the redwoods are at peace. My fire's always warm for you, friend." },
	steps = {
		{
			kind = "kill",
			target = "Fox",
			count = 8,
			objective = "Defeat 8 Snarling Foxes",
			track = "Defeat {Snarling Foxes}",
			reward = { coins = 250, exp = 200 },
			offer = {
				"Evening, traveller. I'm Ranger Rowan. I look after these redwoods.",
				"Something has the wildlife riled up. The foxes snap at anything that moves.",
				"Could you [defeat 8 Snarling Foxes] for me? They won't make it easy.",
			},
			reminder = { "Those foxes are still prowling the trails. [Defeat 8 Snarling Foxes]." },
			complete = { "That's a relief. The trail's safer already. Here, for your trouble." },
		},
		{
			-- 2026-10-21 (user): was "earn 300 coins"; the fur goes toward the Stone Axe
			kind = "gather",
			target = "FoxFur",
			count = 10,
			objective = "Collect 10 Fox Fur",
			track = "Collect {Fox Fur}",
			reward = { coins = 300, exp = 300 },
			offer = {
				"Your old wooden axe won't bite into a redwood. You'll want a Stone Axe.",
				"The weaponsmith wraps their grips in fox fur. Go and [collect 10 Fox Fur] from the foxes on the trail.",
			},
			reminder = { "Those foxes still have their coats. [Collect 10 Fox Fur]." },
			complete = { "Thick and warm. That'll make a fine grip, and the crafter can stitch the rest into a hide coat." },
		},
		{
			-- 2026-10-26 (the user): a mixed hunt
			kind = "hunt",
			targets = { { id = "Fox", count = 12 }, { id = "Boar", count = 3 } },
			objective = "Defeat 12 Snarling Foxes and 3 Wild Boars",
			track = "Defeat {Foxes and Boars}",
			reward = { coins = 400, exp = 400 },
			offer = {
				"I counted tracks this morning. Far more foxes than there should be, and boar prints among them.",
				"Please [defeat 12 Snarling Foxes and 3 Wild Boars] before they overrun the camp.",
			},
			reminder = { "I can still hear them yipping and grunting. [Defeat 12 Snarling Foxes and 3 Wild Boars]." },
			complete = { "Quiet at last. You move through these woods like you were born here." },
		},
		{
			kind = "kill",
			target = "Boar",
			count = 5,
			objective = "Defeat 5 Wild Boars",
			track = "Defeat {Wild Boars}",
			reward = { coins = 600, exp = 600 },
			offer = {
				"Now the boars are charging hikers right off the trail.",
				"Their hides are thick, so hit hard, and wear something tougher than you came in. [Defeat 5 Wild Boars].",
			},
			reminder = { "Mind those tusks! [Defeat 5 Wild Boars]." },
			complete = { "Five boars! I'll mark those trails open again." },
		},
		{
			-- 2026-10-26 (the user): the level step went; chopping in its place
			kind = "gather",
			target = "RedwoodLog",
			count = 12,
			objective = "Collect 12 Redwood Logs",
			track = "Collect {Redwood Logs}",
			reward = { coins = 500, exp = 600 },
			offer = {
				"The boars trampled my woodpile flat. Winter comes early under these trees.",
				"Only a Stone Axe will fell a redwood. The Weaponsmith by the gate can turn your wooden axe into one.",
				"Then [collect 12 Redwood Logs] for me.",
			},
			offerHasTool = {
				"The boars trampled my woodpile flat. Winter comes early under these trees.",
				"That Stone Axe of yours will fell a redwood nicely. [Collect 12 Redwood Logs] for me.",
			},
			reminder = { "The camp's fire won't last the night. [Collect 12 Redwood Logs]." },
			complete = { "Now that's a woodpile. Keep hold of it, the tower's going to need beams too." },
		},
		{
			-- 2026-10-21 (user): was "give 600 coins"; the logs and tusks are taken at hand-in
			kind = "bring",
			items = { { id = "RedwoodLog", count = 15 }, { id = "BoarTusk", count = 6 } },
			objective = "Bring Rowan 15 Redwood Logs and 6 Boar Tusks",
			track = "Bring Rowan {Logs and Tusks}",
			reward = { coins = 800, exp = 1000 },
			offer = {
				"The boars battered the lookout tower. I can't keep watch from up there like this.",
				"Could you [bring me 15 Redwood Logs and 6 Boar Tusks]? Logs for the beams, tusks for pegs.",
				"Only a Stone Axe will fell a redwood. The Weaponsmith by the gate can turn your wooden axe into one.",
			},
			offerHasTool = {
				"The boars battered the lookout tower. I can't keep watch from up there like this.",
				"Could you [bring me 15 Redwood Logs and 6 Boar Tusks]? Logs for the beams, tusks for pegs.",
				"That Stone Axe of yours will fell a redwood nicely.",
			},
			reminder = { "The tower still needs fixing. [Bring me 15 Redwood Logs and 6 Boar Tusks]." },
			complete = { "Thank you. The tower will be standing tall by morning. Take this, it's what I can spare." },
		},
		{
			-- 2026-10-26 (the user): a mixed hunt with the elites
			kind = "hunt",
			targets = { { id = "Boar", count = 6 }, { id = "Bear", count = 3 } },
			objective = "Defeat 6 Wild Boars and 3 Grizzly Bears",
			track = "Defeat {Boars and Bears}",
			reward = { coins = 1000, exp = 1000 },
			offer = {
				"From the tower I spotted grizzlies guarding the path to the old ruins, with a pack of boars around them.",
				"[Defeat 6 Wild Boars and 3 Grizzly Bears] so we can find out what's stirring in there.",
			},
			reminder = { "The bears and boars still block the ruins. [Defeat 6 Wild Boars and 3 Grizzly Bears]." },
			complete = { "The path's clear. And now I know what's behind all this..." },
		},
		{
			kind = "kill",
			target = "ElderTreant",
			count = 1,
			objective = "Defeat the Elder Treant",
			track = "Defeat the {Elder Treant}",
			reward = { coins = 1500, exp = 1500, item = "RangerBadge" },
			offer = {
				"The Elder Treant. The oldest tree in the forest has woken, and it's furious.",
				"Its rage is spreading to every creature here. Go to the ruins and [defeat the Elder Treant].",
			},
			reminder = { "The ruins lie past the bears' path. [Defeat the Elder Treant]." },
			complete = {
				"You felled the Elder Treant?! In all my years, I've never seen the like.",
				"You've earned this: my [ranger's badge]. Any crafter will know what it means.",
			},
		},
		{
			-- 2026-10-26 (the user): the elites and the boss together
			kind = "hunt",
			targets = { { id = "Bear", count = 4 }, { id = "ElderTreant", count = 1 } },
			objective = "Defeat 4 Grizzly Bears and the Elder Treant",
			track = "Defeat {Bears and the Treant}",
			reward = { coins = 1200, exp = 1500 },
			offer = {
				"Bad news. Roots don't die easily. The treant is growing back, stronger than before.",
				"Every bear in the forest has gathered round its ruins to guard it.",
				"[Defeat 4 Grizzly Bears and the Elder Treant] before it takes root for good.",
			},
			reminder = { "The grizzlies are still circling the ruins, and the treant's still standing. [Defeat 4 Grizzly Bears and the Elder Treant]." },
			complete = { "Bears and treant both! The strongest warden these woods have ever had." },
		},
		{
			-- 2026-10-26 (the user): the Clean Up, a long hunt through the whole world
			kind = "hunt",
			targets = { { id = "Fox", count = 10 }, { id = "Boar", count = 8 }, { id = "Bear", count = 5 }, { id = "ElderTreant", count = 3 } },
			objective = "Clean up the forest: defeat 10 Snarling Foxes, 8 Wild Boars, 5 Grizzly Bears and the Elder Treant 3 times",
			track = "Clean up {the forest}",
			-- The quest-only Firefly Lantern (Legendary, 2026-10-11).
			reward = { coins = 3000, exp = 3000, weapon = "LanternFlail" },
			offer = {
				"This is it. The treant keeps regrowing, and its rage still runs through every creature here.",
				"[Defeat 10 Snarling Foxes, 8 Wild Boars, 5 Grizzly Bears and the Elder Treant 3 times], and the forest can finally rest.",
				"Do this, and I'll trust you with something very special.",
			},
			reminder = { "The forest isn't calm yet. Foxes, boars, bears, and that old tree." },
			complete = {
				"You did it. Listen... the forest is quiet again.",
				"This lantern has lit my way for years. The fireflies chose you. It's yours now.",
			},
		},
	} :: { Step },
}

-- Explorer Pip beside the boarded-up mine entrance at the end of the World 3 entry
-- hall (2026-10-17). His mapping crew went missing deeper in; they turn up past the
-- Spider Queen's hall. Numbers are starting values, about twice Rowan's.
-- Rewards about x10 Rowan's step for step (2026-10-24, the rescale). Steps 5 and 9 were levels 60 / 65 until
-- 2026-10-26 (the user: no level steps); now Crystal Shards and the Crystal Golems.
lines.ExplorerCaverns = {
	id = "ExplorerCaverns",
	name = "Into the Crystal Caverns",
	world = 3,
	short = "The Caverns",
	npc = {
		name = "Explorer Pip",
		short = "Pip",
		-- art/quest/portrait_Pip.png (determined-cohen worktree, 2026-10-17)
		portrait = "rbxassetid://111659781861627",
	},
	returnTrack = "Return to {Explorer Pip}",
	returnNote = "to claim your reward",
	finished = { "Every tunnel's on my map now, thanks to you. The crew says hello. Come back any time, partner!" },
	steps = {
		{
			kind = "kill",
			target = "CaveBat",
			count = 8,
			objective = "Defeat 8 Cave Bats",
			track = "Defeat {Cave Bats}",
			reward = { coins = 2500, exp = 2000 },
			offer = {
				"Oh! A real person, down here! I'm Pip, explorer and map-maker.",
				"My crew went deeper into these caverns to map them, and they never came back.",
				"The bats keep flapping my lantern out. Could you [defeat 8 Cave Bats] so I can see where I'm going?",
			},
			reminder = { "Still too many wings in the dark. [Defeat 8 Cave Bats], please!" },
			complete = { "Light! Lovely, steady light. You're handy to have around." },
		},
		{
			-- (2026-10-24) World 3's gathering, like Dale's and Rowan's step 2: the Ore Rocks
			kind = "gather",
			target = "IronOre",
			count = 8,
			-- "Collect", not "Mine" (issue 21, 2026-10-25): ore already held counts
			objective = "Collect 8 Iron Ore",
			track = "Collect {Iron Ore}",
			reward = { coins = 3000, exp = 3000 },
			offer = {
				"My crew's pick snapped down here, and mine's a wooden toy next to these rocks.",
				"The Weaponsmith by the way in can turn your wooden pickaxe into a Crystal Pickaxe.",
				"Then find the grey rocks streaked with orange and [collect 8 Iron Ore]. Hold on to it, we'll want ore for the winch later.",
			},
			offerHasTool = {
				"My crew's pick snapped down here, but I see you've got a Crystal Pickaxe already.",
				"Find the grey rocks streaked with orange and [collect 8 Iron Ore]. Hold on to it, we'll want ore for the winch later.",
			},
			reminder = { "Grey rocks, orange veins. [Collect 8 Iron Ore] with a Crystal Pickaxe." },
			complete = { "Good solid ore! A natural! Now let's go find that trail." },
		},
		{
			-- 2026-10-26 (the user): a mixed hunt
			kind = "hunt",
			targets = { { id = "CaveBat", count = 12 }, { id = "PebbleGolem", count = 3 } },
			objective = "Defeat 12 Cave Bats and 3 Pebble Golems",
			track = "Defeat {Bats and Pebble Golems}",
			reward = { coins = 4000, exp = 4000 },
			offer = {
				"My crew marked their path on the walls, but the bats nested right over it, and the rocks there walk.",
				"[Defeat 12 Cave Bats and 3 Pebble Golems] and clear the way.",
			},
			reminder = { "The marks are under all those bats and pebbles. [Defeat 12 Cave Bats and 3 Pebble Golems]." },
			complete = { "There! Chalk arrows, and a boot print. They came this way!" },
		},
		{
			kind = "kill",
			target = "PebbleGolem",
			count = 5,
			objective = "Defeat 5 Pebble Golems",
			track = "Defeat {Pebble Golems}",
			reward = { coins = 6000, exp = 6000 },
			offer = {
				"The arrows point down the tunnels, but more rocks keep getting up and walking.",
				"[Defeat 5 Pebble Golems] so I can chart it.",
			},
			reminder = { "Can't draw a map with the map walking around. [Defeat 5 Pebble Golems]." },
			complete = { "Charted! Well, it's mostly pebbles now." },
		},
		{
			-- 2026-10-26 (the user): the level step went; mining in its place
			kind = "gather",
			target = "CrystalShard",
			count = 10,
			objective = "Collect 10 Crystal Shards",
			track = "Collect {Crystal Shards}",
			reward = { coins = 5000, exp = 6000 },
			offer = {
				"The tunnel ends at a sheer drop, and it's pitch black down there.",
				"The crystal clusters glow pink and purple and blue. Your Crystal Pickaxe will crack them.",
				"[Collect 10 Crystal Shards] and I'll make us some lamps.",
			},
			reminder = { "No light, no way down. [Collect 10 Crystal Shards]." },
			complete = { "Look at them glow! Keep them safe, the winch at the drop will want some too." },
		},
		{
			-- (2026-10-24) the mined bring step, like Rowan's step 6 (x10 its reward)
			kind = "bring",
			items = { { id = "IronOre", count = 15 }, { id = "CrystalShard", count = 15 } },
			objective = "Bring Pip 15 Iron Ore and 15 Crystal Shards",
			track = "Bring Pip {Ore and Shards}",
			reward = { coins = 8000, exp = 10000 },
			offer = {
				"The old winch at the drop is busted. It needs new gears and a new lamp.",
				"Could you [bring me 15 Iron Ore and 15 Crystal Shards]? Ore for the gears, shards for the light.",
			},
			reminder = { "No gears, no light, no way down. [Bring me 15 Iron Ore and 15 Crystal Shards]." },
			complete = { "Clank, whirr, glow, perfect! Hold on tight, we're going down." },
		},
		{
			-- 2026-10-26 (the user): a mixed hunt with the elites
			kind = "hunt",
			targets = { { id = "PebbleGolem", count = 6 }, { id = "CrystalGolem", count = 3 } },
			objective = "Defeat 6 Pebble Golems and 3 Crystal Golems",
			track = "Defeat {Pebble and Crystal Golems}",
			reward = { coins = 10000, exp = 10000 },
			offer = {
				"Bad news: the lower hall is guarded by Crystal Golems, big shiny ones, with pebble golems all around them.",
				"[Defeat 6 Pebble Golems and 3 Crystal Golems] and we're through.",
			},
			reminder = { "They're pretty, but they're in the way. [Defeat 6 Pebble Golems and 3 Crystal Golems]." },
			complete = { "We're through! And there's webbing everywhere. I don't like webbing." },
		},
		{
			kind = "kill",
			target = "SpiderQueen",
			count = 1,
			objective = "Defeat the Spider Queen",
			track = "Defeat the {Spider Queen}",
			reward = { coins = 15000, exp = 15000, item = "MinersLantern" },
			offer = {
				"That's the one hall nobody's ever mapped. The Spider Queen lives there.",
				"I think she has my crew's gear. [Defeat the Spider Queen] and look for anything of theirs.",
			},
			reminder = { "She's in the big hall past the webs. [Defeat the Spider Queen]." },
			complete = {
				"That lantern! It's our miner's. And if she dropped it, the crew got past her.",
				"Keep the [miner's lantern]. The crafter here can work it into some fine armor.",
			},
		},
		{
			-- 2026-10-26 (the user): the elites and the boss together
			kind = "hunt",
			targets = { { id = "CrystalGolem", count = 4 }, { id = "SpiderQueen", count = 1 } },
			objective = "Defeat 4 Crystal Golems and the Spider Queen",
			track = "Defeat {Crystal Golems and the Queen}",
			reward = { coins = 12000, exp = 15000 },
			offer = {
				"Fresh tracks lead past her hall, deeper than any map. But she's back, and the golems have closed ranks around her.",
				"[Defeat 4 Crystal Golems and the Spider Queen] and we can follow the tracks.",
			},
			reminder = { "They keep reforming, and she keeps spinning! [Defeat 4 Crystal Golems and the Spider Queen]." },
			complete = { "Ready? Me too. Let's finish this." },
		},
		{
			-- 2026-10-26 (the user): the Clean Up, a long hunt through the whole world
			kind = "hunt",
			targets = { { id = "CaveBat", count = 10 }, { id = "PebbleGolem", count = 8 }, { id = "CrystalGolem", count = 5 }, { id = "SpiderQueen", count = 3 } },
			objective = "Clean up the caverns: defeat 10 Cave Bats, 8 Pebble Golems, 5 Crystal Golems and the Spider Queen 3 times",
			track = "Clean up {the caverns}",
			-- The quest-only Diamond Pickaxe (Legendary).
			reward = { coins = 30000, exp = 30000, weapon = "DiamondPickaxe" },
			offer = {
				"She keeps coming back, and the whole cave answers her: bats, pebbles, crystal golems, everything.",
				"[Defeat 10 Cave Bats, 8 Pebble Golems, 5 Crystal Golems and the Spider Queen 3 times], and we'll break through for good.",
			},
			reminder = { "The caverns still aren't safe. Bats, golems, and the Queen herself." },
			complete = {
				"We're through, and my crew's safe on the other side!",
				"They dug this up down there. A diamond pickaxe. It's yours, partner.",
			},
		},
	} :: { Step },
}

Quests.lines = lines
-- the order lines are checked in (the tracker's fallback when the player's
-- world has nothing to show)
Quests.order = { "DaleFarm", "RangerRedwoods", "ExplorerCaverns" }

function Quests.get(id: any): Line?
	return if type(id) == "string" then lines[id] else nil
end

-- The player attribute a line's field is published on: Quests.attr("Step",
-- "DaleFarm") -> "QuestStep_DaleFarm". Fields: Step, State, Progress (server),
-- and ShownState (client-only, the state as the tracker shows it).
function Quests.attr(field: string, id: string): string
	return ("Quest%s_%s"):format(field, id)
end

-- Which line the tracker and guide arrow follow (client): the line of the world
-- the player stands in (its "CurrentWorld" attribute, set by WorldBannerUI) if
-- that line has a step under way (Active / Ready), otherwise the first line in
-- `order` that has one. Nil when nothing is under way.
function Quests.tracked(player: Player): Line?
	local function busy(line: Line): boolean
		local state = player:GetAttribute(Quests.attr("State", line.id))
		return state == "Active" or state == "Ready"
	end
	local world = player:GetAttribute("CurrentWorld")
	for _, id in Quests.order do
		local line = lines[id]
		if line and line.world == world and busy(line) then
			return line
		end
	end
	for _, id in Quests.order do
		local line = lines[id]
		if line and busy(line) then
			return line
		end
	end
	return nil
end

-- How much progress finishes a step.
function Quests.goal(step: Step): number
	if step.kind == "kill" or step.kind == "gather" then
		return step.count or 1
	elseif step.kind == "level" then
		return step.level or 1
	elseif step.kind == "bring" or step.kind == "hunt" then
		local total = 0
		for _, item in (if step.kind == "hunt" then step.targets else step.items) or {} do
			total += item.count
		end
		return math.max(total, 1)
	end
	return step.amount or 1
end

-- What a hunt or bring step's icon shows (2026-10-26, the user: the stronger enemy, then the
-- next as each is done): the toughest enemy still short (the most health; a boss over its
-- elite and so on), or for a bring step the rarest material still short. Once all are met,
-- the toughest / rarest of all. `held` is the player's material counts (Materials.counts),
-- `kills` the hunt's kills (Quests.huntKills). Returns the Config/Worlds or Config/Materials id.
function Quests.focus(step: Step, kills: { [string]: number }?, held: { [string]: number }?): string?
	local list = if step.kind == "hunt" then step.targets elseif step.kind == "bring" then step.items else nil
	if not list or #list == 0 then
		return nil
	end
	local function weight(id: string): number
		if step.kind == "hunt" then
			local def = Enemies.get(id)
			return def and def.hp or 0
		end
		local def = Materials.get(id)
		return if def then (table.find(Weapons.Rarities, def.rarity) or 0) else 0
	end
	local have = if step.kind == "hunt" then kills or {} else held or {}
	local best, bestWeight = nil, -math.huge
	local top, topWeight = nil, -math.huge
	for _, item in list do
		local w = weight(item.id)
		if w > topWeight then
			top, topWeight = item.id, w
		end
		if (have[item.id] or 0) < item.count and w > bestWeight then
			best, bestWeight = item.id, w
		end
	end
	return best or top
end

-- A hunt step's kills so far, per enemy (from the "QuestKills_<line>" attribute).
function Quests.huntKills(player: Player, lineId: string): { [string]: number }
	local out: { [string]: number } = {}
	local raw = player:GetAttribute(Quests.attr("Kills", lineId))
	if type(raw) == "string" then
		for id, n in raw:gmatch("(%w+)=(%d+)") do
			out[id] = tonumber(n) or 0
		end
	end
	return out
end

-- The material a gather / bring step is about (its icon on the dialogue and tracker).
function Quests.material(step: Step): string?
	if step.kind == "gather" then
		return step.target
	elseif step.kind == "bring" then
		local first = step.items and step.items[1]
		return first and first.id
	end
	return nil
end

-- The offer lines for a step: its offerHasTool lines when it has them and the player
-- already owns the tool its material needs (issue 21), else its offer.
function Quests.offerLines(step: Step, player: Player): { string }
	if step.offerHasTool and Quests.toolNeeded(step, player) == nil then
		return step.offerHasTool
	end
	return step.offer
end

-- The tool a gather / bring step still needs before its material can be gathered (see
-- the header): the lowest tier of the node's tool kind that can break it, or nil once
-- the player owns one as good (or the material isn't from a node, like Fox Fur). A
-- bring step only asks about the items still short.
function Quests.toolNeeded(step: Step, player: Player): Tools.ToolDef?
	local ids: { string } = {}
	if step.kind == "gather" and step.target then
		ids = { step.target }
	elseif step.kind == "bring" then
		local held = player:GetAttribute("Materials")
		for _, item in step.items or {} do
			local n = if type(held) == "string" then tonumber(held:match("%f[%w]" .. item.id .. "=(%d+)") or "0") else 0
			if (n or 0) < item.count then
				table.insert(ids, item.id)
			end
		end
	end
	local owned = Tools.owned(player)
	for _, id in ids do
		for _, node in Gathering.Nodes do
			for _, drop in node.drops do
				if drop.id == id then
					local best = Tools.bestOf(owned, node.tool)
					if best == nil or best.tier < node.tier then
						local pick: Tools.ToolDef? = nil
						for _, def in Tools.Defs do
							if def.kind == node.tool and def.tier >= node.tier and (pick == nil or def.tier < pick.tier) then
								pick = def
							end
						end
						return pick
					end
				end
			end
		end
	end
	return nil
end

-- The tools the player's quests are waiting on (each line on an Active step still
-- missing its tool, Quests.toolNeeded): tool id -> the giver's short name, for the
-- Weaponsmith's quest highlight (issue 21).
function Quests.shopNeeds(player: Player): { [string]: string }
	local needs: { [string]: string } = {}
	for _, id in Quests.order do
		local line = Quests.get(id)
		local index = player:GetAttribute(Quests.attr("Step", id))
		local step = if line and type(index) == "number" then line.steps[index] else nil
		if line and step and player:GetAttribute(Quests.attr("State", id)) == "Active" then
			local tool = Quests.toolNeeded(step, player)
			if tool and not needs[tool.id] then
				needs[tool.id] = line.npc.short
			end
		end
	end
	return needs
end

return Quests
