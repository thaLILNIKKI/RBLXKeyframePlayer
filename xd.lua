-- KeyframePlayer Loadstring Bundle (ИСПРАВЛЕННАЯ ВЕРСИЯ ДЛЯ BONE'ов)
-- Copyright (c) 2024 RAMPAGE Interactive, all rights reserved.
-- Written by vq9o and Contributor(s), modified for Bone support
--
-- GitHub: https://github.com/RAMPAGELLC/RBLXKeyframePlayer
-- License: MIT
--
-- INSTALLATION:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/thaLILNIKKI/RBLXKeyframePlayer/main/loadstring-bundle.luau"))()
--
-- USAGE:
-- local KeyframePlayer = loadstring(game:HttpGet("https://raw.githubusercontent.com/thaLILNIKKI/RBLXKeyframePlayer/main/loadstring-bundle.luau"))()
-- local animation = KeyframePlayer:LoadAnimation(humanoid, keyframeSequence)
-- animation:Play()

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- ============================================
-- GoodSignal Module
-- ============================================

local GoodSignal = {}
GoodSignal.__index = GoodSignal

function GoodSignal.new()
    local self = setmetatable({}, GoodSignal)
    self._bindable = Instance.new("BindableEvent")
    return self
end

function GoodSignal:Connect(callback)
    return self._bindable.Event:Connect(callback)
end

function GoodSignal:Wait()
    return self._bindable.Event:Wait()
end

function GoodSignal:Fire(...)
    self._bindable:Fire(...)
end

function GoodSignal:Destroy()
    self._bindable:Destroy()
end

-- ============================================
-- KeyframeSequenceAnimation Module
-- ============================================

local DebugEnabled = true

local Animation = {}
Animation.__index = Animation

local function _debug(...)
    if RunService:IsStudio() and DebugEnabled then
        warn("KeyframePlayer Debug: ", ...)
    end
end

function Animation.new(humanoid, keyframeSequence)
    local self = setmetatable({}, Animation)
    self.Humanoid = humanoid
    self.Sequence = keyframeSequence

    self.IsPlaying = false
    self.Looped = false
    self.Priority = keyframeSequence.Priority or 0
    self.Speed = 1
    self.TimePosition = 0
    self.WeightCurrent = 1
    self.WeightTarget = 1
    self.Length = self:GetSequenceLength()

    self.MarkerReachedSignal = GoodSignal.new()
    self.DidLoopSignal = GoodSignal.new()
    self.EndedSignal = GoodSignal.new()
    self.StoppedSignal = GoodSignal.new()
    self.PausedSignal = GoodSignal.new()

    return self
end

function Animation:GetSequenceLength()
    local maxTime = 0
    for _, keyframe in ipairs(self.Sequence:GetChildren()) do
        if keyframe:IsA("Keyframe") and keyframe.Time > maxTime then
            maxTime = keyframe.Time
        end
    end
    return maxTime
end

function Animation:Resume()
    if not self.IsPlaying then
        self.IsPlaying = true
        self:Play(nil, self.WeightCurrent, self.Speed)
    end
end

function Animation:Pause()
    self.IsPlaying = false
    self.PausedSignal:Fire()
end

function Animation:AdjustSpeed(newSpeed)
    if newSpeed > 0 then
        self.Speed = newSpeed
    end
end

function Animation:AdjustWeight(weight, fadeTime)
    self.WeightTarget = weight
    if fadeTime then
        local startWeight = self.WeightCurrent
        local endTime = tick() + fadeTime
        while tick() < endTime and self.IsPlaying do
            local elapsed = math.min(1, (fadeTime - (endTime - tick())) / fadeTime)
            self.WeightCurrent = startWeight + ((weight - startWeight) * elapsed)
            RunService.Heartbeat:Wait()
        end
    else
        self.WeightCurrent = weight
    end
end

function Animation:GetTimeOfKeyframe(keyFrameName)
    for _, keyframe in ipairs(self.Sequence:GetChildren()) do
        if keyframe.Name == keyFrameName then
            return keyframe.Time
        end
    end
    return 0
end

function Animation:GetMarkerReachedSignal(name)
    return self.MarkerReachedSignal
end

function Animation:DidLoop()
    return self.DidLoopSignal
end

function Animation:Ended()
    return self.EndedSignal
end

function Animation:Stopped()
    return self.StoppedSignal
end

function Animation:Paused()
    return self.PausedSignal
end

function Animation:GetKeyframeAtTime(timePosition)
    local closestKeyframe = nil
    local closestTimeDifference = math.huge
    for _, keyframe in ipairs(self.Sequence:GetChildren()) do
        if keyframe:IsA("Keyframe") then
            local timeDifference = math.abs(keyframe.Time - timePosition)
            if timeDifference < closestTimeDifference then
                closestKeyframe = keyframe
                closestTimeDifference = timeDifference
            end
        end
    end
    return closestKeyframe
end

function Animation:Stop(fadeTime)
    fadeTime = fadeTime or 0.1
    if not self.IsPlaying then
        warn("Animation is not currently playing.")
        return
    end
    self.IsPlaying = false
    local initialWeight = self.WeightCurrent
    local startTime = os.clock()
    local endTime = startTime + fadeTime
    coroutine.wrap(function()
        while os.clock() < endTime do
            local alpha = (os.clock() - startTime) / fadeTime
            self.WeightCurrent = initialWeight * (1 - alpha)
            RunService.Heartbeat:Wait()
        end
        self.WeightCurrent = 0
        self.StoppedSignal:Fire()
    end)()
end

function Animation:Play(fadeTime, weight, speed)
    fadeTime = fadeTime or 0.1
    weight = weight or 1.0
    speed = speed or 1.0

    if self.IsPlaying then
        warn("Animation is already playing.")
        return
    end

    self.IsPlaying = true
    self.Speed = speed
    self.WeightTarget = weight
    self.WeightCurrent = 0

    local initialWeight = self.WeightCurrent
    local startTime = os.clock()
    local endTime = startTime + fadeTime

    coroutine.wrap(function()
        while os.clock() < endTime and self.IsPlaying do
            local alpha = (os.clock() - startTime) / fadeTime
            self.WeightCurrent = initialWeight + (weight - initialWeight) * alpha
            self.TimePosition = self.TimePosition + (self.Speed * RunService.Heartbeat:Wait())
            self:ApplyInterpolatedPose(
                self.Humanoid,
                self:GetKeyframeAtTime(self.TimePosition),
                self:GetNextKeyframe(self:GetKeyframeAtTime(self.TimePosition)),
                alpha
            )
        end
        self.WeightCurrent = weight
        self:ApplyPose(self.Humanoid, self:GetKeyframeAtTime(self.TimePosition))
        self.MarkerReachedSignal:Fire("Play")

        while self.IsPlaying and self.TimePosition < self.Length do
            local nextKeyframe = self:GetNextKeyframe(self:GetKeyframeAtTime(self.TimePosition))
            if nextKeyframe then
                local waitTime = (nextKeyframe.Time - self.TimePosition) / math.abs(self.Speed)
                if waitTime > 0 then
                    task.wait(waitTime)
                end
                self.TimePosition = nextKeyframe.Time
                self:ApplyPose(self.Humanoid, nextKeyframe)
                for _, marker in ipairs(nextKeyframe:GetChildren()) do
                    if marker:IsA("Marker") then
                        self.MarkerReachedSignal:Fire(marker.Name)
                    end
                end
            else
                break
            end
            if self.Looped and self.TimePosition >= self.Length then
                self.DidLoopSignal:Fire()
                self.TimePosition = 0
            end
            RunService.Heartbeat:Wait()
        end

        if not self.Looped then
            self:Stop()
            self.EndedSignal:Fire()
        end
    end)()
end

-- ============================================
-- ИСПРАВЛЕННАЯ ФУНКЦИЯ ДЛЯ BONE'ов
-- ============================================

function Animation:ApplyPose(humanoid, keyframe)
    if keyframe == nil or not keyframe:IsA("Keyframe") then
        return
    end

    for _, pose in ipairs(keyframe:GetChildren()) do
        if pose:IsA("Pose") then
            self:ApplyPoseToPart(humanoid, pose)
        end
    end
end

function Animation:ApplyPoseToPart(humanoid, pose)
    if pose == nil or not pose:IsA("Pose") then
        return
    end

    local part = humanoid.Parent:FindFirstChild(pose.Name)
    if not part or not part:IsA("BasePart") then
        warn("Part not found: " .. tostring(pose.Name))
        return
    end

    -- 🔥 ИСПРАВЛЕНИЕ: Ищем Bone внутри part
    local bone = nil
    for _, descendant in ipairs(part:GetDescendants()) do
        if descendant:IsA("Bone") then
            bone = descendant
            break
        end
    end

    -- Если Bone не найден, ищем Motor6D
    if not bone then
        for _, descendant in ipairs(humanoid.Parent:GetDescendants()) do
            if descendant:IsA("Motor6D") and descendant.Part1 == part then
                bone = descendant
                break
            end
        end
    end

    if bone then
        bone.Transform = pose.CFrame
        _debug("Applied pose to:", bone.Name, "for part:", part.Name)
    else
        warn("Bone or Motor6D not found for part: " .. part.Name)
    end
end

function Animation:GetNextKeyframe(currentKeyframe)
    local nextKeyframe = nil
    for _, keyframe in ipairs(self.Sequence:GetChildren()) do
        if keyframe:IsA("Keyframe") and keyframe.Time > currentKeyframe.Time then
            if not nextKeyframe or keyframe.Time < nextKeyframe.Time then
                nextKeyframe = keyframe
            end
        end
    end
    return nextKeyframe
end

function Animation:ApplyInterpolatedPose(humanoid, currentKeyframe, nextKeyframe, alpha)
    if not currentKeyframe or not nextKeyframe then
        self:ApplyPose(humanoid, currentKeyframe or nextKeyframe)
        return
    end

    for _, currentPose in ipairs(currentKeyframe:GetChildren()) do
        if not currentPose:IsA("Pose") then
            continue
        end

        local nextPose = nextKeyframe:FindFirstChild(currentPose.Name)
        if nextPose and nextPose:IsA("Pose") then
            local part = humanoid.Parent:FindFirstChild(currentPose.Name)
            if part and part:IsA("BasePart") then
                -- 🔥 ИСПРАВЛЕНИЕ: Ищем Bone внутри part
                local bone = nil
                for _, descendant in ipairs(part:GetDescendants()) do
                    if descendant:IsA("Bone") then
                        bone = descendant
                        break
                    end
                end

                if not bone then
                    for _, descendant in ipairs(humanoid.Parent:GetDescendants()) do
                        if descendant:IsA("Motor6D") and descendant.Part1 == part then
                            bone = descendant
                            break
                        end
                    end
                end

                if bone then
                    local interpolatedCFrame = currentPose.CFrame:Lerp(nextPose.CFrame, alpha)
                    bone.Transform = interpolatedCFrame
                    _debug("Interpolated pose applied to:", bone.Name, "for part:", part.Name)
                else
                    warn("Bone or Motor6D not found for part: " .. part.Name)
                end
            else
                warn("Part not found or not a BasePart: " .. tostring(currentPose.Name))
            end
        end
    end
end

-- ============================================
-- KeyframePlayer Main Module
-- ============================================

local KeyframePlayer = {}

function KeyframePlayer:LoadAnimation(humanoid, keyframeSequence)
    return Animation.new(humanoid, keyframeSequence)
end

return KeyframePlayer
