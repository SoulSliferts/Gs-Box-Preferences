-- No need to get GS scores for courses
if GAMESTATE:IsCourseMode() then return end

-- Don't display if Music Wheel GS integration isn't set to Scorebox.
if ThemePrefs.Get("MusicWheelGS") ~= "Scorebox" then return end

local player = ...
local pn = ToEnumShortString(player)

if (not IsServiceAllowed(SL.GrooveStats.GetScores) or
		SL[pn].ApiKey == "") then
	return
end

local n = player==PLAYER_1 and "1" or "2"
local IsNotWide = (GetScreenAspectRatio() < 16/9)
local NoteFieldIsCentered = (GetNotefieldX(player) == _screen.cx)
local NumEntries = ThemePrefs.Get("MaxPlayersDisplayGsBox") -- Set Mx players 5-15

local border = 5
local width = 162
local height = 80
-- the player is 6+... increment the size for the box
if (NumEntries > 5) then
	for i=5,NumEntries do
		height = 16 * i
	end
else
	height = 80
end

local cur_style = 0
local num_styles = 4

local GrooveStatsBlue = color("#007b85")
local RpgYellow = color("1,0.972,0.792,1")
local ItlPink = color("1,0.2,0.406,1")
local BoogieStatsPurple = color("#003fff")

local style_color = {
	[0] = GrooveStatsBlue,  -- Either GrooveStats or GrooveStats EX score
	[1] = GrooveStatsBlue,  -- Either GrooveStats or GrooveStats EX score
	[2] = RpgYellow,
	[3] = ItlPink,
}

local self_color = color(ThemePrefs.Get("PlayerColorGsBox")) -- set color player
local rival_color = color(ThemePrefs.Get("RivalColorGsBox")) -- set color rival

local loop_seconds = 5
local transition_seconds = 1

local all_data = {}

local ResetAllData = function()
	all_data = {}
	SL[pn].Rival = {}
	SL[pn].Rival.Score = 0
	SL[pn].Rival.EXScore = 0
	SL[pn].Rival.WRScore = 0
	SL[pn].Rival.WREXScore = 0
	
	for i=1,num_styles do
		local data = {
			["has_data"]=false,
			["scores"]={}
		}
		local scores = data["scores"]
		for i=1,NumEntries do
			scores[#scores+1] = {
				["rank"]="",
				["name"]="",
				["score"]="",
				["isSelf"]=false,
				["isRival"]=false,
				["isFail"]=false,
				["isEx"]=false,
			}
		end
		all_data[i] = data
	end
end

-- Initialize the all_data object.
ResetAllData()

-- Checks to see if any data is available.
local HasData = function(idx)
	return all_data[idx+1] and all_data[idx+1].has_data
end

