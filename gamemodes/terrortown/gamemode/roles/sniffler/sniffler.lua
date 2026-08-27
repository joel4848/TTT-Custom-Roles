AddCSLuaFile()

local hook    = hook
local IsValid = IsValid
local player  = player

local AddHook        = hook.Add
local PlayerIterator = player.Iterator

-------------
-- CONVARS --
-------------

local sniffler_scanner_float_time = CreateConVar("ttt_sniffler_scanner_float_time", "1", FCVAR_NONE, "The amount of time (in seconds) it takes for the sniffler's scanner to lose its target without line of sight", 0, 60)
local sniffler_scanner_cooldown   = CreateConVar("ttt_sniffler_scanner_cooldown", "3", FCVAR_NONE, "The amount of time (in seconds) the sniffler's tracker goes on cooldown for after losing its target", 0, 60)
local sniffler_scanner_distance   = CreateConVar("ttt_sniffler_scanner_distance", "300", FCVAR_NONE, "The maximum distance away the scanner target can be", 100, 2000)

local sniffler_requires_scanner = GetConVar("ttt_sniffler_requires_scanner")
local sniffler_scanner_time     = GetConVar("ttt_sniffler_scanner_time")

------------------
-- ROLE WEAPONS --
------------------

-- Only allow the sniffler to pick up sniffler-specific weapons
local function Sniffler_Weapons_PlayerCanPickupWeapon(ply, wep)
    if not IsValid(wep) or not IsValid(ply) then return end
    if ply:IsSpec() then return end

    if wep:GetClass() == "weapon_inf_scanner" then
        return ply:IsSniffler()
    end
end

----------------
-- ROLE STATE --
----------------

local function HasSniffler()
    for _, v in PlayerIterator() do
        if v:IsSniffler() then
            return true
        end
    end
    return false
end

local function SetDefaultScanState(ply, oldRole, newRole)
    ply:SetNWInt("TTTSnifflerScanStage", SNIFFLER_UNSCANNED)
end

AddHook("TTTPrepareRound", "Sniffler_TTTPrepareRound", function()
    for _, v in PlayerIterator() do
        v:SetNWInt("TTTSnifflerScanStage", SNIFFLER_UNSCANNED)
        v:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_IDLE)
        v:SetNWString("TTTSnifflerScannerTarget", "")
        v:SetNWString("TTTSnifflerScannerMessage", "")
        v:SetNWFloat("TTTSnifflerScannerStartTime", -1)
        v:SetNWFloat("TTTSnifflerScannerTargetLostTime", -1)
        v:SetNWFloat("TTTSnifflerScannerCooldown", -1)
    end
end)

AddHook("TTTBeginRound", "Sniffler_TTTBeginRound", function()
    if not HasSniffler() then return end

    for _, v in PlayerIterator() do
        SetDefaultScanState(v)
    end
end)

-------------
-- SCANNER --
-------------

local function IsTargetingPlayer(ply)
    if not IsValid(ply) then return false end

    local tr = ply:GetEyeTrace(MASK_SHOT)
    local ent = tr.Entity

    return (IsPlayer(ent) and ent:IsActive()) and ent or false
end

local function TargetLost(ply)
    if not IsValid(ply) then return end

    ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_LOST)
    ply:SetNWString("TTTSnifflerScannerTarget", "")
    ply:SetNWString("TTTSnifflerScannerMessage", "TARGET LOST")
    ply:SetNWFloat("TTTSnifflerScannerStartTime", -1)
    ply:SetNWFloat("TTTSnifflerScannerCooldown", CurTime())
end

local function Announce(ply, message)
    if not IsValid(ply) then return end

    ply:QueueMessage(MSG_PRINTCENTER, message)
end

local function InRange(ply, target)
    if not IsValid(ply) or not IsValid(target) then return false end

    if not ply:IsLineOfSightClear(target) then return false end

    local plyPos = ply:GetPos()
    local targetPos = target:GetPos()
    local scanner_distance = sniffler_scanner_distance:GetInt()
    local scannerDistanceSqr = scanner_distance * scanner_distance
    if plyPos:DistToSqr(targetPos) > scannerDistanceSqr then return false end

    return ply:IsOnScreen(target, 0.35)
end

local function ScanAllowed(ply, target)
    if not IsValid(ply) or not IsValid(target) then return false end
    if not IsPlayer(target) then return false end
    if not target:IsActive() then return false end
    if not InRange(ply, target) then return false end

    return true
end

