return {
	{
		name = "missions", 
		control = WG.MissionHandler.GetControl(),
	},
	{
		name = "campaign",
		submenuData = {
			submenuControl = WG.CampaignHandler.GetControl(),
			tabs = {
				{
					name = "technology", 
					control = Control:New {},
				},
				{
					name = "codex", 
					control = WG.CodexHandler.GetControl(),
				},
				{
					name = "options", 
					control = Control:New {},
				},
			},
		},
	},
	{
		name = "skirmish", 
		control = WG.BattleRoomWindow.GetSingleplayerControl(VFS.Include(LUA_DIRNAME .. "configs/gameConfig/zk/singleplayerQuickSkirmish.lua")),
		entryCheck = WG.BattleRoomWindow.SetSingleplayerGame,
	},
	{
		name = "load",
		control = WG.LoadGameWindow.GetControl(),
		entryCheck = WG.BattleRoomWindow.SetSingleplayerGame,
	},
	{
		name = "commanders",
		control = WG.CommConfig.GetControl(),
		entryCheck = WG.BattleRoomWindow.SetSingleplayerGame,
	},
	--{
	--	name = "quick_start", 
	--	control = Control:New {},
	--},
}
