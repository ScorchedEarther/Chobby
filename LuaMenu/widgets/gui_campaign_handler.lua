--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "Campaign Handler",
		desc      = "Explore the galaxy",
		author    = "GoogleFrog",
		date      = "25 Jan 2017",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true  --  loaded by default?
	}
end

local GALAXY_IMAGE = LUA_DIRNAME .. "images/heic1403aDowngrade.jpg"
local IMAGE_BOUNDS = {
	x = 810/4000,
	y = 710/2602,
	width = 2400/4000,
	height = 1500/2602,
}

local TRANSFORM_BOUNDS = {
	left = -0.03,
	top = 0,
	right = 1,
	bottom = 1,
}

local difficultyNameMap = {
	[0] = "Unknown",
	[1] = "Easy",
	[2] = "Normal",
	[3] = "Hard",
	[4] = "Brutal",
}

local edgeDrawList = 0
local planetConfig, planetAdjacency, planetEdgeList

local ACTIVE_COLOR = {0,1,0,0.75}
local INACTIVE_COLOR = {0.2, 0.2, 0.2, 0.75}
local HIDDEN_COLOR = {0.2, 0.2, 0.2, 0}

local PLANET_START_COLOR = {1, 1, 1, 1}
local PLANET_NO_START_COLOR = {0.5, 0.5, 0.5, 1}

local TARGET_IMAGE = LUA_DIRNAME .. "images/niceCircle.png"

local REWARD_ICON_SIZE = 58
local DEBUG_UNLOCKS_SIZE = 26
local DEBUG_UNLOCK_COLUMNS = 4

local VISIBILITY_DISTANCE = 2 -- Distance from captured at which planets are visible.

local LIVE_TESTING
local PLANET_WHITELIST
local PLANET_COUNT = 0

local debugPlanetSelected, debugPlanetSelectedName

local planetHandler
local planetList
local selectedPlanet
local currentWinPopup

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Edge Drawing

local function IsEdgeVisible(p1, p2)
	if PLANET_WHITELIST and ((not PLANET_WHITELIST[p1]) or (not PLANET_WHITELIST[p2])) then
		return false
	end
	return (planetList[p1] and planetList[p1].GetVisible()) or (planetList[p2] and planetList[p2].GetVisible())
end

local function DrawEdgeLines()
	for i = 1, #planetEdgeList do
		if IsEdgeVisible(planetEdgeList[i][1], planetEdgeList[i][2]) then
			for p = 1, 2 do
				local pid = planetEdgeList[i][p]
				local planetData = planetList[pid]
				local hidden = not (planetData and planetData.GetVisible()) -- Note that planets not in the whitelist have planetData = nil
				local x, y = planetHandler.GetZoomTransform(planetConfig[pid].mapDisplay.x, planetConfig[pid].mapDisplay.y)
				gl.Color((hidden and HIDDEN_COLOR) or (planetData.GetCaptured() and ACTIVE_COLOR) or INACTIVE_COLOR)
				gl.Vertex(x, y)
			end
		end
	end
end

local function CreateEdgeList()
	gl.BeginEnd(GL.LINES, DrawEdgeLines)
end

local function UpdateEdgeList()
	gl.DeleteList(edgeDrawList)
	edgeDrawList = gl.CreateList(CreateEdgeList)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Feedback/testing warning window