local SetScoreData = function(data_idx, score_idx, rank, name, score, isSelf, isRival, isFail, isEx)
	all_data[data_idx].has_data = true

	local score_data = all_data[data_idx]["scores"][score_idx]
	score_data.rank = rank..((#rank > 0) and "." or "")
	score_data.name = name
	score_data.score = score
	score_data.isSelf = isSelf
	score_data.isRival = isRival
	score_data.isFail = isFail
	score_data.isEx = isEx
	
	if not isFail and (isRival or isSelf) then
		if data_idx == 3 then
			if tonumber(score) > SL[pn].Rival.EXScore then
				SL[pn].Rival.EXScore = tonumber(score)
			end
		else
			if tonumber(score) > SL[pn].Rival.Score then
				SL[pn].Rival.Score = tonumber(score)
			end
		end
	end
	
	if score_data.rank == 1 then
		if data_idx == 3 then
			SL[pn].Rival.WREXScore = tonumber(score)
		else
			if tonumber(score) > SL[pn].Rival.WRScore then
				SL[pn].Rival.WRScore = tonumber(score)
			end
		end
	end
end

local LeaderboardRequestProcessor = function(res, master)
	if master == nil then return end

	if res.error or res.statusCode ~= 200 then
		local error = res.error and ToEnumShortString(res.error) or nil
		local text = ""
		if error == "Timeout" then
			text = "Timed Out"
		elseif error or (res.statusCode ~= nil and res.statusCode ~= 200) then
			text = "Failed to Load 😞"
		end
		SetScoreData(1, 1, "", text, "", false, false, false, false)
		if master ~= nil then
			master:queuecommand("CheckScorebox")
		end
		return
	end

	local playerStr = "player"..n
	local data = JsonDecode(res.body)

	-- BoogieStats integration
	-- Find out whether this chart is ranked on GrooveStats. 
	-- If it is unranked, alter groovestats logo and the box border color to the BoogieStats theme
	local headers = res.headers
	local boogie = false
	local boogie_ex = false
	if headers["bs-leaderboard-player-" .. n] == "BS" then
		boogie = true
	elseif headers["bs-leaderboard-player-" .. n] == "BS-EX" then
		boogie_ex = true
	end
	if not SCREENMAN:GetTopScreen():GetChild("Overlay") then return end
	local gsBox = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("ScoreBox" .. pn):GetChild("GrooveStatsLogo")
	local bsBox = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("ScoreBox" .. pn):GetChild("BoogieStatsLogo")
	local bsExBox = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("ScoreBox" .. pn):GetChild("BoogieStatsEXLogo")

	if boogie then
		style_color[0] = BoogieStatsPurple
		style_color[1] = BoogieStatsPurple
		bsBox:visible(true)
		bsExBox:visible(false)
		gsBox:visible(false)
	else
		style_color[0] = GrooveStatsBlue
		bsBox:visible(false)
		bsExBox:visible(false)
		gsBox:visible(true)
	end
	

	-- First check to see if the leaderboard even exists.
	if data and data[playerStr] then
		if SL[pn].Streams.Hash ~= data[playerStr]["chartHash"] then return end
		-- These will get overwritten if we have any entries in the leaderboard below.
		SetScoreData(1, 1, "", "No Scores", "", false, false, false, false)
		SetScoreData(2, 1, "", "No Scores", "", false, false, false, false)
		
		all_data[1].has_data = false
		all_data[2].has_data = false
		
		local showITG = SL["P"..n].ActiveModifiers.SBITGScore
		local showEX = SL["P"..n].ActiveModifiers.SBEXScore
		local showEvents = SL["P"..n].ActiveModifiers.SBEvents
		
		cur_style = 0

		local numEntries = 0
		if SL["P"..n].ActiveModifiers.ShowEXScore then
			-- If the player is using EX scoring, then we want to display the EX leaderboard first.		
			if showEX then
				if data[playerStr]["exLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["exLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(1, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										true
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(1, i, "", "", "", "", "", "", true)
					end
				end
			end

			if showITG then
				if data[playerStr]["gsLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["gsLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(2, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										boogie_ex
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(2, i, "", "", "", "", "", "", boogie_ex)
					end
				end
			end
		else
			-- Display the main GrooveStats leaderboard first if player is not using EX scoring.
			if showITG then
				if data[playerStr]["gsLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["gsLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(1, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										boogie_ex
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(1, i, "", "", "", "", "", "", boogie_ex)
					end
				end
			end

			if showEX then
				if data[playerStr]["exLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["exLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(2, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										true
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(2, i, "", "", "", "", "", "", true)
					end
				end
			end
		end

		-- Display event boxes first if they are applicable
		if showEvents then
			if data[playerStr]["rpg"] then
				cur_style = 3
				local numEntries = 0
				SetScoreData(3, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["rpg"]["rpgLeaderboard"] then
					for entry in ivalues(data[playerStr]["rpg"]["rpgLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(3, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										false
									)
					end
					numEntries = numEntries + 1
					for i=numEntries,5,1 do
						SetScoreData(3, i,
										"",
										"",
										"",
										false,
										false,
										false)
					end
				end
			end

			if data[playerStr]["itl"] then
				cur_style = 4
				local numEntries = 0
				SetScoreData(4, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["itl"]["itlLeaderboard"] then
					for entry in ivalues(data[playerStr]["itl"]["itlLeaderboard"]) do
						if entry["isSelf"] then
							UpdateItlExScore(player, SL[pn].Streams.Hash, entry["score"])
							SL["P"..n].itlScore = entry["score"]
							local stepartist = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("StepArtistAF_P"..n)
							if stepartist ~= nil then
							  stepartist:queuecommand("ITL")
							end
						end
						numEntries = numEntries + 1
						SetScoreData(4, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										true
									)
					end
					numEntries = numEntries + 1
					for i=numEntries,5,1 do
						SetScoreData(4, i,
										"",
										"",
										"",
										false,
										false,
										false)
					end
				end
			end
		end
 	end
	if master ~= nil then
		master:queuecommand("CheckScorebox")
	end
end

local af = Def.ActorFrame{
	Name="ScoreBox"..pn,
	InitCommand=function(self)
		if #GAMESTATE:GetHumanPlayers() == 1 then
			-- fix the position in y for the box
			if (NumEntries > 5) then
				self:x(_screen.cx + 80)
				local f = 10
				for i=5,NumEntries do
					-- the box is 10+... fix the broken position y
					if (NumEntries >= 10) then
						self:y(_screen.cy + 160 - f)
						f = f + 7
					else
						self:y(_screen.cy + 160 - f)
						f = f + 5
					end
				end
			else
				self:x(_screen.cx + 80):y(_screen.cy + 160)
			end
			if pn == "P2" then
				self:y(_screen.cy*1.65 - 55)
			end
		else
			if pn == "P1" then
				self:zoom(0.65):x(_screen.cx - 65):y(_screen.cy + 178)
				if IsNotWide then
					self:x(_screen.cx - 48)
				end
			else
				self:zoom(0.65):x(_screen.cx + 371):y(_screen.cy + 178)
				if IsNotWide then
					self:x(_screen.cx + 279)
				end
			end
		end
		self.isFirst = true
	end,
	ResetCommand=function(self) self:stoptweening() end,
	OffCommand=function(self) self:stoptweening() end,
	PlayerJoinedMessageCommand=function(self, params)
		if pn == "P1" then
			self:zoom(0.65):x(_screen.cx - 65):y(_screen.cy + 178)
			if IsNotWide then
				self:x(_screen.cx - 48)
			end
		else
			self:zoom(0.65):x(_screen.cx + 371):y(_screen.cy + 178)
			if IsNotWide then
				self:x(_screen.cx + 279)
			end
		end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:visible(false)
		end
		self:x(_screen.cx + 80):y(_screen.cy + 160):zoom(1)
		if pn == "P2" then
			self:y(_screen.cy*1.65 - 55)
		end
	end,
	CurrentSongChangedMessageCommand=function(self)
		self:finishtweening():visible(false)
		ResetAllData()
		self.isFirst = true
	end,
	CheckScoreboxCommand=function(self)
		if GAMESTATE:GetCurrentSong() and GAMESTATE:GetCurrentSteps(player) then
			self:queuecommand("LoopScorebox")
		end
	end,
	LoopScoreboxCommand=function(self)
		self:visible(true)
		
		local has_data = false
		if #all_data == 0 then return end
		for i=1,num_styles do
			if all_data[i].has_data then
				has_data = true
				break
			end
		end
		if not has_data then return end

		self:finishtweening()
		
		self:GetChild("Name1"):visible(true)
		self:GetChild("Name2"):visible(true)
		self:GetChild("Name3"):visible(true)
		self:GetChild("Name4"):visible(true)
		self:GetChild("Name5"):visible(true)
		self:GetChild("Score1"):visible(true)
		self:GetChild("Score2"):visible(true)
		self:GetChild("Score3"):visible(true)
		self:GetChild("Score4"):visible(true)
		self:GetChild("Score5"):visible(true)
		self:GetChild("Rank1"):visible(true)
		self:GetChild("Rank2"):visible(true)
		self:GetChild("Rank3"):visible(true)
		self:GetChild("Rank4"):visible(true)
		self:GetChild("Rank5"):visible(true)
		self:GetChild("GrooveStatsLogo"):stopeffect()
		self:GetChild("BoogieStatsLogo"):stopeffect()
		self:GetChild("BoogieStatsEXLogo"):stopeffect()
		self:GetChild("SRPG8Logo"):visible(true)
		self:GetChild("ITLLogo"):visible(true)
		self:GetChild("Outline"):visible(true)
		self:GetChild("Background"):linear(transition_seconds/2):diffusealpha(1):visible(true)
		
		local start = cur_style

		cur_style = (cur_style + 1) % num_styles
		if cur_style ~= start or self.isFirst then
			-- Make sure we have the next set of data.
			while cur_style ~= start do
				if HasData(cur_style) then
					-- If this is the first time we're looping, update the start variable
					-- since it may be different than the default
					if self.isFirst then
						start = cur_style
						self.isFirst = false
						-- Continue looping to figure out the next style.
					else
						break
					end
				end
				cur_style = (cur_style + 1) % num_styles
			end
		end

		-- Loop only if there's something new to loop to.
		if start ~= cur_style then
			self:sleep(loop_seconds):queuecommand("LoopScorebox")
		end
	end,

	RequestResponseActor(0, 0)..{
		OnCommand=function(self)
			self:queuecommand("MakeRequest")
			-- Create variables for both players, even if they're not currently active.
			self.IsParsing = {false, false}
		end,
		-- Broadcasted from ./PerPlayer/DensityGraph.lua
		P1ChartParsingMessageCommand=function(self)	self.IsParsing[1] = true end,
		P2ChartParsingMessageCommand=function(self)	self.IsParsing[2] = true end,
		P1ChartParsedMessageCommand=function(self)
			self.IsParsing[1] = false
			if pn == "P1" then
				self:queuecommand("ChartParsed")
			end
		end,
		P2ChartParsedMessageCommand=function(self)
			self.IsParsing[2] = false
			if pn == "P2" then
				self:queuecommand("ChartParsed")
			end
		end,
		ChartParsedCommand=function(self)
			if not self.leaving_screen then
				self:queuecommand("MakeRequest")
			end
		end,
		MakeRequestCommand=function(self)				
			local sendRequest = false
			local headers = {}
			local query = {
				maxLeaderboardResults=NumEntries,
			}

			if SL[pn].ApiKey ~= "" and SL[pn].Streams.Hash ~= "" then
				query["chartHashP"..n] = SL[pn].Streams.Hash
				headers["x-api-key-player-"..n] = SL[pn].ApiKey
				sendRequest = true
			end

			-- We technically will send two requests in ultrawide versus mode since
			-- both players will have their own individual scoreboxes.
			-- Should be fine though.
			if sendRequest then
				if self.IsParsing[1] or self.IsParsing[2] then return end
				
				RemoveStaleCachedRequests()
				ResetAllData()
				
				self:GetParent():visible(true)
				self:GetParent():GetChild("Name1"):settext(""):visible(false)
				self:GetParent():GetChild("Name2"):settext(""):visible(false)
				self:GetParent():GetChild("Name3"):settext(""):visible(false)
				self:GetParent():GetChild("Name4"):settext(""):visible(false)
				self:GetParent():GetChild("Name5"):settext(""):visible(false)
				self:GetParent():GetChild("Score1"):settext(""):visible(false)
				self:GetParent():GetChild("Score2"):settext(""):visible(false)
				self:GetParent():GetChild("Score3"):settext(""):visible(false)
				self:GetParent():GetChild("Score4"):settext(""):visible(false)
				self:GetParent():GetChild("Score5"):settext(""):visible(false)
				self:GetParent():GetChild("Rank1"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Rank2"):settext(""):visible(false)
				self:GetParent():GetChild("Rank3"):settext(""):visible(false)
				self:GetParent():GetChild("Rank4"):settext(""):visible(false)
				self:GetParent():GetChild("Rank5"):settext(""):visible(false)
				self:GetParent():GetChild("GrooveStatsLogo"):visible(true):diffusealpha(0.5):glowshift({color("#C8FFFF"), color("#6BF0FF")})
				self:GetParent():GetChild("BoogieStatsLogo"):visible(false)
				self:GetParent():GetChild("BoogieStatsEXLogo"):visible(false)
				self:GetParent():GetChild("SRPG8Logo"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("ITLLogo"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Outline"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Background"):diffusealpha(0):visible(false)
				
				if IsItlSong(player) then
					UpdatePathMap(player, SL[pn].Streams.Hash)
				end
				
				self:playcommand("MakeGrooveStatsRequest", {
					endpoint="player-leaderboards.php?"..NETWORK:EncodeQueryParameters(query),
					method="GET",
					headers=headers,
					timeout=10,
					callback=LeaderboardRequestProcessor,
					args=self:GetParent(),
				})
			end
		end
	},

	-- Outline
	Def.Quad{
		Name="Outline",
		InitCommand=function(self)
			self:diffuse(GrooveStatsBlue):setsize(width + border, height + border)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width + border - 40, height + border)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width + border - 40, height + border)
			else
				self:setsize(width + border, height + border)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width + border, height + border)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds):diffuse(style_color[cur_style])
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- Main body
	Def.Quad{
		Name="Background",
		InitCommand=function(self)
			self:diffuse(color("#000000")):setsize(width, height)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width - 40, height)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width - 40, height)
			else
				self:setsize(width, height)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width, height)
		end,
	},
	-- GrooveStats Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "GrooveStats.png"),
		Name="GrooveStatsLogo",
		InitCommand=function(self)
			self:zoom(0.8):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 or cur_style == 1 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- BoogieStats Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "BoogieStats.png"),
		Name="BoogieStatsLogo",
		InitCommand=function(self)
			self:zoom(0.8):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 or cur_style == 1 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- BoogieStats EX Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "BoogieStatsEX.png"),
		Name="BoogieStatsEXLogo",
		InitCommand=function(self)
			self:zoom(0.8):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- EX Text
	Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="EX",
		InitCommand=function(self)
			self:diffusealpha(0):x(2):y(-5)
		end,
		LoopScoreboxCommand=function(self)
			if (cur_style == 1 and not SL["P"..n].ActiveModifiers.ShowEXScore) or (cur_style == 0 and SL["P"..n].ActiveModifiers.ShowEXScore) then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.3)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- SRPG Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "_VisualStyles/SRPG8/logo_main (doubleres).png"),
		Name="SRPG8Logo",
		InitCommand=function(self)
			self:diffusealpha(0.4):zoom(0.05):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 2 then
				self:linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- ITL Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "ITL.png"),
		Name="ITLLogo",
		InitCommand=function(self)
			self:diffusealpha(0.2):zoom(0.45):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 3 then
				self:linear(transition_seconds/2):diffusealpha(0.2)
			else
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
}

for i=1,NumEntries do
	local y = -height/2 + 16 * i - 8
	local zoom = 0.87

	-- Rank 1 gets a crown.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Name="Rank"..i,
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoom(0.09):xy(-width/2 + 14, y):diffusealpha(0)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(-width/2 + 32)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				if IsNotWide then
					self:x(-width/2 + 32)
				else
					self:x(-width/2 + 14)
				end
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(-width/2 + 14)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				if score.rank ~= "" then
					self:linear(transition_seconds/2):diffusealpha(1)
				end
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	else
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Name="Rank"..i,
			Text="",
			InitCommand=function(self)
				self:diffuse(Color.White):xy(-width/2 + 27, y):maxwidth(30):horizalign(right):zoom(zoom)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(-width/2 + 42)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				if IsNotWide then
					self:x(-width/2 + 42)
				else
					self:x(-width/2 + 27)
				end
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(-width/2 + 27)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				local clr = Color.White
				if score.isSelf then
					clr = self_color
				elseif score.isRival then
					clr = rival_color
				end
				self:settext(score.rank)
				self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Name"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 30, y):maxwidth(100):horizalign(left):zoom(zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 45):maxwidth(70)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(-width/2 + 45):maxwidth(70)
			else
				self:x(-width/2 + 30):maxwidth(100)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 30):maxwidth(100)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = Color.White
			if score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.name)
			self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Score"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 160, y):horizalign(right):zoom(zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 140)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(-width/2 + 140)
			else
				self:x(-width/2 + 160)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 160)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = Color.White
			if score.isFail then
				clr = Color.Red
			elseif score.isEx then
				clr = SL.JudgmentColors["FA+"][1]
			elseif score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.score)
			self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}
end
return af
