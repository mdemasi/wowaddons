-- BreathFrame: blue screen border while your breath timer is draining.

local CFG = {
    color       = { 0.15, 0.45, 1.0 }, -- normal border color (blue)
    dangerColor = { 1.0, 0.1, 0.1 },   -- color at 0% breath (red)
    redAt       = 0.4,                 -- start blending to red at 40%
    thickness   = 90,                  -- px, glow depth at full breath
    maxThickness= 350,                 -- px, glow depth at 0% breath
    growAt      = 0.4,                 -- start growing inward at 40%
    bandAlpha   = 0.12,                -- per-band opacity (overall strength)
    fadeIn      = 0.6,                 -- seconds to fade in
    flashAt     = 0.5,                 -- start flashing at 50% breath
    slowPeriod  = 2.0,                 -- seconds per flash at 50%
    fastPeriod  = 0.2,                 -- seconds per flash near 0%
}

local f = CreateFrame("Frame", "BreathFrameOverlay", WorldFrame)
f:SetAllPoints(WorldFrame)
f:SetFrameStrata("BACKGROUND")
f:EnableMouse(false)
f:Hide()

-- Fake a gradient with stacked solid bands (works on every client).
local BANDS = 10
local bands = {} -- { tex, side, index }
for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    for i = 1, BANDS do
        local t = f:CreateTexture(nil, "OVERLAY")
        if side == "TOP" then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT")
        elseif side == "BOTTOM" then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT")
        elseif side == "LEFT" then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT")
        else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT") end
        bands[#bands + 1] = { tex = t, horizontal = (side == "TOP" or side == "BOTTOM"), i = i }
    end
end

local function lerp(a, b, t) return a + (b - a) * t end

local lastR, lastThick
local function Style(frac)
    -- 0 above threshold -> 1 at empty
    local red  = frac < CFG.redAt  and (1 - frac / CFG.redAt)  or 0
    local grow = frac < CFG.growAt and (1 - frac / CFG.growAt) or 0
    local c, d = CFG.color, CFG.dangerColor
    local r, g, b = lerp(c[1], d[1], red), lerp(c[2], d[2], red), lerp(c[3], d[3], red)
    local thick = lerp(CFG.thickness, CFG.maxThickness, grow)
    if r == lastR and thick == lastThick then return end
    lastR, lastThick = r, thick
    local step = thick / BANDS
    for _, band in ipairs(bands) do
        band.tex:SetColorTexture(r, g, b, CFG.bandAlpha * (1 - (band.i - 1) / BANDS))
        if band.horizontal then band.tex:SetHeight(step * band.i) else band.tex:SetWidth(step * band.i) end
    end
end

-- Breath state, tracked from events (with polling fallback).
local B = { active = false }
local test -- { start, duration } when /breathframe test is running

local function SetBreath(value, maxValue, scale, paused)
    B.value, B.max, B.scale, B.paused = value, maxValue, scale or -1, paused
    B.stamp = GetTime()
    B.active = maxValue and maxValue > 0
end

local function Fraction()
    if test then
        local left = test.duration - (GetTime() - test.start)
        if left <= 0 then test = nil; return nil end
        return left / test.duration
    end
    if not B.active or not B.scale or B.scale >= 0 then return nil end
    local ms
    if GetMirrorTimerProgress then ms = GetMirrorTimerProgress("BREATH") end
    if not ms or ms <= 0 then
        ms = B.value
        if not B.paused or B.paused == 0 then
            ms = ms + B.scale * 1000 * (GetTime() - B.stamp)
        end
    end
    return math.max(0, math.min(1, ms / B.max))
end

local function Poll()
    if not GetMirrorTimerInfo then return end
    for i = 1, (MIRRORTIMER_NUMTIMERS or 3) do
        local timer, value, maxValue, scale, paused = GetMirrorTimerInfo(i)
        if timer == "BREATH" then
            if not B.active or B.scale ~= scale then SetBreath(value, maxValue, scale, paused) end
            return
        end
    end
    B.active = false
end

local phase, pollAcc, fade = 0, 0, 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
    pollAcc = pollAcc + elapsed
    if pollAcc > 0.25 then pollAcc = 0; Poll() end

    local frac = Fraction()
    if not frac then f:Hide(); phase, fade = 0, 0; return end
    if not f:IsShown() then fade = 0; f:Show() end
    fade = math.min(1, fade + elapsed / CFG.fadeIn)

    Style(frac)

    local alpha = 1
    if frac <= CFG.flashAt then
        local urgency = 1 - frac / CFG.flashAt
        local period = lerp(CFG.slowPeriod, CFG.fastPeriod, urgency)
        phase = (phase + elapsed / period) % 1
        local pulse = 0.5 + 0.5 * math.cos(phase * 2 * math.pi)
        alpha = 0.15 + 0.85 * pulse
    else
        phase = 0
    end
    f:SetAlpha(alpha * fade)
end)

driver:RegisterEvent("MIRROR_TIMER_START")
driver:RegisterEvent("MIRROR_TIMER_PAUSE")
driver:RegisterEvent("MIRROR_TIMER_STOP")
driver:SetScript("OnEvent", function(_, event, name, a, b, c, d)
    if name ~= "BREATH" then return end
    if event == "MIRROR_TIMER_START" then
        SetBreath(a, b, c, d)
    elseif event == "MIRROR_TIMER_PAUSE" then
        B.paused = a
    else
        B.active = false
    end
end)

SLASH_BREATHFRAME1 = "/breathframe"
SlashCmdList.BREATHFRAME = function(msg)
    msg = (msg or ""):lower()
    if msg == "test" then
        test = { start = GetTime(), duration = 20 }
        print("|cff3399ffBreathFrame|r: 20s test (flash at 10s, red + grow at 8s).")
    elseif msg == "stop" then
        test = nil
    else
        print("|cff3399ffBreathFrame|r loaded. Commands: /breathframe test | stop")
    end
end
