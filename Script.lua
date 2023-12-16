local module = {}

--[[Connection required services]]
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local Players = game:GetService("Players")

--[[Connecting the necessary modules]]
local Utils_RS = require(RS.Utils_RS) 
local Laser_RS = require(RS.Laser_RS) 

local CurrentCamera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

--[[Tables for storing connections, in order to later clean up these 
connections when they are no longer needed, to avoid memory leaks.]]
local ConT = {Con = {}, Num = 0}

--[[Weapon initialization function for interacting with slimes]]
function module.Init(ChrT, ViewModelT)	

	local Anim = Instance.new("Animation")
	Anim.AnimationId = "rbxassetid://15372380997"

	--[[Loading animations of holding weapons for the character and for the view model.]]
   local HoldAnimTrack = ChrT.Animator:LoadAnimation(Anim)
	HoldAnimTrack:Play()	
	local HoldAnimTrackVM = ViewModelT.Animator:LoadAnimation(Anim)
	HoldAnimTrackVM:Play()	

   --[[We clone a weapon to interact with slimes from the replication storage and attach 
   it to the right hand of the model. And also in the server script the same thing happens, 
   but the attachment goes to the right hand of the character himself, 
   so that other players can also see the weapon.]]   
   local VacPac = RS.VacPac.VacPac:Clone()
	local Motor6D = Instance.new("Motor6D")
	Motor6D.Part0 = ViewModelT.RightArm
	Motor6D.Part1 = VacPac.Handle
	Motor6D.Parent = ViewModelT.RightArm
	VacPac.Parent = ViewModelT.VmChr

	local M1btnPress, M2btnPress = false, false
	local Main = VacPac.Main
	local FireAttach = Main.FireAttach

	local BigWheelM6d = Main.BigWheel
	local SmallWheelM6d = Main.SmallWheel

	local RotateS = Main.RotateS

	--[[Parameters that are used for the function workspace:GetPartBoundsInBox, 
   Only those parts that are in the folder(workspace.OBJ) will be found]] 
   local DragOutParams = OverlapParams.new()
	DragOutParams.FilterType = Enum.RaycastFilterType.Include
	DragOutParams.MaxParts = 100
	DragOutParams.FilterDescendantsInstances = {workspace.OBJ}
  
   --[[parameters for the function workspace:Raycast, excluding character]] 
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {ChrT.Chr}

   --[[When the left mouse button is pressed, the weapon begins to attract slimes to itself 
   using AlignPosition, and when the player releases the left mouse button, 
   all AlignPositions are turned off and the slimes continue to move freely. 
   And also the release of the left mouse button is reported to the server through a 
   remote event.]] 
	local SlimeAPosT = {}
	local function SlimeAPosDisable()
		for obj,v in SlimeAPosT do
			if not obj then continue end
			obj:SetAttribute("IsDragging", false)
			v.Enabled = false
			RS.EVENTS.VACPAC.DragOutEndE:FireServer(obj)				
		end		
	end

	--[[We create an event to detect user input.]] 
   ConT.Num+=1
	ConT.Con[ConT.Num] = UIS.InputBegan:Connect(function(input, gameProcessed)	

		-- gameProcessed Click on gui return true
		if gameProcessed then return end
		
      --[[Checking the mouse and joystick button presses]]
		if input.UserInputType == Enum.UserInputType.MouseButton1 or 
			input.KeyCode == Enum.KeyCode.ButtonR1 then			
			M1btnPress = true
			RotateS:Play()

			--[[A loop that will run while the left mouse button is pressed]]
         while ChrT.Hum.Health > 0 and M1btnPress do 

				--[[Rotation of 6D motors on weapons]]
            BigWheelM6d.C0 *= CFrame.fromOrientation(0,0,math.rad(5))
				SmallWheelM6d.C0 *= CFrame.fromOrientation(0,0,math.rad(-5))
			
			
         	local SlimeAPosInZoneT = {}
          	--[[Position where the camera is looking at 30 studs]]
            local posEnd = CurrentCamera.CFrame.Position + CurrentCamera.CFrame.LookVector*30 

				--[[When a weapon shoots at water, water is created on the server and the gun attracts it.]]
            local raycastResult = workspace:Raycast(CurrentCamera.CFrame.Position, CurrentCamera.CFrame.LookVector*30 , raycastParams)
				if raycastResult then
					if raycastResult.Material == Enum.Material.Water then 
						RS.EVENTS.VACPAC.CrtWaterE:FireServer(raycastResult.Position)	
					end
				end

				--[[Function that uses workspace:GetPartBoundsInBox, to find slimes in a certain area of ​​action and attract them to you.]]
            local partsT = Laser_RS.Laser2(FireAttach.WorldPosition,  posEnd, 8, DragOutParams)

				for k,part in partsT do
				
               --[[ looking for a part with a name Main]]
               if part.Name ~= "Main" then continue end
					local model = part.Parent					
					if not model then continue end 
					if not model:GetAttribute("CanBeSucked") then continue end 
					model:SetAttribute("IsDragging", true)
					RS.EVENTS.VACPAC.DragOutBegE:FireServer(model)

              --[[ Inside the PrimaryPart we find AlignPosition]]
					local PrimaryPart = model.PrimaryPart
					local AlignPosition = PrimaryPart:FindFirstChild("AlignPosition")
					if not AlignPosition then continue end
					AlignPosition.Position = PrimaryPart.Position
					AlignPosition.Enabled = true				
					
              --[[This table is used in the function SlimeAPosDisable]]
               SlimeAPosT[model] = AlignPosition
					
               --[[Table for saving AlignPosition, which must be turned off 
               if the slimes leave the action area while the weapon is working.]]
               SlimeAPosInZoneT[model] = AlignPosition

					
               --[[The code below is needed to use Orientation to move the slime 
               to the weapon that attracts them. Sine and cosine are needed for 
               slimes to move beautifully along curved trajectories. 
               vectorToObjectSpace - needed so that the movement occurs relative to the camera,
                and not world coordinates. ]]
               local now = os.clock()
					local Sin = 13
					local Cos = 10
					local bobble_X = math.cos(now * Cos) * 0.05
					local bobble_Y = math.sin(now * Sin) * 0.1
					local bobble_Z = math.cos(now * Cos) * 0.3

					local bobbleV3 = Vector3.new(bobble_X, bobble_Y , bobble_Z) 
					bobbleV3 = CurrentCamera.CFrame:vectorToObjectSpace(bobbleV3)
					local mag = (FireAttach.WorldPosition - PrimaryPart.Position).Magnitude 
					local direction = (FireAttach.WorldPosition - PrimaryPart.Position).Unit 
					local speed = 0.3
					local timeFly = mag/(speed*60)						
					AlignPosition.Position+= direction*speed +bobbleV3	

					--[[You get slime when the distance is less than seven]]
               if LocalPlayer:DistanceFromCharacter(PrimaryPart.Position) < 7 then 
						RS.EVENTS.VACPAC.DragOutE:FireServer(model)	
					end					
				end

            --[[Release the slimes out of range of the weapon.]] 
				for k,v in SlimeAPosT do	
					local AP = SlimeAPosInZoneT[k] 
					if not AP then 
						v.Enabled = false											
					end
				end		
				table.clear(SlimeAPosInZoneT)
				task.wait()	
			end
		end

		--[[When you hold down the right mouse button you shoot slime]] 
		if input.UserInputType == Enum.UserInputType.MouseButton2 or 
			input.KeyCode == Enum.KeyCode.ButtonR2 then	
			M2btnPress = true
			while ChrT.Hum.Health > 0 and M2btnPress do 
				local direction = CurrentCamera.CFrame.LookVector
				RS.EVENTS.VACPAC.ShotE:FireServer(direction)
				--print(LocalPlayer)
				task.wait(0.2)	
			end
		end
	end)


	ConT.Num+=1
	ConT.Con[ConT.Num] = UIS.InputEnded:Connect(function(input, gameProcessed)	
		--[[When you release the left mouse button]] 
      if input.UserInputType == Enum.UserInputType.MouseButton1 or 
			input.KeyCode == Enum.KeyCode.ButtonR1 then	
			M1btnPress = false
			RotateS:Stop()
			SlimeAPosDisable()			
			table.clear(SlimeAPosT)	
		end
   --[[When you release the right mouse button]] 
		if input.UserInputType == Enum.UserInputType.MouseButton2 or 
			input.KeyCode == Enum.KeyCode.ButtonR2  then	
			M2btnPress = false	
		end
	end)	

	--[[The event receives a signal from the server when fired and uses the impulse to move the slime.]] 
   ConT.Num+=1
	ConT.Con[ConT.Num] = RS.EVENTS.VACPAC.ShotE.OnClientEvent:Connect(function(Model)
		local direction = CurrentCamera.CFrame.LookVector
		local Mass = Utils_RS.Model.GetMass(Model)	
		Model.PrimaryPart:ApplyImpulse(direction*50*Mass + Vector3.new(0,20*Mass,0))
	end) 
end
--[[We use the function to clean up events to avoid memory leaks.]]
function module.Finalize()	
	for k, v in ConT.Con do		
		v:Disconnect()			
	end		
	ConT.Num = 0
	table.clear(ConT.Con)		
end

return module

