local hook = hook

local AddHook = hook.Add
local PlayerIterator = player.Iterator

local client = nil

------------------
-- TRANSLATIONS --
------------------

AddHook("Initialize", "Sniffler_Translations_Initialize", function()
    -- Weapons
    LANG.AddToLanguage("english", "snfscanner_help_pri", "Look at a player to start scanning.")
    LANG.AddToLanguage("english", "snfscanner_help_sec", "Keep line of sight or you will lose your target.")
    LANG.AddToLanguage("english", "snfscanner_inv",      "INVENTORY")
    LANG.AddToLanguage("english", "snfscanner_shop",     "SHOP WEAPONS")
    LANG.AddToLanguage("english", "snfscanner_roleweps", "ROLE WEAPONS")

    -- Rescan cooldown message
    LANG.AddToLanguage("english", "snfscanner_rescan_part_1", "WAIT ")
    LANG.AddToLanguage("english", "snfscanner_rescan_part_2", " TO SCAN AGAIN")

    -- ConVars
    LANG.AddToLanguage("english", "sniffler_config_show_radius", "Show tracking radius circle")

    -- Cheat Sheet
    LANG.AddToLanguage("english", "cheatsheet_desc_sniffler", "Can scan other players to learn whether they have any interesting items.")

    -- Popup
    LANG.AddToLanguage("english", "info_popup_sniffler", [[You are {role}!

Hold out your scanner while looking at a player to learn more about them.]])
end)

-------------
-- CONVARS --
-------------

local sniffler_scanner_time     = GetConVar("ttt_sniffler_scanner_time")
local sniffler_requires_scanner = GetConVar("ttt_sniffler_requires_scanner")

local sniffler_show_scan_radius  = CreateClientConVar("ttt_sniffler_show_scan_radius", "0", true, false, "Whether the scan radius circle should show", 0, 1)
local sniffler_lootrole_distance = CreateConVar("ttt_sniffler_lootrole_distance", "300", FCVAR_NONE, "The distance within which the sniffler will detect loot roles", 100, 10000)

local function Sniffler_TTTSettingsRolesTabSections(role, parentForm)
    if role ~= ROLE_SNIFFLER then return end

    parentForm:CheckBox(LANG.GetTranslation("sniffler_config_show_radius"), "ttt_sniffler_show_scan_radius")
    return true
end

-----------------
-- SCANNER HUD --
-----------------

local function GetTargetScanTime(target)
    local scanner_time = sniffler_scanner_time:GetInt()
    if not target or not IsPlayer(target) then
        return scanner_time
    end

    return scanner_time
end

local function Sniffler_HUDPaint()
    if not client then
        client = LocalPlayer()
    end

    if not IsValid(client) or client:IsSpec() or GetRoundState() ~= ROUND_ACTIVE then return end
    if not client:IsSniffler() then return end

    if not sniffler_requires_scanner:GetBool() or (client.GetActiveWeapon and IsValid(client:GetActiveWeapon()) and client:GetActiveWeapon():GetClass() == "weapon_inf_scanner") then
        local state = client:GetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_IDLE)

        if sniffler_show_scan_radius:GetBool() then
            surface.DrawCircle(ScrW() / 2, ScrH() / 2, math.Round(ScrW() / 6), 0, 255, 0, 155)
        end

        if state == SNIFFLER_SCANNER_IDLE then
            return
        end

        local target = player.GetBySteamID64(client:GetNWString("TTTSnifflerScannerTarget", ""))
        local scan = GetTargetScanTime(target)
        local time = client:GetNWFloat("TTTSnifflerScannerStartTime", -1) + scan

        local x = ScrW() / 2.0
        local y = ScrH() / 2.0

        y = y + (y / 3)

        local w = 400

        local T = LANG.GetTranslation
        local titles = {T("snfscanner_inv"), T("snfscanner_shop"), T("snfscanner_roleweps")}

        if state == SNIFFLER_SCANNER_LOCKED or state == SNIFFLER_SCANNER_SEARCHING then
            if time < 0 then return end

            local color = Color(255, 255, 0, 155)
            if state == SNIFFLER_SCANNER_LOCKED then
                color = Color(0, 255, 0, 155)
            end

            local targetState = target:GetNWInt("TTTSnifflerScanStage", SNIFFLER_UNSCANNED)

            local cc = math.min(1, 1 - ((time - CurTime()) / scan))
            local progress = (cc + targetState) / 3

            CRHUD:PaintProgressBar(x, y, w, color, client:GetNWString("TTTSnifflerScannerMessage", ""), progress, 3, titles)
        elseif state == SNIFFLER_SCANNER_LOST then
            local color = Color(200 + math.sin(CurTime() * 32) * 50, 0, 0, 155)
            CRHUD:PaintProgressBar(x, y, w, color, client:GetNWString("TTTSnifflerScannerMessage", ""), 1, 3, titles)
        elseif state == SNIFFLER_SCANNER_WAITING then
            local color = Color(200 + math.sin(CurTime() * 16) * 50, 0, 0, 155)

            local rescanTime = client:GetNWFloat("TTTSnifflerRescanTime_" .. target:SteamID64(), 0)
            local timeLeftRaw = math.max(0, rescanTime - CurTime())

            local timeLeftRounded = math.ceil(timeLeftRaw)
            local mins = math.floor(timeLeftRounded / 60)
            local secs = timeLeftRounded % 60
            local timeLeftString = string.format("%02d:%02d", mins, secs)

            local totalCooldownTime = GetConVar("ttt_sniffler_rescan_time"):GetFloat()
            local progress = 0
            if totalCooldownTime > 0 then
                progress = timeLeftRaw / totalCooldownTime
            end

            local message = T("snfscanner_rescan_part_1") .. timeLeftString .. T("snfscanner_rescan_part_2")

            CRHUD:PaintProgressBar(x, y, w, color, message, progress, 1, {timeLeftString})
        end
    end
