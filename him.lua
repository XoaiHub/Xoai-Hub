-- Function to auto select team (run only once)
function autoSelectTeam()
    local args = {
        [1] = "SetTeam",  -- Team setting command
        [2] = "Pirates"   -- Team you want to select (Pirates in this case)
    }

    -- Call InvokeServer to select team
    local success, result = pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer(unpack(args))
    end)

    -- Check if successful and handle errors
    if success then
        print("Successfully set team to Pirates.")
    else
        warn("Error setting team: " .. tostring(result))
    end
end

-- Call autoSelectTeam once when the script starts
autoSelectTeam()

-- Global variables for quest and fruit
local NameM, NameQ, LvQ, CFQ

-- Function to teleport to a position using Tween (adjustable duration for slower movement)
-- Function for teleportation to a position
function TP(Pos)
    local character = game.Players.LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.CFrame = Pos
    else
        warn("HumanoidRootPart not found!")
    end
end

function Tween(Pos, duration)
    local character = game.Players.LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        -- Import TweenService
        local TweenService = game:GetService("TweenService")

        -- Set a default duration if not provided
        duration = duration or 5  -- Default to 5 seconds if not provided


        -- Create a TweenInfo object
        local tweenInfo = TweenInfo.new(
            duration, -- Duration (adjustable)
            Enum.EasingStyle.Linear, -- Easing style for smoothness
            Enum.EasingDirection.Out, -- Direction of the easing
            0, -- No repeat count
            false, -- Don't reverse the tween
            0 -- No delay before starting the tween
        )
        
        -- Create the goal for the tween
        local goal = {CFrame = Pos}
        
        -- Create the tween using TweenService
        local tween = TweenService:Create(character.HumanoidRootPart, tweenInfo, goal)
        
        -- Play the tween
        tween:Play()
    else
        warn("HumanoidRootPart not found!")
    end
end

-- Function to check and set quest details based on level
function checkQuest()
    local lvl = game:GetService("Players").LocalPlayer.Data.Level.Value
    -- Check quest based on level ranges
    if lvl <= 9 then
        NameM = "Bandit"
        NameQ = "BanditQuest1"
        LvQ = 1
        CFQ = CFrame.new(1058.9927978515625, 16.13587760925293, 1551.7337646484375)
    elseif lvl >= 10 and lvl < 14 then
        NameM = "Monkey"
        NameQ = "JungleQuest"
        LvQ = 1
        CFQ = CFrame.new(-1598.089111328125, 35.55011749267578, 153.37783813476562)
    elseif lvl >= 15 and lvl <= 24 then
        NameM = "Gorilla"
        NameQ = "JungleQuest"
        LvQ = 2
        CFQ = CFrame.new(-1232.4705810546875, 2.222564935684204, -516.0242919921875)
    elseif lvl >= 25 and lvl <= 29 then
        NameM = "The Gorilla King"
        NameQ = "JungleQuest"
        LvQ = 3
        CFQ = CFrame.new(-1136.59375, 6.0392680168151855, -451.90875244140625)
    elseif lvl >= 30 and lvl <= 44 then
        NameM = "Pirate"
        NameQ = "BuggyQuest1"
        LvQ = 1
        CFQ = CFrame.new(-1140.51416015625, 3.4500136375427246, 3902.158203125)
    elseif lvl >= 45 and lvl <= 59 then
        NameM = "Brute"
        NameQ = "BuggyQuest1"
        LvQ = 2
        CFQ = CFrame.new(-877.4066772460938, 13.633481979370117, 4261.064453125)
    elseif lvl >= 60 and lvl <= 74 then
        NameM = "Desert Bandit"
        NameQ = "DesertQuest"
        LvQ = 1
        CFQ = CFrame.new(875.7348022460938, 5.147282123565674, 4485.775390625)
    elseif lvl >= 75 and lvl <= 89 then
        NameM = "Desert Officer"
        NameQ = "DesertQuest"
        LvQ = 2
        CFQ = CFrame.new(1608.4351806640625, -0.09106875956058502, 4461.8984375)
    elseif lvl >= 90 and lvl <= 99 then
        NameM = "Snow Bandit"
        NameQ = "SnowQuest"
        LvQ = 1
        CFQ = CFrame.new(1181.7484130859375, 85.97068786621094, -1318.0391845703125)
    elseif lvl >= 100 and lvl <= 119 then
        NameM = "Snowman"
        NameQ = "SnowQuest"
        LvQ = 2
        CFQ = CFrame.new(1153.3218994140625, 104.47148895263672, -1431.357177734375)
    elseif lvl >= 120 and lvl <= 149 then
        NameM = "Chief Petty Officer"
        NameQ = "MarineQuest2"
        LvQ = 1
        CFQ = CFrame.new(-4923.10791015625, 19.349998474121094, 4076.943359375)
    elseif lvl >= 150 and lvl <= 174 then
        NameM = "Sky Bandit"
        NameQ = "SkyQuest"
        LvQ = 1
        CFQ = CFrame.new(-4960.736328125, 276.7643737792969, -2797.63916015625)
    elseif lvl >= 175 and lvl <= 189 then
        NameM = "Dark Master"
        NameQ = "SkyQuest"
        LvQ = 2
        CFQ = CFrame.new(-5339.18212890625, 387.3499755859375, -2258.0126953125)
    elseif lvl >= 190 and lvl <= 209 then
        NameM = "Prisoner"
        NameQ = "PrisonerQuest"
        LvQ = 1
        CFQ = CFrame.new(5221.13134765625, 0.3318325877189636, 442.4338073730469)
    elseif lvl >= 210 and lvl <= 249 then
        NameM = "Dangerous Prisoner"
        NameQ = "PrisonerQuest"
        LvQ = 2
        CFQ = CFrame.new(5477.04150390625, 0.34914466738700867, 466.3166198730469)
    elseif lvl >= 250 and lvl <= 274 then
        NameM = "Toga Warrior"
        NameQ = "ColosseumQuest"
        LvQ = 1
        CFQ = CFrame.new(-1664.951416015625, -2.7931976318359375, -2981.8759765625)
    elseif lvl >= 275 and lvl <= 298 then
        NameM = "Gladiator"
        NameQ = "ColosseumQuest"
        LvQ = 2
        CFQ = CFrame.new(-1426.0404052734375, -0.739990234375, -3200.133544921875)
    end
