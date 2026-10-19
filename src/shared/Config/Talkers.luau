--!strict
-- Talkers: NPCs you talk to who don't give a questline (2026-10-18; Finn the fisherman
-- first). A talker is a model tagged "Talker" (MapLayout.Tags.Talker) whose TalkerId
-- attribute names one of the defs below. QuestController runs the conversation with the
-- same Talk prompt, camera shot and dialogue card as the quest givers.
--
--   npc    name (the card), short ("Talk to <short>"), portrait (the card's photo; "" = none yet)
--   talk   fn(player) -> { lines, tag?, later }: what they say right now, from the player's
--          state. In lines, [...] is the bold red highlight, as in Config/Quests.

local Tools = require(script.Parent.Tools)

local Talkers = {}

export type Talk = { lines: { string }, tag: string?, later: string }
export type Def = {
	id: string,
	npc: { name: string, short: string, portrait: string },
	talk: (player: Player) -> Talk,
}

local function owns(player: Player, kind: string): boolean
	return Tools.bestOf(Tools.owned(player), kind) ~= nil
end

Talkers.Defs = {
	-- Finn, at the World 1 fishing hut. A tutorial only (user, 2026-10-18): rods are bought
	-- from the shopkeeper, and without one he sends you to buy it.
	Fisherman = {
		id = "Fisherman",
		npc = { name = "Finn", short = "Finn", portrait = "" },
		talk = function(player: Player): Talk
			if not owns(player, "Rod") then
				return {
					tag = "Fishing",
					later = "Will do",
					lines = {
						"Ahoy there! Name's Finn. I've been fishing this pond longer than that windmill's been turning.",
						"Fancy catching a few yourself? You'll need a [Fishing Rod] first.",
						"The shopkeeper up at the plaza sells them. Grab one and come see me, and I'll show you the ropes.",
					},
				}
			end
			local slot = Tools.slotOf("Rod") or 5
			return {
				tag = "Fishing Lesson",
				later = "Thanks, Finn!",
				lines = {
					"Ah, you've got yourself a rod! Let me show you how it's done.",
					("Press [%d] to take it out. You can fish anywhere along the water, but the end of my pier's the best spot."):format(slot),
					"Click to cast your line, and keep an eye on the bobber.",
					"When a fish pulls it under and a [!] pops up, click quick to hook it! Wait too long and it lets go.",
					"Then a ring closes in. Click while it's inside the [green zone], [3 times in a row]. Miss one and the fish gets away. The rare ones fight harder!",
				},
			}
		end,
	},
} :: { [string]: Def }

function Talkers.get(id: any): Def?
	return if type(id) == "string" then Talkers.Defs[id] else nil
end

return Talkers