end

-------------------------
-- LOOT ROLE DETECTION --
-------------------------

local heartbeat1, heartbeat2

local function CreateHeartbeats(ply)
    if not heartbeat1 then
        heartbeat1 = CreateSound(ply, "sniffler/heartbeat1.wav")
    end
    if not heartbeat2 then
        heartbeat2 = CreateSound(ply, "sniffler/heartbeat2.wav")
    end
end

local nextBeatTime = 0
local beatState = 0

local function PlayHeartbeat(ply)
    CreateHeartbeats(ply)

    local proximity = ply.lootRoleProximity or 0
    if proximity <= 0 then
        beatState = 0
        return
    end

    local now = CurTime()
    if now < nextBeatTime then return end

    local beatGap = Lerp(proximity, 0.35, 0.15)
    local pairGap = Lerp(proximity, 1.2, 0.3)
    local pitch   = Lerp(proximity, 50, 110)
    local volume  = Lerp(proximity, 0.7, 1.0)

    if beatState == 0 then
        heartbeat1:Stop()
        heartbeat1:PlayEx(volume, pitch)

        beatState = 1
        nextBeatTime = now + beatGap
    elseif beatState == 1 then
        heartbeat2:Stop()
        heartbeat2:PlayEx(volume, pitch)

        beatState = 0
        nextBeatTime = now + pairGap
    end
end

local function SeekLootRoles()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    timer.Create("TTTSniffler_LootRolesTimer_" .. ply:SteamID64(), 0, 0, function()
        if not IsValid(ply) or not ply:Alive() or ply:IsSpec() then return end

        local range = sniffler_lootrole_distance:GetInt()
        local rangeSqr = range * range

        local closestTarget = nil
        local minDistSqr = math.huge

        for _, target in PlayerIterator() do
            if not IsValid(target) or target == ply then continue end
            if not target:Alive() or target:IsSpec() then continue end
            if not (target:IsActiveLootGoblin() or target:IsPinata()) then continue end

            local distSqr = ply:GetPos():DistToSqr(target:GetPos())
            if distSqr < minDistSqr then
                minDistSqr = distSqr
                closestTarget = target
            end
        end

        ply.closestTarget = closestTarget
        ply.closestTargetDistSqr = minDistSqr

        if IsValid(closestTarget) and minDistSqr <= rangeSqr then
            local distance = math.sqrt(minDistSqr)
            ply.lootRoleProximity = 1 - (distance / range)
        else
            ply.lootRoleProximity = 0
        end

        PlayHeartbeat(ply)
    end)
end

local function Sniffler_RenderLootOverlay()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:IsSniffler() then return end

    local intensity = ply.lootRoleProximity or 0
    if intensity <= 0 then return end

    DrawColorModify({
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] =  -intensity * 0.05,
        ["$pp_colour_contrast"] = 1 + (intensity * 0.2),
        ["$pp_colour_colour"] = 1 - (intensity * 0.2),
        ["$pp_colour_mulr"] = intensity * 0.5,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0
    })

    DrawColorModify({
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = intensity * -0.5,
        ["$pp_colour_addb"] = intensity * -0.5,
        ["$pp_colour_brightness"] = 0,
        ["$pp_colour_contrast"] = 1,
        ["$pp_colour_colour"] = 1,
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0
    })

    DrawMotionBlur(0.1, intensity * 0.4, 0.01)

    if intensity > 0.01 then
        local passes = math.ceil(intensity * 3)
        local blurHeight = ScrH() * intensity * 0.5
        DrawToyTown(passes, blurHeight)
    end
