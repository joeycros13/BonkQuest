--!strict
-- ChatTagController: the gold [VIP] tag (and a leaderboard reward's blue tag, e.g.
-- [#1 Daily Kills], 2026-10-19) in front of a player's chat
-- messages (the VIP gamepass, ShopService publishes the player's "VIP"
-- attribute).
--
-- Uses TextChatService.OnIncomingMessage, so TextChatService.ChatVersion must
-- be TextChatService (set in Studio's Properties; scripts can't change it).
-- The tag's look is the TAG string below (Luckiest Guy, like the game's titles).
-- The chat's own look (Fredoka text with a dark outline, teal window and input
-- bar, cream bubbles, Luckiest Guy tabs) is set on TextChatService's
-- ChatWindowConfiguration / ChatInputBarConfiguration /
-- BubbleChatConfiguration / ChannelTabsConfiguration in Studio.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTagController = {}

local TAG = '<font face="LuckiestGuy" color="#FFC83D">[VIP]</font> '
-- a leaderboard reward's tag (LeaderboardService's "LeaderTag" attribute, until the next reset)
local LEADER_TAG = '<font face="LuckiestGuy" color="#7FD3FF">[%s]</font> '
local REWARD_FORMAT = '<font color="#FFD23F">%s</font>'

local deps: any = nil

function ChatTagController.init(injected: any)
	deps = injected
end

function ChatTagController.start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[ChatTagController] TextChatService.ChatVersion is legacy chat; set it to TextChatService for the [VIP] tag")
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		local speaker = source and Players:GetPlayerByUserId(source.UserId)
		if not speaker then
			return nil
		end
		local leader = speaker:GetAttribute("LeaderTag")
		local vip = speaker:GetAttribute("VIP") == true
		if not (vip or type(leader) == "string") then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = (if type(leader) == "string" then LEADER_TAG:format(leader) else "") .. (if vip then TAG else "") .. message.PrefixText
		return properties
	end
	-- "You finished #1 on the Daily Kills board! Rewards: ..." in the chat
	deps.Remotes.getEvent("LeaderboardReward").OnClientEvent:Connect(function(event: any)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") and type(event) == "table" and type(event.text) == "string" then
			general:DisplaySystemMessage(REWARD_FORMAT:format(event.text))
		end
	end)
end

return ChatTagController
