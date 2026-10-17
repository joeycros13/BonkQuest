--!strict
-- ChatTagController: the gold [VIP] tag in front of a VIP player's chat
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

function ChatTagController.init(_injected: any) end

function ChatTagController.start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[ChatTagController] TextChatService.ChatVersion is legacy chat; set it to TextChatService for the [VIP] tag")
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		local speaker = source and Players:GetPlayerByUserId(source.UserId)
		if not (speaker and speaker:GetAttribute("VIP") == true) then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = TAG .. message.PrefixText
		return properties
	end
end

return ChatTagController