end

local function Night_SetupWorldFog()
    local intensity = LocalPlayer().lootRoleProximity or 0

    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogMaxDensity(intensity)
    render.FogColor(0, 0, 0)
    render.FogStart(50 + ((1 - intensity) * 1000))
    render.FogEnd(600 + ((1 - intensity) * 1000))
    return true
end

local function Night_SetupSkyboxFog(scale)
    local intensity = LocalPlayer().lootRoleProximity or 0

    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogMaxDensity(intensity)
    render.FogColor(0, 0, 0)
    render.FogStart(50 + ((1 - intensity) * 1000))
    render.FogEnd(600 + ((1 - intensity) * 1000))
    return true
end

local function HasSniffler()
    for _, v in PlayerIterator() do
        if v:IsSniffler() then
            return true
        end
    end
    return false
end

AddHook("TTTBeginRound", "Sniffler_TTTBeginRound_Client", function()
    if not HasSniffler() then return end

    if LocalPlayer():IsSniffler() then
        AddHook("RenderScreenspaceEffects", "Sniffler_RenderLootOverlay", Sniffler_RenderLootOverlay)
        AddHook("SetupSkyboxFog", "RdmtJoelBotC_Night_SetupSkyboxFog", Night_SetupSkyboxFog)
        AddHook("SetupWorldFog", "RdmtJoelBotC_Night_SetupWorldFog", Night_SetupWorldFog)
        SeekLootRoles()
    end
end)

-------------
-- CLEANUP --
-------------

AddHook("TTTPrepareRound", "Sniffler_TTTPrepareRound_Client", function()
    local ply = LocalPlayer()
    if IsValid(ply) then
        timer.Remove("TTTSniffler_LootRolesTimer_" .. ply:SteamID64())
        ply.lootRoleProximity = 0
        ply.closestTarget = nil
        ply.closestTargetDistSqr = math.huge
    end

    hook.Remove("HUDPaint", "Sniffler_DrawLootVignette")
    hook.Remove("RenderScreenspaceEffects", "Sniffler_RenderLootOverlay")
    hook.Remove("SetupSkyboxFog", "RdmtJoelBotC_Night_SetupSkyboxFog")
    hook.Remove("SetupWorldFog", "RdmtJoelBotC_Night_SetupWorldFog")

    if heartbeat1 then heartbeat1:Stop() end
    if heartbeat2 then heartbeat2:Stop() end
    beatState = 0
    nextBeatTime = 0
end)

--------------
-- TUTORIAL --
--------------

AddHook("TTTTutorialRoleText", "Sniffler_TTTTutorialRoleText", function(role, titleLabel)
    if role == ROLE_SNIFFLER then
        local roleColor = ROLE_COLORS[ROLE_SNIFFLER]
        local html = "The " .. ROLE_STRINGS[ROLE_SNIFFLER] .. " is a member of the <span style='color: rgb(" .. roleColor.r .. ", " .. roleColor.g .. ", " .. roleColor.b .. ")'>traitor team</span> whose goal is to learn more about their enemies using their <span style='color: rgb(" .. roleColor.r .. ", " .. roleColor.g .. ", " .. roleColor.b .. ")'>"
        if sniffler_requires_scanner:GetBool() then
            html = html .. "scanner"
        else
            html = html .. "scanning ability"
        end
        html = html .. "</span>."

        local scanner_circle_state
        local scanner_circle_state_opposite
        local scannerColor
        if sniffler_show_scan_radius:GetBool() then
            scanner_circle_state = "enabled"
            scanner_circle_state_opposite = "disabled"
            scannerColor = ROLE_COLORS[ROLE_INNOCENT]
        else
            scanner_circle_state = "disabled"
            scanner_circle_state_opposite = "enabled"
            scannerColor = ROLE_COLORS[ROLE_TRAITOR]
        end
        html = html .. "<span style='display: block; margin-top: 10px;'>The scan area circle is currently <span style='color: rgb(" .. scannerColor.r .. ", " .. scannerColor.g .. ", " .. scannerColor.b .. ")'>" .. scanner_circle_state .. "</span> but can be " .. scanner_circle_state_opposite .. " on the role settings tab of this window.</span>"

        return html
    end
end)

------------------
-- REGISTRATION --
------------------

ROLE_REGISTERED_HOOKS[ROLE_SNIFFLER] = {
    ["HUDPaint"] = Sniffler_HUDPaint,
    ["TTTScoreboardPlayerRole"] = Sniffler_TTTScoreboardPlayerRole,
    ["TTTSettingsRolesTabSections"] = Sniffler_TTTSettingsRolesTabSections,
}