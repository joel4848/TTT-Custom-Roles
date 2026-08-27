local hook = hook

local AddHook = hook.Add

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

local sniffler_scanner_time = GetConVar("ttt_sniffler_scanner_time")
local sniffler_requires_scanner = GetConVar("ttt_sniffler_requires_scanner")

local sniffler_show_scan_radius = CreateClientConVar("ttt_sniffler_show_scan_radius", "0", true, false, "Whether the scan radius circle should show", 0, 1)

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

    ["PostDrawTranslucentRenderables"] = Sniffler_PostDrawTranslucentRenderables
}