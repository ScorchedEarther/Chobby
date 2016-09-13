--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "Queue List Window",
		desc      = "Handles matchMaking queue list display.",
		author    = "GoogleFrog",
		date      = "11 September 2016",
		license   = "GNU LGPL, v2.1 or later",
		layer     = -100000,
		enabled   = true  --  loaded by default?
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Variables

local requiredMaps = {}
local requiredMapCount = 0

local panelInterface

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Initialization

local function MakeQueueControl(parentControl, queueName, queueDescription)
	local Configuration = WG.Chobby.Configuration
	
	local btnLeave, btnJoin
	
	btnJoin = Button:New {
		x = 0,
		y = 0,
		width = 80,
		bottom = 0,
		caption = i18n("join"),
		font = Configuration:GetFont(3),
		classname = "option_button",
		OnClick = {
			function(obj)
				if requiredMapCount ~= 0 then
					WG.Chobby.InformationPopup("Map downloads must complete before you are able to join matchmaking.")
					return
				end
			
				WG.LibLobby.lobby:JoinMatchMaking(queueName)
				obj:SetVisibility(false)
				btnLeave:SetVisibility(true)
			end
		},
		parent = parentControl
	}
	
	btnLeave = Button:New {
		x = 0,
		y = 0,
		width = 80,
		bottom = 0,
		caption = i18n("leave"),
		font = Configuration:GetFont(3),
		classname = "action_button",
		OnClick = {
			function(obj)
				WG.LibLobby.lobby:LeaveMatchMaking(queueName)
				obj:SetVisibility(false)
				btnJoin:SetVisibility(true)
			end
		},
		parent = parentControl
	}
	btnLeave:SetVisibility(false)
	
	local lblTitle = TextBox:New {
		x = 90,
		y = 10,
		width = 120,
		bottom = 0,
		fontsize = Configuration:GetFont(3).size,
		text = queueName,
		parent = parentControl
	}
	
	local lblDescription = TextBox:New {
		x = 180,
		y = 15,
		width = 120,
		right = 5,
		align = "bottom",
		bottom = 0,
		fontsize = Configuration:GetFont(1).size,
		text = queueDescription,
		parent = parentControl
	}
	
	local externalFunctionsAndData = {}
	
	externalFunctionsAndData.inQueue = false
	
	function externalFunctionsAndData.SetInQueue(inQueue)
		btnJoin:SetVisibility(not inQueue)
		btnLeave:SetVisibility(inQueue)
	end
	
	return externalFunctionsAndData
end

local function InitializeControls(window)
	local Configuration = WG.Chobby.Configuration
	local lobby = WG.LibLobby.lobby
	
	local lblTitle = Label:New {
		x = 20,
		right = 5,
		y = 16,
		height = 20,
		font = Configuration:GetFont(3),
		caption = "Queues",
		parent = window
	}

	local btnClose = Button:New {
		right = 7,
		y = 5,
		width = 80,
		height = 45,
		caption = i18n("close"),
		font = Configuration:GetFont(3),
		classname = "negative_button",
		OnClick = {
			function()
				window:Hide()
			end
		},
		parent = window
	}

	local listPanel = ScrollPanel:New {
		x = 5,
		right = 5,
		y = 55,
		height = 200,
		borderColor = {0,0,0,0},
		horizontalScrollbar = false,
		parent = window
	}
	
	local statusText = TextBox:New {
		x = 5,
		right = 5,
		y = 270,
		height = 200,
		fontsize = Configuration:GetFont(2).size,
		text = "",
		parent = window
	}
	
	local requirementText = TextBox:New {
		x = 5,
		right = 5,
		y = 350,
		height = 200,
		fontsize = Configuration:GetFont(2).size,
		text = "",
		parent = window
	}
	
	local queues = 0
	local queueHolders = {}
	local function AddQueue(_, queueName, queueDescription, mapNames)
		if listPanel:GetChildByName(queueName) then
			return
		end
	
		local queueHolder = Control:New {
			x = 10,
			y = queues*50 + 20,
			right = 0,
			height = 35,
			caption = "", -- Status Window
			parent = listPanel,
			resizable = false,
			draggable = false,
			padding = {0, 0, 0, 0},
		}
		queueHolders[queueName] = MakeQueueControl(queueHolder, queueName, queueDescription)
		queues = queues + 1
	end
	
	local possibleQueues = lobby:GetQueues()
	for name, data in pairs(possibleQueues) do
		AddQueue(_, data.name, data.description, data.mapNames)
	end
	
	local function UpdateQueueStatus(listener, inMatchMaking, joinedQueueList, queueCounts, currentEloWidth, joinedTime, bannedTime)
		local peopleInCommonQueues = 0
		for i = 1, #joinedQueueList do
			local queueName = joinedQueueList[i]
			peopleInCommonQueues = peopleInCommonQueues + ((queueCounts and queueCounts[queueName]) or 0)
			if queueHolders[queueName] then
				queueHolders[queueName].inQueue = true
			end
		end
		
		for name, queueHolder in pairs(queueHolders) do
			queueHolder.SetInQueue(queueHolder.inQueue)
			queueHolder.inQueue = false
		end
		
		if bannedTime then
			statusText:SetText("You are banned from matchmaking for " .. bannedTime)
		end
	end
	
	lobby:AddListener("OnQueueOpened", AddQueue)
	lobby:AddListener("OnMatchMakerStatus", UpdateQueueStatus)
	
	local externalFunctions = {}
	
	function externalFunctions.UpdateRequirementText()
		local newText = ""
		local firstEntry = true
		for name,_ in pairs(requiredMaps) do
			if firstEntry then
				newText = "Required maps: "
			else
				newText = newText .. ", "
			end
			firstEntry = false
			newText = newText .. name
		end
		requirementText:SetText(newText)
	end
	
	externalFunctions.UpdateRequirementText()
	
	return externalFunctions
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- External Interface

local QueueListWindow = {}

function QueueListWindow.GetControl()

	local window = Control:New {
		x = "0%",
		y = "0%",
		width = "100%",
		height = "100%",
		padding = {0, 0, 0, 0},
		OnParent = {
			function(obj)
				if obj:IsEmpty() then
					panelInterface = InitializeControls(obj)
				end
			end
		},
	}
	return window
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Widget Interface

function widget:DownloadFinished()
	for mapName,_ in pairs(requiredMaps) do
		local haveMap = VFS.HasArchive(mapName)
		if haveMap then
			requiredMaps[mapName] = nil
			requiredMapCount = requiredMapCount - 1
		end
	end
	
	if panelInterface then
		panelInterface.UpdateRequirementText()
	end
end

function widget:Initialize()
	CHOBBY_DIR = LUA_DIRNAME .. "widgets/chobby/"
	VFS.Include(LUA_DIRNAME .. "widgets/chobby/headers/exports.lua", nil, VFS.RAW_FIRST)

	local function AddQueue(_, queueName, queueDescription, mapNames)
		for i = 1, #mapNames do
			local mapName = mapNames[i]
			if not requiredMaps[mapName] then
				local haveMap = VFS.HasArchive(mapName)
				if not haveMap then
					requiredMaps[mapName] = true
					requiredMapCount = requiredMapCount + 1
					
					VFS.DownloadArchive(mapName, "map")
				end
			end
		end
		
		if panelInterface then
			panelInterface.UpdateRequirementText()
		end
	end
	
	WG.LibLobby.lobby:AddListener("OnQueueOpened", AddQueue)
	
	WG.QueueListWindow = QueueListWindow
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------