end

-- Function to start the quest
function getQ()
    checkQuest()
    if NameQ and LvQ then
        local args = {
            [1] = "StartQuest",
            [2] = NameQ,
            [3] = LvQ
        }
        local success, result = pcall(function()
            return game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer(unpack(args))
        end)
        if not success then
            warn("Error starting quest: " .. tostring(result))
        end
    else
        warn("Quest details not properly set.")
    end
end

-- Function for fast attack
function FastAttack()
    local ReplicatedStorage = game.ReplicatedStorage
    local player = game.Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local rootPart = character:WaitForChild("HumanoidRootPart")

    -- Start fast attack using RegisterAttack
    local attackSuccess, attackErr = pcall(function()
        ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"):WaitForChild("RE/RegisterAttack"):FireServer(0.5)
    end)

    if not attackSuccess then
        warn("Error during fast attack: " .. tostring(attackErr))
        return
    end

    -- Handle the enemies
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if not enemiesFolder then 
        warn("Enemies folder not found in workspace.")
        return 
    end

    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        if enemy:IsA("Model") and enemy:FindFirstChild("Head") then
            local head = enemy:FindFirstChild("Head")
            local humanoid = enemy:FindFirstChild("Humanoid")
            if head and humanoid then
                local distance = (head.Position - rootPart.Position).Magnitude
                if distance <= 100 then
                    -- Hide the enemy's head to simulate a hit
                    local hideSuccess, hideErr = pcall(function()
                        head:SetAttribute("Hidden", true)
                    end)

                    if not hideSuccess then
                        warn("Error hiding head: " .. tostring(hideErr))
                    end

                    -- Register hit on the enemy
                    local hitSuccess, hitErr = pcall(function()
                        ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"):WaitForChild("RE/RegisterHit"):FireServer(head)
                    end)

                    if not hitSuccess then
                        warn("Error during RegisterHit: " .. tostring(hitErr))
                    end
                end
            end
        end
    end
end

-- Function to add points to Defense
function addDefensePoints(points)
    local args = {
        [1] = "AddPoint",   -- Command to add points
        [2] = "Defense",    -- Type of point (Defense in this case)
        [3] = points       -- Number of points you want to add
    }

    -- Send the request to the server to add points
    local success, result = pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer(unpack(args))
    end)

    -- Handle success or failure
    if success then
        print("Successfully added " .. points .. " Defense points.")
    else
        warn("Error adding Defense points: " .. tostring(result))
    end
end

-- Function to bring mob to a specified position
function BringMob(PosMon)
    checkQuest()
    if workspace.Enemies then
        for _, v in pairs(workspace.Enemies:GetChildren()) do
            if v.Name == NameM and v:FindFirstChild("HumanoidRootPart") then
                local humanoid = v:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 10 then
                    v.HumanoidRootPart.CanCollide = false
                    v.HumanoidRootPart.CFrame = PosMon                                                          
                end
            end  
        end
    else
        warn("Enemies folder not found in workspace.")
    end
end