local function GetTargetScanTime(target)
    local scanner_time = sniffler_scanner_time:GetInt()
    if not target or not IsPlayer(target) then
        return scanner_time
    end

    return scanner_time
end

local function Scan(ply, target)
    if not IsValid(ply) or not IsValid(target) then return end

    if target:IsActive() then
        local stage = target:GetNWInt("TTTSnifflerScanStage", SNIFFLER_UNSCANNED)
        if CurTime() - ply:GetNWFloat("TTTSnifflerScannerStartTime", -1) >= GetTargetScanTime(target) then
            stage = stage + 1
            if stage == SNIFFLER_SCANNED_INV_TOTAL then
                local targetInvTotal = 0
                for _, wep in ipairs(target:GetWeapons()) do
                    targetInvTotal = targetInvTotal + 1
                end

                local targetInvTotalString = targetInvTotal == 1 and " weapon" or " weapons"

                local message = target:Nick() .. " has " .. targetInvTotal .. targetInvTotalString .. " in their inventory"

                Announce(ply, message)

                ply:SetNWFloat("TTTSnifflerScannerStartTime", CurTime())
            elseif stage == SNIFFLER_SCANNED_SHOP_ITEMS then
                local targetShopTotal = 0
                for _, wep in ipairs(target:GetWeapons()) do
                    if wep.CanBuy and #wep.CanBuy > 0 then
                        targetShopTotal = targetShopTotal + 1
                    end
                end

                local targetShopTotalString = targetShopTotal == 1 and " buyable weapon" or " buyable weapons"

                local message = target:Nick() .. " has " .. targetShopTotal .. targetShopTotalString .. " in their inventory"

                Announce(ply, message)

                ply:SetNWFloat("TTTSnifflerScannerStartTime", CurTime())
            elseif stage == SNIFFLER_SCANNED_ROLE_ITEMS then
                local targetHasRoleWeapon = false
                for _, wep in ipairs(target:GetWeapons()) do
                    if wep.Category and wep.Category == WEAPON_CATEGORY_ROLE then
                        targetHasRoleWeapon = true
                        continue
                    end
                end

                local message = targetHasRoleWeapon and target:Nick() .. " has a role weapon" or target:Nick() .. " does not have a role weapon"

                Announce(ply, message)

                local rescanTime = GetConVar("ttt_sniffler_rescan_time"):GetInt()
                ply:SetNWFloat("TTTSnifflerRescanTime_" .. target:SteamID64(), CurTime() + rescanTime)

                ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_IDLE)
                ply:SetNWString("TTTSnifflerScannerTarget", "")
                ply:SetNWString("TTTSnifflerScannerMessage", "")
                ply:SetNWFloat("TTTSnifflerScannerStartTime", -1)
            end
            target:SetNWInt("TTTSnifflerScanStage", stage)
            hook.Call("TTTSnifflerScanStageChanged", nil, ply, target, stage)
        end
    else
        TargetLost(ply)
    end
end

