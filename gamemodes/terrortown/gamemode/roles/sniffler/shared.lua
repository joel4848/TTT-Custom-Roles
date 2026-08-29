AddCSLuaFile()

local hook = hook
local table = table

local AddHook = hook.Add

-- Initialize role features
SNIFFLER_UNSCANNED          = 0
SNIFFLER_SCANNED_INV_TOTAL  = 1
SNIFFLER_SCANNED_SHOP_ITEMS = 2
SNIFFLER_SCANNED_ROLE_ITEMS = 3

SNIFFLER_SCANNER_IDLE      = 0
SNIFFLER_SCANNER_LOCKED    = 1
SNIFFLER_SCANNER_SEARCHING = 2
SNIFFLER_SCANNER_LOST      = 3
SNIFFLER_SCANNER_WAITING   = 4

------------------
-- ROLE CONVARS --
------------------

CreateConVar("ttt_sniffler_scanner_time", "15", FCVAR_REPLICATED, "The amount of time (in seconds) the sniffler's scanner takes to use", 0, 60)
CreateConVar("ttt_sniffler_rescan_time", "30", FCVAR_REPLICATED, "The amount of time (in seconds) before the sniffler can scan a player again", 0, 60)
local sniffler_requires_scanner = CreateConVar("ttt_sniffler_requires_scanner", "0", FCVAR_REPLICATED)
local sniffler_is_innocent = CreateConVar("ttt_sniffler_is_innocent", "0", FCVAR_REPLICATED, "Whether the sniffler should be treated as a special innocent", 0, 1)

ROLE_CONVARS[ROLE_SNIFFLER] = {
    {
        cvar = "ttt_sniffler_requires_scanner",
        type = ROLE_CONVAR_TYPE_BOOL
    },
    {
        cvar = "ttt_sniffler_scanner_time",
        type = ROLE_CONVAR_TYPE_NUM,
        decimal = 0
    },
    {
        cvar = "ttt_sniffler_rescan_time",
        type = ROLE_CONVAR_TYPE_NUM,
        decimal = 0
    },
    {
        cvar = "ttt_sniffler_scanner_float_time",
        type = ROLE_CONVAR_TYPE_NUM,
        decimal = 0
    },
    {
        cvar = "ttt_sniffler_scanner_cooldown",
        type = ROLE_CONVAR_TYPE_NUM,
        decimal = 0
    },
    {
        cvar = "ttt_sniffler_scanner_distance",
        type = ROLE_CONVAR_TYPE_NUM,
        decimal = 0
    }
}

-----------------
-- ROLE WEAPON --
-----------------

AddHook("TTTUpdateRoleState", "Sniffler_TTTUpdateRoleState", function()
    local sniffler_scanner = weapons.GetStored("weapon_inf_scanner")
    if sniffler_requires_scanner:GetBool() then
        sniffler_scanner.InLoadoutFor = table.Copy(sniffler_scanner.InLoadoutForDefault)
    else
        table.Empty(sniffler_scanner.InLoadoutFor)
    end
end)

-------------------
-- ROLE FEATURES --
-------------------

AddHook("TTTUpdateRoleState", "Sniffler_TTTUpdateRoleState", function()
    local is_innocent = sniffler_is_innocent:GetBool()
    DETECTIVE_ROLES[ROLE_SNIFFLER] = not is_innocent
end)