local function MakeFeedbackWindow(parent, feedbackLink)
	local Configuration = WG.Chobby.Configuration
	
	local holder = Control:New {
		right = 60,
		y = 40,
		width = 390,
		height = 240,
		padding = {0,0,0,0},
		parent = parent,
	}
	
	local textWindow = Window:New{
		classname = "main_window_small",
		x = 0,
		y = 0,
		right = 0,
		bottom = 0,
		resizable = false,
		draggable = false,
		parent = holder,
	}
	
	TextBox:New {
		x = 55,
		right = 15,
		y = 15,
		height = 35,
		text = "Campaign Testing",
		fontsize = Configuration:GetFont(4).size,
		parent = textWindow,
	}
	TextBox:New {
		x = 15,
		right = 15,
		y = 58,
		height = 35,
		lineSpacing = 1,
		text = "Welcome to the alpha test of the Zero-K campaign. New missions will be released every Sunday. Please post your thoughts, feedback and issues on the forum.",
		fontsize = Configuration:GetFont(2).size,
		parent = textWindow,
	}
	
	Button:New {
		x = 95,
		right = 95,
		bottom = 12,
		height = 45,
		caption = "Post Feedback",
		classname = "action_button",
		font = WG.Chobby.Configuration:GetFont(3),
		OnClick = {
			function ()
				WG.WrapperLoopback.OpenUrl(feedbackLink)
			end
		},
		parent = textWindow,
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Save planet positions

local function EchoPlanetPositionAndEdges()
	Spring.Echo("planetEdgeList = {")
	for i = 1, #planetEdgeList do
		Spring.Echo(string.format("\t{%02d, %02d},", planetEdgeList[i][1], planetEdgeList[i][2]))
	end
	Spring.Echo("}")
	Spring.Echo("planetPositions = {")
	for i = 1, #planetConfig do
		Spring.Echo(string.format("\t[%01d] = {%03f, %03f},", i, math.floor(planetConfig[i].mapDisplay.x*1000), math.floor(planetConfig[i].mapDisplay.y*1000)))
	end
	Spring.Echo("}")
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Rewards panels

local function MakeRewardList(holder, bottom, name, rewardsTypes, cullUnlocked, widthMult, stackHeight)
	if (not rewardsTypes) or #rewardsTypes == 0 then
		return false
	end
	
	local Configuration = WG.Chobby.Configuration
	
	widthMult = widthMult or 1
	stackHeight = stackHeight or 1
	
	local scroll, rewardsHolder
	
	local position = 0
	for t = 1, #rewardsTypes do
		local rewardList, tooltipFunction, alreadyUnlockedCheck,  overrideTooltip = rewardsTypes[t][1], rewardsTypes[t][2], rewardsTypes[t][3], rewardsTypes[t][4]
		if rewardList then
			for i = 1, #rewardList do
				local alreadyUnlocked = alreadyUnlockedCheck(rewardList[i])
				if not (cullUnlocked and alreadyUnlocked) then
					if not rewardsHolder then
						rewardsHolder = Control:New {
							x = 10,
							right = 10,
							bottom = bottom,
							height = 94,
							padding = {0, 0, 0, 0},
							parent = holder,
						}
						
						TextBox:New {
							x = 4,
							y = 2,
							right = 4,
							height = 30,
							text = name,
							font = Configuration:GetFont(2),
							parent = rewardsHolder
						}
						
						scroll = ScrollPanel:New {
							classname = "scrollpanel_borderless",
							x = 3,
							y = 18,
							right = 3,
							bottom = 2,
							scrollbarSize = 12,
							padding = {0, 0, 0, 0},
							parent = rewardsHolder,
						}
					end
					
					local info, imageFile, imageOverlay, count = tooltipFunction(rewardList[i])
					
					local x, y = (REWARD_ICON_SIZE*widthMult + 4)*math.floor(position/stackHeight), (position%stackHeight)*REWARD_ICON_SIZE/stackHeight
					if imageFile then
						local color = nil
						local statusString = ""
						if alreadyUnlocked then
							statusString = " (already unlocked)"
						elseif cullUnlocked then
							statusString = " (newly unlocked)"
						else
							color = {0.5, 0.5, 0.5, 0.5}
						end
						local tooltip = (overrideTooltip and info) or ((info.humanName or "???") .. statusString .. "\n " .. (info.description or ""))
						
						local image = Image:New{
							x = x,
							y = y,
							width = REWARD_ICON_SIZE*widthMult,
							height = REWARD_ICON_SIZE/stackHeight,
							keepAspect = true,
							color = color,
							tooltip = string.gsub(tooltip, "_COUNT_", ""),
							file = imageOverlay or imageFile,
							file2 = imageOverlay and imageFile,
							parent = scroll,
						}
						if count then
							Label:New {
								x = 2,
								y = "50%",
								right = 4,
								bottom = 6,
								align = "right",
								fontsize = Configuration:GetFont(3).size,
								caption = count,
								parent = image,
							}
						end
						function image:HitTest(x,y) return self end
					else
						local tooltip = (overrideTooltip and info) or (info.name or "???")
						
						Button:New {
							x = x,
							y = y,
							width = REWARD_ICON_SIZE*widthMult,
							height = REWARD_ICON_SIZE/stackHeight,
							caption = string.gsub(tooltip, "_COUNT_", ""),
							font = Configuration:GetFont(2),
							parent = scroll
						}
					end
					
					position = position + 1
				end
			end
		end
	end
	
	return (rewardsHolder and true) or false
end

local function MakeBonusObjectiveLine(parent, bottom, planetData, bonusObjectiveSuccess, difficulty)

	local objectiveConfig = planetData.gameConfig.bonusObjectiveConfig
	if not objectiveConfig then
		return bottom
	end
	
	local difficultyName = difficultyNameMap[difficulty or 0]
	
	if bonusObjectiveSuccess then
		local function IsObjectiveUnlocked(objectiveID)
			return bonusObjectiveSuccess[objectiveID]
		end
		local function GetObjectiveInfo(objectiveID)
			local tooltip = objectiveConfig[objectiveID].description
			local complete, oldDifficulty = WG.CampaignData.GetBonusObjectiveComplete(planetData.index, objectiveID)
			if complete then
				if bonusObjectiveSuccess[objectiveID] and ((difficulty or 0) > (oldDifficulty or 0)) then
					tooltip = tooltip .. " \n(Improved difficulty from " .. difficultyNameMap[oldDifficulty or 0] .. " to " .. difficultyName .. ")"
				else
					tooltip = tooltip .. " \n(Previously complete on " .. difficultyNameMap[oldDifficulty or 0] .. ")"
				end
			elseif bonusObjectiveSuccess[objectiveID] then
				tooltip = tooltip .. " \n(Newly completed on " .. difficultyName .. ")"
			else
				tooltip = tooltip .. " \n(Incomplete)"
			end 
			return tooltip, objectiveConfig[objectiveID].image, objectiveConfig[objectiveID].imageOverlay
		end
		local objectiveList = {}
		for i = 1, #objectiveConfig do
			objectiveList[i] = i
		end
		if MakeRewardList(parent, bottom, "Bonus Objectives", {{objectiveList, GetObjectiveInfo, IsObjectiveUnlocked, true}}, false) then
			return bottom + 98
		end
	else
		local function IsObjectiveUnlocked(objectiveID)
			return WG.CampaignData.GetBonusObjectiveComplete(planetData.index, objectiveID)
		end
		local function GetObjectiveInfo(objectiveID)
			local complete, oldDifficulty = WG.CampaignData.GetBonusObjectiveComplete(planetData.index, objectiveID)
			local tooltip = objectiveConfig[objectiveID].description
			if complete then
				tooltip = tooltip .. "\nHighest difficulty: " .. difficultyNameMap[oldDifficulty or 0]
			end
			return tooltip, objectiveConfig[objectiveID].image, objectiveConfig[objectiveID].imageOverlay
		end
		local objectiveList = {}
		for i = 1, #objectiveConfig do
			objectiveList[i] = i
		end
		if MakeRewardList(parent, bottom, "Bonus Objectives", {{objectiveList, GetObjectiveInfo, IsObjectiveUnlocked, true}}, false) then
			return bottom + 98
		end
	end
	
	return bottom
end

local function MakeRewardsPanel(parent, planetData, cullUnlocked, showCodex, bonusObjectiveSuccess, difficulty)
	local bottom = 82
	
	rewards = planetData.completionReward
	
	if showCodex then
		if MakeRewardList(parent, bottom, "Codex", {{rewards.codexEntries, WG.CampaignData.GetCodexEntryInfo, WG.CampaignData.GetCodexEntryIsUnlocked}}, cullUnlocked, 3.96, 2) then
			bottom = bottom + 98
		end
	end
	
	local unlockRewards = {
		{rewards.units, WG.CampaignData.GetUnitInfo, WG.CampaignData.GetUnitIsUnlocked},
		{rewards.modules, WG.CampaignData.GetModuleInfo, WG.CampaignData.GetModuleIsUnlocked},
		{rewards.abilities, WG.CampaignData.GetAbilityInfo, WG.CampaignData.GetAbilityIsUnlocked}
	}
	
	if MakeRewardList(parent, bottom, "Unlocks", unlockRewards, cullUnlocked) then
		bottom = bottom + 98
	end
	
	bottom = MakeBonusObjectiveLine(parent, bottom, planetData, bonusObjectiveSuccess, difficulty)
	
	return bottom
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Zooming

local windowX, windowY, windowWidth, windowHeight
local function RepositionBackgroundAndPlanets(newX, newY, newWidth, newHeight)
	windowX = newX or windowX
	windowY = newY or windowY
	windowWidth = newWidth or windowWidth
	windowHeight = newHeight or windowHeight
	
	planetHandler.UpdateVisiblePlanetBounds()
	
	local tX, tY, tScale = planetHandler.GetZoomTransformValues()
	local transformedImageBounds = {
		x = IMAGE_BOUNDS.x + tX*IMAGE_BOUNDS.width,
		y = IMAGE_BOUNDS.y + tY*IMAGE_BOUNDS.height,
		width = IMAGE_BOUNDS.width/tScale,
		height = IMAGE_BOUNDS.height/tScale,
	}
	
	local background = WG.Chobby.interfaceRoot.GetBackgroundHolder()
	background:SetBoundOverride(transformedImageBounds)
	
	local x, y, width, height = background:ResizeAspectWindow(windowX, windowY, windowWidth, windowHeight)
	planetHandler.UpdatePosition(x, y, width, height)
	UpdateEdgeList()
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Planet capturing

local function MakeWinPopup(planetData, bonusObjectiveSuccess, difficulty)
	local victoryWindow = Window:New {
		caption = "",
		name = "victoryWindow",
		parent = WG.Chobby.lobbyInterfaceHolder,
		width = 520,
		height = 560,
		resizable = false,
		draggable = false,
		classname = "main_window",
	}
	
	local childWidth = victoryWindow.width - victoryWindow.padding[1] - victoryWindow.padding[3]
	
	Label:New {
		x = 0,
		y = 6,
		width = childWidth,
		height = 30,
		align = "center",
		caption = "Victory on " .. planetData.name .. "!",
		font = WG.Chobby.Configuration:GetFont(4),
		parent = victoryWindow
	}
	
	local experienceHolder = Control:New {
		x = 20,
		y = 58,
		right = 20,
		height = 100,
		padding = {0, 0, 0, 0},
		parent = victoryWindow,
	}
	
	local experienceDisplay = WG.CommanderHandler.GetExperienceDisplay(experienceHolder, 38, true)
	
	local rewardsHeight = MakeRewardsPanel(victoryWindow, planetData, true, true, bonusObjectiveSuccess, difficulty)
	
	victoryWindow:SetPos(nil, nil, nil, 200 + rewardsHeight)
	
	local function CloseFunc()
		victoryWindow:Dispose()
	end
	
	local buttonClose = Button:New {
		x = (childWidth - 136)/2,
		width = 136,
		bottom = 1,
		height = 70,
		caption = i18n("continue"),
		font = WG.Chobby.Configuration:GetFont(3),
		parent = victoryWindow,
		classname = "negative_button",
		OnClick = {
			function()
				CloseFunc()
			end
		},
	}
	
	local popupHolder = WG.Chobby.PriorityPopup(victoryWindow, CloseFunc, CloseFunc)
	
	local externalFunctions = {}
	
	function externalFunctions.UpdateExperience(oldExperience, oldLevel, newExperience, newLevel, gainedBonusExperience)
		experienceDisplay.AddFancyExperience(newExperience - oldExperience, gainedBonusExperience)
	end
	
	return externalFunctions
end

local function MakeRandomBonusVictoryList(winChance, length)
	local list = {}
	for i = 1, length do
		list[i] = (math.random() < winChance)
	end
	return list
end

local function MakeBonusObjectivesList(bonusObjectivesString)
	if not bonusObjectivesString then
		return false
	end
	local list = {}
	local length = string.len(bonusObjectivesString)
	for i = 1, length do
		list[i] = (string.sub(bonusObjectivesString, i, i) == "1")
	end
	return list
end

local function ProcessPlanetVictory(planetID, battleFrames, bonusObjectives, bonusObjectiveString, difficulty)
	if not planetID then
		Spring.Echo("ProcessPlanetVictory error")
		return
	end
	if selectedPlanet then
		selectedPlanet.Close()
		selectedPlanet = nil
	end
	-- It is important to popup before capturing the planet to filter out the
	-- already unlocked rewards.
	currentWinPopup = MakeWinPopup(planetConfig[planetID], bonusObjectives, difficulty)
	WG.CampaignData.AddPlayTime(battleFrames)
	WG.CampaignData.CapturePlanet(planetID, bonusObjectives, difficulty)
	
	WG.Analytics.SendIndexedRepeatEvent("campaign:planet_" .. planetID .. ":difficulty_" .. difficulty .. ":win", math.floor(battleFrames/30), ":bonus_" .. (bonusObjectiveString or ""))
	WG.Analytics.SendOnetimeEvent("campaign:planets_owned_" .. WG.CampaignData.GetCapturedPlanetCount(), math.floor(WG.CampaignData.GetPlayTime()/30))
end

local function ProcessPlanetDefeat(planetID, battleFrames)
	if selectedPlanet then
		selectedPlanet.Close()
		selectedPlanet = nil
	end
	WG.Chobby.InformationPopup("Battle for " .. planetConfig[planetID].name .. " lost.", nil, nil, "Defeat")
	WG.CampaignData.AddPlayTime(battleFrames, true)
	
	WG.Analytics.SendIndexedRepeatEvent("campaign:planet_" .. planetID .. ":difficulty_" .. WG.CampaignData.GetDifficultySetting() .. ":lose", math.floor(battleFrames/30), ":defeat")
end

local function ProcessPlanetResign(planetID, battleFrames)
	WG.CampaignData.AddPlayTime(battleFrames, true)
	WG.Analytics.SendIndexedRepeatEvent("campaign:planet_" .. planetID .. ":difficulty_" .. WG.CampaignData.GetDifficultySetting() .. ":lose", math.floor(battleFrames/30), ":resign")
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- TODO: use shader animation to ease info panel in

local function SelectPlanet(planetHandler, planetID, planetData, startable)
	local Configuration = WG.Chobby.Configuration

	WG.Chobby.interfaceRoot.GetRightPanelHandler().CloseTabs()
	WG.Chobby.interfaceRoot.GetMainWindowHandler().CloseTabs()
	
	local starmapInfoPanel = Window:New{
		classname = "main_window",
		parent = planetHandler,
		x = 32,
		y = 32,
		right = 32,
		bottom = 32,
		resizable = false,
		draggable = false,
		padding = {12, 7, 12, 7},
	}
	
	local planetName = string.upper(planetData.name)
	if not LIVE_TESTING then
		planetName = planetName .. " - " .. planetID
	end
	
	local subPanel = Panel:New{
		parent = starmapInfoPanel,
		x = "50%",
		y = "10%",
		right = "5%",
		bottom = "5%",
		children = {
			-- title
			Label:New{
				x = 8,
				y = 12,
				caption = planetName,
				font = Configuration:GetFont(4),
			},
			-- grid of details
			Grid:New{
				x = 8,
				y = 60,
				right = 4,
				bottom = "72%",
				columns = 2,
				rows = 2,
				children = {
					Label:New{caption = "Primary", font = Configuration:GetFont(3)},
					Label:New{caption = planetData.infoDisplay.primary .. " (" .. planetData.infoDisplay.primaryType .. ") ", font = Configuration:GetFont(3)},
					Label:New{caption = "Type", font = Configuration:GetFont(3)},
					Label:New{caption = planetData.infoDisplay.terrainType or "<UNKNOWN>", font = Configuration:GetFont(3)},
					--Label:New{caption = "Radius", font = Configuration:GetFont(3)},
					--Label:New{caption = planetData.infoDisplay.radius or "<UNKNOWN>", font = Configuration:GetFont(3)},
					--Label:New{caption = "Military rating", font = Configuration:GetFont(3)},
					--Label:New{caption = tostring(planetData.infoDisplay.milRating or "<UNKNOWN>"), font = Configuration:GetFont(3)},
				},
			},
			-- desc text
			TextBox:New {
				x = 8,
				y = "30%",
				right = 4,
				bottom = "25%",
				text = planetData.infoDisplay.text,
				font = Configuration:GetFont(3),
			},
		}
	}
	
	MakeRewardsPanel(subPanel, planetData)
	
	if startable then
		local startButton = Button:New{
			right = 10,
			bottom = 10,
			width = 135,
			height = 70,
			classname = "action_button",
			parent = subPanel,
			caption = i18n("start"),
			font = Configuration:GetFont(4),
			OnClick = {
				function(self)
					WG.PlanetBattleHandler.StartBattle(planetID, planetData)
				end
			}
		}
		
		if (not LIVE_TESTING) and (Configuration.debugAutoWin or Configuration.debugMode) then
			local autoWinButton = Button:New{
				right = 150,
				bottom = 10,
				width = 150,
				height = 70,
				classname = "action_button",
				parent = subPanel,
				caption = "Auto Win",
				font = Configuration:GetFont(4),
				OnClick = {
					function(self)
						ProcessPlanetVictory(planetID, 352, MakeRandomBonusVictoryList(0.75, 8), nil, WG.CampaignData.GetDifficultySetting())
					end
				}
			}
			local autoLostButton = Button:New{
				right = 305,
				bottom = 10,
				width = 175,
				height = 70,
				classname = "action_button",
				parent = subPanel,
				caption = "Auto Lose",
				font = Configuration:GetFont(4),
				OnClick = {
					function(self)
						ProcessPlanetDefeat(planetID, 351)
					end
				}
			}
		end
	end
	
	-- close button
	local function CloseFunc()
		if starmapInfoPanel then
			starmapInfoPanel:Dispose() 
			starmapInfoPanel = nil
			return true
		end
		return false
	end
	
	Button:New{
		parent = starmapInfoPanel,
		y = 3,
		right = 3,
		width = 80,
		height = 45,
		classname = "negative_button",
		caption = i18n("close"),
		font = Configuration:GetFont(3),
		OnClick = {
			CloseFunc
		},
	}
	
	WG.Chobby.interfaceRoot.SetBackgroundCloseListener(CloseFunc)
	
	-- list of missions on this planet
	--local missionsStack = StackPanel:New {
	--	parent = starmapInfoPanel,
	--	orientation = "vertical",
	--	x = 4,
	--	right = 4,
	--	height = "25%",
	--	bottom = 0,
	--	resizeItems = false,
	--	autoArrangeV = false,
	--}
	--for i=1,#planetDef.missions do
	--end
	
	-- planet image
	local planetImage = Image:New{
		parent = starmapInfoPanel,
		x = 0,
		right = "50%",
		y = (starmapInfoPanel.height - planetData.infoDisplay.size) / 2,
		height = planetData.infoDisplay.size,
		keepAspect = true,
		file = planetData.infoDisplay.image,
	}
	
	-- background
	local bg = Image:New{
		parent = starmapInfoPanel,
		x = 0,
		y = 0,
		right = 0,
		bottom = 0,
		file = planetData.infoDisplay.backgroundImage,
		keepAspect = false,
	}
	-- force offscreen position
	--local overflowX = (starmapInfoPanel.width - starmapInfoPanel.width) / 2
	--local overflowY = (starmapInfoPanel.width - starmapInfoPanel.height) / 2
	--bg.x = -overflowX
	--bg.y = -overflowY
	bg:Invalidate()
	
	starmapInfoPanel:SetLayer(1)
	
	starmapInfoPanel.OnResize = starmapInfoPanel.OnResize or {}
	starmapInfoPanel.OnResize[#starmapInfoPanel.OnResize + 1] = function(obj, xSize, ySize)
		planetImage:SetPos(nil, math.floor((ySize - planetData.infoDisplay.size)/2))
	end
	
	local externalFunctions = {}
	
	externalFunctions.Close = CloseFunc
	
	return externalFunctions
end

local function AddDebugUnlocks(parent, unlockList, unlockInfo, offset)
	if unlockList then
		for i = 1, #unlockList do
			local info, imageFile, imageOverlay, count = unlockInfo(unlockList[i])
			local image = Image:New{
				x = (offset%DEBUG_UNLOCK_COLUMNS) * DEBUG_UNLOCKS_SIZE,
				y = math.floor(offset/DEBUG_UNLOCK_COLUMNS) * DEBUG_UNLOCKS_SIZE,
				width = DEBUG_UNLOCKS_SIZE - 1,
				height = DEBUG_UNLOCKS_SIZE - 1,
				keepAspect = true,
				file = imageOverlay or imageFile,
				file2 = imageOverlay and imageFile,
				parent = parent,
			}
			offset = offset + 1
		end
	end
	return offset
end

local function EnablePlanetClick()
	planetClickEnabled = true
end

local function GetPlanet(galaxyHolder, planetID, planetData, adjacency)
	local Configuration = WG.Chobby.Configuration
	
	local planetSize = planetData.mapDisplay.size
	local xPos, yPos = planetData.mapDisplay.x, planetData.mapDisplay.y
	
	local captured = WG.CampaignData.IsPlanetCaptured(planetID)
	local startable
	local visible = false
	local distance = false
	local tipHolder
	
	local target
	local targetSize = math.ceil(math.floor(planetSize*1.35)/2)*2
	local planetOffset = math.floor((targetSize - planetSize)/2)
	
	local planetHolder = Control:New{
		x = 0,
		y = 0,
		width = targetSize,
		height = targetSize,
		padding = {0, 0, 0, 0},
		parent = galaxyHolder,
	}
	
	local debugHolder
	if (not LIVE_TESTING) and Configuration.debugMode and Configuration.showPlanetUnlocks then
		debugHolder = Control:New{
			x = 0,
			y = 0,
			width = targetSize*3,
			height = targetSize,
			padding = {1, 1, 1, 1},
			parent = galaxyHolder,
		}
		
		local rewards = planetData.completionReward
		local offset = 0
		offset = AddDebugUnlocks(debugHolder, rewards.units, WG.CampaignData.GetUnitInfo, offset)
		offset = AddDebugUnlocks(debugHolder, rewards.modules, WG.CampaignData.GetModuleInfo, offset)
		offset = AddDebugUnlocks(debugHolder, rewards.abilities, WG.CampaignData.GetAbilityInfo, offset)
	end
	
	local button = Button:New{
		x = planetOffset,
		y = planetOffset,
		width = planetSize,
		height = planetSize,
		classname = "button_planet",
		caption = "",
		OnClick = { 
			function(self, x, y, mouseButton)
				if (not LIVE_TESTING) and Configuration.editCampaign and Configuration.debugMode then
					if debugPlanetSelected and planetID ~= debugPlanetSelected then
						local adjacent = planetAdjacency[debugPlanetSelected][planetID]
						if adjacent then
							for i = 1, #planetEdgeList do
								local edge = planetEdgeList[i]
								if (edge[1] == planetID and edge[2] == debugPlanetSelected) or (edge[2] == planetID and edge[1] == debugPlanetSelected) then
									table.remove(planetEdgeList, i)
									break
								end
							end
						else
							planetEdgeList[#planetEdgeList + 1] = {planetID, debugPlanetSelected}
						end
						
						planetAdjacency[debugPlanetSelected][planetID] = not adjacent
						planetAdjacency[planetID][debugPlanetSelected] = not adjacent
						UpdateEdgeList()
						debugPlanetSelectedName = nil
						debugPlanetSelected = nil
						return
					end
					debugPlanetSelectedName = self.name
					debugPlanetSelected = planetID
					return
				end
				
				if selectedPlanet then
					selectedPlanet.Close()
					selectedPlanet = nil
				end
				selectedPlanet = SelectPlanet(galaxyHolder, planetID, planetData, startable)
			end
		},
		parent = planetHolder,
	}
	button:SetVisibility(false)
	
	local image = Image:New {
		x = 3,
		y = 3,
		right = 3,
		bottom = 3,
		file = planetData.mapDisplay.image,
		keepAspect = true,
		parent = button,
	}
	
	if (not LIVE_TESTING) and Configuration.debugMode then
		local number = Label:New {
			x = 3,
			y = 3,
			right = 6,
			bottom = 6,
			align = "center",
			valign = "center",
			caption = planetID,
			font = Configuration:GetFont(3),
			parent = image,
		}
	end
	
	local function UpdateSize(sizeScale)
		planetSize = planetData.mapDisplay.size*sizeScale
		targetSize = math.ceil(math.floor(planetSize*1.35)/2)*2
		planetOffset = math.floor((targetSize - planetSize)/2)
		
		button:SetPos(planetOffset, planetOffset, planetSize, planetSize)
	end
	
	local externalFunctions = {}
	
	function externalFunctions.UpdatePosition(xSize, ySize)
		local tX, tY, tSize = planetHandler.GetZoomTransform(xPos, yPos, math.max(1, xSize/1050))
		UpdateSize(tSize)
		local x = math.max(0, math.min(xSize - targetSize, tX*xSize - targetSize/2))
		local y = math.max(0, math.min(ySize - targetSize, tY*ySize - targetSize/2))
		planetHolder:SetPos(x, y, targetSize, targetSize)
		
		if tipHolder then
			tipHolder:SetPos(x + targetSize, y - 5 + (targetSize - planetData.mapDisplay.hintSize[2])/2)
		end
		
		if debugHolder then
			debugHolder:SetPos(x, y + planetSize, DEBUG_UNLOCK_COLUMNS*DEBUG_UNLOCKS_SIZE + 2, 2*DEBUG_UNLOCKS_SIZE + 2)
		end
	end
	
	function externalFunctions.SetPosition(newX, newY)
		xPos, yPos = newX, newY
		planetConfig[planetID].mapDisplay.x, planetConfig[planetID].mapDisplay.y = newX, newY
		UpdateEdgeList()
	end
	
	
	function externalFunctions.UpdateInformation()
		local bonusCount, maxBonus = 0, 0
		local objectiveConfig = planetData.gameConfig.bonusObjectiveConfig
		if objectiveConfig then
			maxBonus = #objectiveConfig
			for i = 1, #objectiveConfig do
				if WG.CampaignData.GetBonusObjectiveComplete(planetID, i) then
					bonusCount = bonusCount + 1
				end
			end
		end
		local conquerString
		local cap, difficulty = WG.CampaignData.IsPlanetCaptured(planetID)
		if cap then
			conquerString = "Conquered on " .. difficultyNameMap[difficulty or 0] .. "\n"
		end
		button.tooltip = "Planet " .. planetData.name .. "\n" .. (conquerString or "") .. "Bonus objectives: " .. bonusCount .. " / " .. maxBonus
	end
	externalFunctions.UpdateInformation()
	
	function externalFunctions.UpdateStartable(disableStartable)
		captured = WG.CampaignData.IsPlanetCaptured(planetID)
		startable = captured or planetData.startingPlanet
		if not startable then
			for i = 1, #adjacency do
				if adjacency[i] then
					if ((not PLANET_WHITELIST) or PLANET_WHITELIST[i]) and planetList[i].GetCaptured() then
						startable = true
						break
					end
				end
			end
		end
		
		if captured then
			distance = 0
		elseif startable then
			distance = 1
		else
			distance = false
		end
		
		if disableStartable then
			startable = false
		end
		
		if startable then
			image.color = PLANET_START_COLOR
		else
			image.color = PLANET_NO_START_COLOR
		end
		image:Invalidate()
		
		local targetable = startable and not captured
		if target then
			if not targetable then
				target:Dispose()
				target = nil
			end
		elseif targetable then
			target = Image:New{
				x = 0,
				y = 0,
				right = 0,
				bottom = 0,
				file = TARGET_IMAGE,
				keepAspect = true,
				parent = planetHolder,
			}
			target:SendToBack()
		end
		
		if tipHolder then
			if not targetable then
				tipHolder:Dispose()
				tipHolder = nil
			end
		elseif targetable and planetData.mapDisplay.hintText then
			tipHolder = Window:New{
				classname = "main_window_small",
				x = planetHolder.x + planetHolder.width,
				y = planetHolder.y - 5 + (planetHolder.height - planetData.mapDisplay.hintSize[2])/2,
				width = planetData.mapDisplay.hintSize[1],
				height = planetData.mapDisplay.hintSize[2],
				resizable = false,
				draggable = false,
				parent = galaxyHolder,
			}
			TextBox:New {
				x = 12,
				right = 12,
				y = 8,
				bottom = 8,
				font = Configuration:GetFont(4),
				text = planetData.mapDisplay.hintText,
				parent = tipHolder,
			}
		end
		
		externalFunctions.UpdateInformation()
	end
	
	-- Only call this after calling UpdateStartable for all planets. Call at least (VISIBILITY_DISTANCE - 1) times.
	function externalFunctions.UpdateDistance()
		if distance then
			return
		end
		for i = 1, #adjacency do
			if adjacency[i] then
				if ((not PLANET_WHITELIST) or PLANET_WHITELIST[i]) and planetList[i].GetDistance() then
					distance = planetList[i].GetDistance() + 1
					return
				end
			end
		end
	end
	function externalFunctions.UpdateVisible()
		visible = (distance and distance <= VISIBILITY_DISTANCE) or ((not LIVE_TESTING) and Configuration.debugMode)
		button:SetVisibility(visible)
	end
	
	function externalFunctions.DownloadMapIfClose()
		if startable or captured then
			WG.DownloadHandler.MaybeDownloadArchive(planetData.gameConfig.mapName, "map", 2)
			return
		end
		for i = 1, #adjacency do
			if adjacency[i] then
				if ((not PLANET_WHITELIST) or PLANET_WHITELIST[i]) and not planetList[i].GetCapturedOrStarableUnsafe() then
					WG.DownloadHandler.MaybeDownloadArchive(planetData.gameConfig.mapName, "map", 1)
					return
				end
			end
		end
	end
	
	function externalFunctions.GetCaptured()
		return WG.CampaignData.IsPlanetCaptured(planetID)
	end
	
	function externalFunctions.GetCapturedOrStarableUnsafe()
		-- Unsafe because an update may be required before the return value is valid
		return startable or captured
	end
	
	function externalFunctions.GetVisible()
		return visible
	end
	
	function externalFunctions.GetVisibleEdge() -- Whether an edge to this planet is visible.
		return (distance and distance <= (VISIBILITY_DISTANCE + 1)) or ((not LIVE_TESTING) and Configuration.debugMode)
	end
	
	function externalFunctions.GetDistance()
		return distance
	end
	
	return externalFunctions
end

local function UpdateStartableAndVisible()
	for i = 1, PLANET_COUNT do
		if (not PLANET_WHITELIST) or PLANET_WHITELIST[i] then
			planetList[i].UpdateStartable(not WG.CampaignData.GetCampaignInitializationComplete())
		end
	end
	if VISIBILITY_DISTANCE > 2 then
		for i = 1, VISIBILITY_DISTANCE - 1 do
			if (not PLANET_WHITELIST) or PLANET_WHITELIST[i] then
				planetList[i].UpdateDistance()
			end
		end
	end
	for i = 1, PLANET_COUNT do
		if (not PLANET_WHITELIST) or PLANET_WHITELIST[i] then
			planetList[i].UpdateDistance()
			planetList[i].UpdateVisible()
		end
	end
	RepositionBackgroundAndPlanets()
end

local function DownloadNearbyMaps()
	for i = 1, PLANET_COUNT do
		if (not PLANET_WHITELIST) or PLANET_WHITELIST[i] then
			planetList[i].DownloadMapIfClose()
		end
	end
end

local function UpdateGalaxy()
	UpdateStartableAndVisible()
	UpdateEdgeList()
	DownloadNearbyMaps()
end

local function InitializePlanetHandler(parent, newLiveTestingMode, newPlanetWhitelist, feedbackLink)
	LIVE_TESTING = newLiveTestingMode
	PLANET_WHITELIST = newPlanetWhitelist
	
	local Configuration = WG.Chobby.Configuration
	
	local debugMode = Configuration.debugMode and (not LIVE_TESTING)
	
	if feedbackLink then
		MakeFeedbackWindow(parent, feedbackLink)
	end
	
	local window = ((debugMode and Panel) or Control):New {
		name = "planetsHolder",
		padding = {0,0,0,0},
		parent = parent,
	}
	window:BringToFront()
	
	local planetWindow = Control:New {
		name = "planetWindow",
		x = 0,
		y = 0,
		width = "100%",
		height = "100%",
		padding = {0,0,0,0},
		parent = window,
	}
	
	if debugMode then
		planetWindow.OnMouseDown = planetWindow.OnMouseDown or {}
		planetWindow.OnMouseDown[#planetWindow.OnMouseDown + 1] = function(self, x, y, mouseButton) 
			if Configuration.editCampaign and debugPlanetSelected then
				if mouseButton == 3 then
					debugPlanetSelected = nil
					debugPlanetSelectedName = nil
					EchoPlanetPositionAndEdges()
					return true
				end
				local hovered = WG.Chili.Screen0.hoveredControl
				if hovered and (hovered.name == "planetWindow" or hovered.name == debugPlanetSelectedName) then
					planetList[debugPlanetSelected].SetPosition(x/planetWindow.width, y/planetWindow.height)
					planetList[debugPlanetSelected].UpdatePosition(planetWindow.width, planetWindow.height)
				end
			end
			return false
		end
		--function planetWindow:HitTest(x,y) return self end
	end
	
	local planetData = Configuration.campaignConfig.planetDefs
	planetConfig, planetAdjacency, planetEdgeList = planetData.planets, planetData.planetAdjacency, planetData.planetEdgeList
	
	local transX, transY, transScale = 0, 0, 1
	
	planetList = {}
	PLANET_COUNT = #planetConfig
	for i = 1, PLANET_COUNT do
		if (not PLANET_WHITELIST) or PLANET_WHITELIST[i] then
			planetList[i] = GetPlanet(planetWindow, i, planetConfig[i], planetAdjacency[i])
		end
	end
	
	local graph = Chili.Control:New{
		x       = 0,
		y       = 0,
		height  = "100%",
		width   = "100%",
		padding = {0,0,0,0},
		drawcontrolv2 = true,
		DrawControl = function (obj)
			local x = obj.x
			local y = obj.y
			local w = obj.width
			local h = obj.height
			
			local _,_,scale = planetHandler.GetZoomTransformValues()
			
			gl.PushMatrix()
			gl.Translate(x, y, 0)
			gl.Scale(w, h, 1)
			gl.LineWidth(3 * scale)
			gl.CallList(edgeDrawList)
			gl.PopMatrix()
		end,
		parent = window,
	}
	
	local function PlanetCaptured(listener, planetID)
		if (not PLANET_WHITELIST) or PLANET_WHITELIST[planetID] then
			planetList[planetID].UpdateStartable(not WG.CampaignData.GetCampaignInitializationComplete())
			UpdateGalaxy()
		end
	end
	WG.CampaignData.AddListener("PlanetCaptured", PlanetCaptured)
	
	local function PlanetUpdate(listener, planetID)
		if (not PLANET_WHITELIST) or PLANET_WHITELIST[planetID] then
			planetList[planetID].UpdateInformation()
		end
	end
	WG.CampaignData.AddListener("PlanetUpdate", PlanetUpdate)
	
	local externalFunctions = {}
	
	function externalFunctions.UpdatePosition(x, y, width, height)
		window:SetPos(x, y, width, height)
		if x then
			for i = 1, PLANET_COUNT do
				if (not PLANET_WHITELIST) or PLANET_WHITELIST[i] then
					planetList[i].UpdatePosition(width, height)
				end
			end
		end
	end
	
	function externalFunctions.GetZoomTransform(x, y, size)
		x = (x - transX)*transScale
		y = (y - transY)*transScale
		return x, y, (size or 1)*transScale
	end
	
	function externalFunctions.GetZoomTransformValues()
		return transX, transY, transScale
	end
	
	function externalFunctions.UpdateVisiblePlanetBounds()
		local left, top, right, bottom
		local padding = 0.05
		for i = 1, PLANET_COUNT do
			if ((not PLANET_WHITELIST) or PLANET_WHITELIST[i]) and planetList[i].GetVisibleEdge() then
				local xPos, yPos = planetConfig[i].mapDisplay.x, planetConfig[i].mapDisplay.y
				if planetList[i].GetVisible() then
					left = math.min(left or (xPos - padding), (xPos - padding))
					top = math.min(top or (yPos - padding), (yPos - padding))
					right = math.max(right or (xPos + padding), (xPos + padding))
					bottom = math.max(bottom or (yPos + padding), (yPos + padding))
				else
					left = math.min(left or xPos, xPos)
					top = math.min(top or yPos, yPos)
					right = math.max(right or xPos, xPos)
					bottom = math.max(bottom or yPos, yPos)
				end
			end
		end
		
		if not left then
			transX, transY, transScale = 0, 0, 1
			return
		end
		
		left = math.max(left, TRANSFORM_BOUNDS.left)
		top = math.max(top, TRANSFORM_BOUNDS.top)
		right = math.min(right, TRANSFORM_BOUNDS.right)
		bottom = math.min(bottom, TRANSFORM_BOUNDS.bottom)
		
		-- Make square
		local width = right - left
		local height = bottom - top
		if width > height then
			local mid = top + height/2
			top = mid - width/2
			bottom = mid + width/2
			
			if top < TRANSFORM_BOUNDS.top then
				bottom = bottom + (TRANSFORM_BOUNDS.top - top)
				top = TRANSFORM_BOUNDS.top
			elseif bottom > TRANSFORM_BOUNDS.bottom then
				top = top + (TRANSFORM_BOUNDS.bottom - bottom)
				bottom = TRANSFORM_BOUNDS.bottom
			end
		else
			local mid = left + width/2
			left = mid - height/2
			right = mid + height/2
			
			if left < TRANSFORM_BOUNDS.left then
				right = right + (TRANSFORM_BOUNDS.left - left)
				left = TRANSFORM_BOUNDS.left
			elseif right > TRANSFORM_BOUNDS.right then
				left = left + (TRANSFORM_BOUNDS.right - right)
				right = TRANSFORM_BOUNDS.right
			end
		end
		
		transX, transY, transScale = left, top, 1/(right - left)
	end
	
	function externalFunctions.GetParent()
		return parent
	end
	
	return externalFunctions
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Ingame interface

local BATTLE_WON_STRING = "Campaign_PlanetBattleWon"
local BATTLE_LOST_STRING = "Campaign_PlanetBattleLost"
local BATTLE_RESIGN_STRING = "Campaign_PlanetBattleResign"

function string:split(delimiter)
	local result = {}
	local from  = 1
	local delim_from, delim_to = string.find(self, delimiter, from)
	while delim_from do
		table.insert(result, string.sub(self, from , delim_from - 1))
		from = delim_to + 1
		delim_from, delim_to = string.find( self, delimiter, from)
	end
	table.insert(result, string.sub(self, from))
	return result
end

function widget:RecvLuaMsg(msg)
	if string.find(msg, BATTLE_WON_STRING) then
		Spring.Echo("msg", msg)
		local data = msg:split(" ")
		Spring.Utilities.TableEcho(data, "data")
		local planetID = tonumber(data[2])
		local battleFrames = tonumber(data[3])
		local bonusObjectives = data[4]
		local difficulty = tonumber(data[5]) or 0
		if planetID and planetConfig and planetConfig[planetID] then
			ProcessPlanetVictory(planetID, battleFrames, MakeBonusObjectivesList(bonusObjectives), bonusObjectives, difficulty)
		end
	elseif string.find(msg, BATTLE_LOST_STRING) then
		Spring.Echo("msg", msg)
		local data = msg:split(" ")
		Spring.Utilities.TableEcho(data, "data")
		local planetID = tonumber(data[2])
		local battleFrames = tonumber(data[3])
		if planetID and planetConfig and planetConfig[planetID] then
			ProcessPlanetDefeat(planetID, battleFrames)
		end
	elseif string.find(msg, BATTLE_RESIGN_STRING) then
		Spring.Echo("msg", msg)
		local data = msg:split(" ")
		Spring.Utilities.TableEcho(data, "data")
		local planetID = tonumber(data[2])
		local battleFrames = tonumber(data[3])
		if planetID and planetConfig and planetConfig[planetID] then
			ProcessPlanetResign(planetID, battleFrames)
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- External Interface

local externalFunctions = {}

function externalFunctions.GetControl(newLiveTestingMode, newPlanetWhitelist, feedbackLink)
	local window = Control:New {
		name = "campaignHandler",
		x = "0%",
		y = "0%",
		width = "100%",
		height = "100%",
		padding = {0,0,0,0},
		OnParentPost = {
			function(obj, parent)
				if obj:IsEmpty() then
					planetHandler = InitializePlanetHandler(obj, newLiveTestingMode, newPlanetWhitelist, feedbackLink)
					
					local x, y = obj:LocalToScreen(0, 0)
					RepositionBackgroundAndPlanets(x, y, obj.width, obj.height)
					UpdateGalaxy()
				end
				
				local background = WG.Chobby.interfaceRoot.GetBackgroundHolder()
				background:SetImageOverride(GALAXY_IMAGE)
				
				obj:UpdateClientArea()
				WG.Chobby.interfaceRoot.GetRightPanelHandler().CloseTabs()
				WG.Chobby.interfaceRoot.GetMainWindowHandler().CloseTabs()
			end
		},
		OnOrphan = {
			function(obj)
				if not obj.disposed then -- AutoDispose
					local background = WG.Chobby.interfaceRoot.GetBackgroundHolder()
					background:RemoveOverride()
				end
			end
		},
		OnResize = {
			function(obj, xSize, ySize)
				if not obj.parent then
					return
				end
				local x, y = obj:LocalToScreen(0, 0)
				RepositionBackgroundAndPlanets(x, y, xSize, ySize)
			end
		},
	}
	return window
end

function externalFunctions.CloseSelectedPlanet()
	if selectedPlanet then
		selectedPlanet.Close()
		selectedPlanet = nil
		return true
	end
	return false
end


--------------------------------------------------------------------------------
-- Callins
--------------------------------------------------------------------------------

local function DelayedViewResize()
	if not planetHandler then
		return
	end
	local window = planetHandler.GetParent()
	if not (window and window.parent) then
		return
	end
	local x, y = window:LocalToScreen(0, 0)
	RepositionBackgroundAndPlanets(x, y, window.xSize, window.ySize)
end

function widget:ViewResize(vsx, vsy)
	WG.Delay(DelayedViewResize, 0.8)
end

function widget:Initialize()
	CHOBBY_DIR = "LuaMenu/widgets/chobby/"
	VFS.Include("LuaMenu/widgets/chobby/headers/exports.lua", nil, VFS.RAW_FIRST)
	
	local function CampaignLoaded(listener)
		if planetList and planetHandler then
			UpdateGalaxy()
			if selectedPlanet then
				selectedPlanet.Close()
				selectedPlanet = nil
			end
		end
	end
	WG.CampaignData.AddListener("CampaignLoaded", CampaignLoaded)
	WG.CampaignData.AddListener("InitializationComplete", CampaignLoaded)
	
	local function GainExperience(listener, oldExperience, oldLevel, newExperience, newLevel, gainedBonusExperience)
		if currentWinPopup then
			currentWinPopup.UpdateExperience(oldExperience, oldLevel, newExperience, newLevel, gainedBonusExperience)
		end
		if oldExperience == 0 or (oldLevel ~= newLevel) then
			local singleplayerMenu = WG.Chobby.interfaceRoot.GetSingleplayerSubmenu()
			if singleplayerMenu then
				local campaignMenu = singleplayerMenu.GetSubmenuByName("campaign")
				if campaignMenu then
					campaignMenu.SetTabHighlighted("commander", true)
				end
			end
		end
	end
	WG.CampaignData.AddListener("GainExperience", GainExperience)
	
	WG.CampaignHandler = externalFunctions
end

function widget:Shutdown()
	WG.CampaignHandler = nil
end