local function Sniffler_TTTPlayerAliveThink(ply)
    if not IsValid(ply) or ply:IsSpec() or GetRoundState() ~= ROUND_ACTIVE then return end

    if ply:IsSniffler() and not ply:IsRoleAbilityDisabled() then
        local state = ply:GetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_IDLE)
        if state == SNIFFLER_SCANNER_IDLE then
            local target = IsTargetingPlayer(ply)
            if target and (not sniffler_requires_scanner:GetBool() or (ply.GetActiveWeapon and IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() == "weapon_inf_scanner")) then
                local stage = target:GetNWInt("TTTSnifflerScanStage", SNIFFLER_UNSCANNED)
                local rescanTime = ply:GetNWFloat("TTTSnifflerRescanTime_" .. target:SteamID64(), 0)

                -- If target's cooldown is finished, reset their state
                if stage == SNIFFLER_SCANNED_ROLE_ITEMS and CurTime() >= rescanTime then
                    stage = SNIFFLER_UNSCANNED
                    target:SetNWInt("TTTSnifflerScanStage", stage)
                end

                if stage < SNIFFLER_SCANNED_ROLE_ITEMS and ScanAllowed(ply, target) then
                    ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_LOCKED)
                    ply:SetNWString("TTTSnifflerScannerTarget", target:SteamID64())
                    ply:SetNWString("TTTSnifflerScannerMessage", "SNIFFLING " .. utf8.upper(target:Nick()))
                    ply:SetNWFloat("TTTSnifflerScannerStartTime", CurTime())
                elseif stage == SNIFFLER_SCANNED_ROLE_ITEMS and ScanAllowed(ply, target) and CurTime() < rescanTime then
                    -- Target is scanned but on cooldown
                    ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_WAITING)
                    ply:SetNWString("TTTSnifflerScannerTarget", target:SteamID64())
                end
            end
        elseif state == SNIFFLER_SCANNER_LOCKED then
            local target = player.GetBySteamID64(ply:GetNWString("TTTSnifflerScannerTarget", ""))
            if target:IsActive() then
                if not InRange(ply, target) then
                    ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_SEARCHING)
                    ply:SetNWString("TTTSnifflerScannerMessage", "SNIFFING " .. utf8.upper(target:Nick()) .. " (LOSING TARGET)")
                    ply:SetNWFloat("TTTSnifflerScannerTargetLostTime", CurTime())
                end
                Scan(ply, target)
            else
                TargetLost(ply)
            end
        elseif state == SNIFFLER_SCANNER_SEARCHING then
            local target = player.GetBySteamID64(ply:GetNWString("TTTSnifflerScannerTarget", ""))
            if target:IsActive() then
                if (CurTime() - ply:GetNWInt("TTTSnifflerScannerTargetLostTime", -1)) >= sniffler_scanner_float_time:GetInt() then
                    TargetLost(ply)
                else
                    if InRange(ply, target) then
                        ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_LOCKED)
                        ply:SetNWString("TTTSnifflerScannerMessage", "SNIFFING " .. utf8.upper(target:Nick()))
                        ply:SetNWFloat("TTTSnifflerScannerTargetLostTime", -1)
                    end
                    Scan(ply, target)
                end
            else
                TargetLost(ply)
            end
        elseif state == SNIFFLER_SCANNER_LOST then
            if (CurTime() - ply:GetNWFloat("TTTSnifflerScannerCooldown", -1)) >= sniffler_scanner_cooldown:GetInt() then
                ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_IDLE)
                ply:SetNWString("TTTSnifflerScannerMessage", "")
                ply:SetNWFloat("TTTSnifflerScannerCooldown", -1)
            end
        elseif state == SNIFFLER_SCANNER_WAITING then
            local target = IsTargetingPlayer(ply)
            local storedTarget = player.GetBySteamID64(ply:GetNWString("TTTSnifflerScannerTarget", ""))

            -- Sniffler still looking at target
            if target and target == storedTarget and ScanAllowed(ply, target) then
                local rescanTime = ply:GetNWFloat("TTTSnifflerRescanTime_" .. target:SteamID64(), 0)
                if CurTime() >= rescanTime then
                    -- When cooldown is finished, start rescanning
                    target:SetNWInt("TTTSnifflerScanStage", SNIFFLER_UNSCANNED)
                    ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_LOCKED)
                    ply:SetNWString("TTTSnifflerScannerMessage", "SNIFFING " .. utf8.upper(target:Nick()))
                    ply:SetNWFloat("TTTSnifflerScannerStartTime", CurTime())
                end
            else
                ply:SetNWInt("TTTSnifflerScannerState", SNIFFLER_SCANNER_IDLE)
                ply:SetNWString("TTTSnifflerScannerTarget", "")
            end
        end
    end
end

----------------
-- HITMARKERS --
----------------

local function Sniffler_TTTDrawHitMarker(victim, dmginfo)
    local att = dmginfo:GetAttacker()
    if not IsPlayer(att) or not IsPlayer(victim) then return end

    if victim:GetNWInt("TTTSnifflerScanStage", SNIFFLER_UNSCANNED) ~= SNIFFLER_SCANNED_SHOP_ITEMS then return end

    if not att:IsSniffler() and not (sniffler_share_scans:GetBool() and att:IsTraitorTeam()) then return end

    if victim:IsJester() or victim:IsSwapper() or victim:IsGuesser() or (victim:IsBeggar() and GetConVar("ttt_beggar_respawn_change_role"):GetBool()) then
        return true, false, false, true
    end
end

------------------
-- REGISTRATION --
------------------

ROLE_REGISTERED_HOOKS[ROLE_SNIFFLER] = {
    ["PlayerCanPickupWeapon"] = Sniffler_Weapons_PlayerCanPickupWeapon,
    ["TTTDrawHitMarker"] = Sniffler_TTTDrawHitMarker,
    ["TTTPlayerAliveThink"] = Sniffler_TTTPlayerAliveThink
}