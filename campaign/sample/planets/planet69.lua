--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Planet config

local function GetPlanet(planetUtilities, planetID)
	
	--local image = planetUtilities.planetImages[math.floor(math.random()*#planetUtilities.planetImages) + 1]
	local image = LUA_DIRNAME .. "images/planets/terran02.png"
	
	local planetData = {
		name = "Folsom",
		startingPlanet = true,
		mapDisplay = {
			x = (planetUtilities.planetPositions and planetUtilities.planetPositions[planetID][1]) or 0.05,
			y = (planetUtilities.planetPositions and planetUtilities.planetPositions[planetID][2]) or 0.87,
			image = image,
			size = planetUtilities.PLANET_SIZE_MAP,
			hintText = "Click this planet to begin.",
			hintSize = {410, 66},
		},
		infoDisplay = {
			image = image,
			size = planetUtilities.PLANET_SIZE_INFO,
			backgroundImage = planetUtilities.backgroundImages[math.floor(math.random()*#planetUtilities.backgroundImages) + 1],
			terrainType = "Terran",
			radius = "6550 km",
			primary = "Origin",
			primaryType = "G8V",
			milRating = 1,
			text = [[Familiarize yourself with command by establishing a foothold on a critical piece of infrastructure. The abandoned tools of war the previous owners left behind will serve as good practice for the tougher challenges ahead.]]
		},
		gameConfig = {
			gameName = "Quick Tutorial",
			mapName = "FolsomDamDeluxeV4",
			playerConfig = {
				startX = 300,
				startZ = 3800,
				allyTeam = 0,
				commanderParameters = {
					facplop = false,
				},
				extraUnlocks = {
					"factorycloak",
					"cloakraid",
					"staticmex",
					"energysolar",
					"turretlaser", -- This is here so the tab exists
					"staticradar", -- This is here so the tab exists
				},
			},
			modoptions = {
				integral_disable_defence = 1,
				integral_disable_special = 1,
			},
			aiConfig = {
				{
					startX = 4000,
					startZ = 75,
					aiLib = "NullAI",
					humanName = "Ally",
					allyTeam = 0,
					unlocks = {},
					commander = false,
				},
				{
					startX = 4000,
					startZ = 75,
					aiLib = "NullAI",
					humanName = "Enemy",
					allyTeam = 1,
					unlocks = {},
					commander = false,
				},
			},
			defeatConditionConfig = {
				-- Indexed by allyTeam.
				[0] = {},
				[1] = {
					ignoreUnitLossDefeat = true,
				},
			},
			objectiveConfig = {
			},
			bonusObjectiveConfig = {
			}
		},
		completionReward = {
			experience = planetUtilities.MAIN_EXP,
			units = {
				"factorycloak",
				"cloakraid",
				"staticmex",
				"energysolar",
			},
			modules = {
				"module_ablative_armor_LIMIT_A_2",
			},
			abilities = {},
			codexEntries = {}
		},
	}
	
	return planetData
end

return GetPlanet