-- Function to randomly buy or equip a fruit
function randomFruit()
    local fruits = {"Cousin"}  -- Example fruits list
    local actions = {"Buy", "Equip"}  -- Example actions

    local selectedFruit = fruits[math.random(1, #fruits)]
    local selectedAction = actions[math.random(1, #actions)] 

    -- Display the chosen action and fruit
    print("Executing action: " .. selectedAction .. " on fruit: " .. selectedFruit)

    local args = {selectedFruit, selectedAction}
    local replicatedStorage = game:GetService("ReplicatedStorage")
    local remotes = replicatedStorage:WaitForChild("Remotes")
    local commF = remotes:WaitForChild("CommF_")

    local success, result = pcall(function()
        return commF:InvokeServer(unpack(args))
    end)

    if success then
        print("Success! Result: " .. tostring(result))
    else
        warn("Error invoking server: " .. tostring(result))
    end
end

-- Function to add points to Melee automatically
function addMeleePoints(points)
    local args = {
        [1] = "AddPoint",  -- Command to add points
        [2] = "Melee",     -- Type of point (Melee in this case)
        [3] = points       -- Number of points you want to add
    }

    -- Call InvokeServer to execute the command
    pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer(unpack(args))
        print("Successfully added Melee points!")
    end)
end

-- Function to equip item (like "Combat")
local player = game:GetService("Players")
local LocalPlayer = player.LocalPlayer  -- Ensure accessing the correct player

-- Function to equip a weapon (tool) to the character
equipitem = function(v)
    -- Check if the tool exists in the Backpack
    local tool = LocalPlayer.Backpack:FindFirstChild(v)
    if tool then
        -- If the tool exists, equip it to the character
        LocalPlayer.Character.Humanoid:EquipTool(tool)
        print(v .. " đã được trang bị!")
    else
        warn(v .. " không tồn tại trong Backpack!")
    end
end

-- Infinite loop to keep equipping the item
task.spawn(function()
    while true do
        equipitem("Combat")  -- Change "Combat" to the item name you want to equip
        task.wait(1)  -- Wait for 1 second before checking again (to prevent overload)
    end
end)

-- Global variable for auto farm
_G.AutoFarm = true

-- Main farming loop
task.spawn(function()
    while _G.AutoFarm do
        pcall(function()
            -- Kiểm tra và thực hiện quest
            if game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false then
                checkQuest()
                Tween(CFQ, 5)  -- Use tween-based teleport with 15 seconds duration
                getQ()
            elseif game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == true then
                checkQuest()
                if game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text:find(NameM) then
                    -- Attack and bring the enemy to position
                    if workspace.Enemies:FindFirstChild(NameM) then
                        for _, v in pairs(workspace.Enemies:GetChildren()) do
                            if v.Name == NameM then
                                if v.Humanoid.Health > 0 then
                                    if v:FindFirstChild("HumanoidRootPart") then
                                        repeat
                                            task.wait(0.01)
                                            BringMob(v.HumanoidRootPart.CFrame)
                                            TP(v.HumanoidRootPart.CFrame * CFrame.new(0, 40, 0))          
                                            FastAttack()
                                        until v.Humanoid.Health <= 0
                                    end
                                end  
                            end
                        end
                    end
                else
                    local args = {
                        [1] = "AbandonQuest"
                    }
                    game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer(unpack(args))
                end
            end
            -- Random fruit action every 5 seconds
            randomFruit()
        end)

        -- Add melee points every second
        addMeleePoints(1)

        -- Add defense points every second
        addDefensePoints(1)

        task.wait(1)
    end
end)

-- Function to check if Buso Haki is already active
function isBusoHakiActive()
    -- Replace this with the appropriate check if Buso Haki is on
    -- For example, checking a GUI element or player status
    return game:GetService("Players").LocalPlayer:FindFirstChild("BusoHakiStatus") and game:GetService("Players").LocalPlayer.BusoHakiStatus.Value == true
end

-- Function to automatically activate Buso Haki only once
function autoActivateBusoHakiOnce()
    if not isBusoHakiActive() then
        local args = {
            [1] = "Buso"  -- Command to activate Buso Haki
        }

        -- Activate Buso Haki
        local success, result = pcall(function()
            game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer(unpack(args))
        end)

        -- Check if the command was successful
        if success then
            print("Successfully activated Buso Haki.")
        else
            warn("Error activating Buso Haki: " .. tostring(result))
        end
    else
        print("Buso Haki is already active.")
    end
end

-- Function to handle character respawn and automatically activate Buso Haki
game:GetService("Players").LocalPlayer.CharacterAdded:Connect(function()
    -- Wait for the character to load
    wait(1)  -- Adjust the wait time as necessary
    -- Automatically activate Buso Haki upon respawn
    autoActivateBusoHakiOnce()
end)

-- Call the function to start auto-activating Buso Haki once when the script starts
autoActivateBusoHakiOnce()
