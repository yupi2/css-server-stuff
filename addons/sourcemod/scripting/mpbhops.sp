/*========================================
** Multiplayer Bunnyhops: Source by DaFox & petsku
** Compatible with: Counter-Strike Source
** Thanks to Ian (Juan) Cammarata & #sourcemod
**======================================*/

#define VERSION "1.0.0.5"

//max. number of door/button based bhop blocks handled in a map
#define MAX_BHOPBLOCKS 1024
//how long can players stand on the block before getting teleported
#define BLOCK_TELEPORT 0.15
//when can they touch the same block again without getting teleported
#define BLOCK_COOLDOWN 1.0

//rgba value to color door blocks if cvar is enabled
#define COLOR_DOOR   {0, 200, 0, 255}
//rgba value to color button blocks if cvar is enabled
#define COLOR_BUTTON {200, 0, 200, 255}


#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

public Plugin:myinfo =
{
	name = "Multiplayer Bunnyhops: Source",
	author = "DaFox & petsku & unbiased george",
	description = "Allows players to jump on bhop maps, without the blocks being triggered but push the player off if they fail to bhop",
	version = VERSION,
	url = "http://www.google.com/"
}

//=============================================================================
//=============================================================================

//dont move when fired
#define SF_BUTTON_DONTMOVE        (1 << 0)
//button fires when touched
#define SF_BUTTON_TOUCH_ACTIVATES (1 << 8)
//player touch opens
#define SF_DOOR_PTOUCH            (1 << 10)

bool g_bLateLoaded = false
bool g_bMapEnding = false

int g_iBhopDoorList[MAX_BHOPBLOCKS]
int g_iBhopDoorTeleList[MAX_BHOPBLOCKS]
int g_iBhopDoorCount

float g_iBhopDoorSp[300]

int g_iBhopButtonList[MAX_BHOPBLOCKS]
int g_iBhopButtonTeleList[MAX_BHOPBLOCKS]
int g_iBhopButtonCount

int g_iOffs_clrRender = -1
int g_iOffs_vecOrigin = -1
int g_iOffs_vecMins = -1
int g_iOffs_vecMaxs = -1

int g_iDoorOffs_vecPosition1 = -1
int g_iDoorOffs_vecPosition2 = -1
int g_iDoorOffs_flSpeed = -1
int g_iDoorOffs_spawnflags = -1
int g_iDoorOffs_NoiseMoving = -1
int g_iDoorOffs_sLockedSound = -1
int g_iDoorOffs_bLocked = -1

int g_iButtonOffs_vecPosition1 = -1
int g_iButtonOffs_vecPosition2 = -1
int g_iButtonOffs_flSpeed = -1
int g_iButtonOffs_spawnflags = -1

Handle g_hCvar_Enable = INVALID_HANDLE
Handle g_hCvar_Color = INVALID_HANDLE
Handle g_hSDK_Touch = INVALID_HANDLE

char gS_CurrentMap[32];

//=============================================================================================
//=============================================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoaded = late
	return APLRes_Success
}

public OnPluginStart()
{
	Handle hGameConf = LoadGameConfigFile("sdkhooks.games")

	if (hGameConf == INVALID_HANDLE)
	{
		SetFailState("GameConfigFile sdkhooks.games was not found")
		return
	}

	StartPrepSDKCall(SDKCall_Entity)
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Touch")
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer)
	g_hSDK_Touch = EndPrepSDKCall()
	CloseHandle(hGameConf)

	if (g_hSDK_Touch == INVALID_HANDLE)
	{
		SetFailState("Unable to prepare virtual function CBaseEntity::Touch")
		return
	}

	CreateConVar("mpbhops_version", VERSION, "Multiplayer Bunnyhops: Source", FCVAR_NOTIFY)
	g_hCvar_Enable = CreateConVar("mpbhops_enable", "1", "Enable/disable Multiplayer Bunnyhops: Source", FCVAR_NOTIFY)
	g_hCvar_Color = CreateConVar("mpbhops_color", "0", "If enabled, marks hooked bhop blocks with colors", FCVAR_NOTIFY)

	HookConVarChange(g_hCvar_Enable, ConVarChanged_Enable)
	HookConVarChange(g_hCvar_Color, ConVarChanged_Color)

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy)

	g_iOffs_clrRender = FindSendPropInfo("CBaseEntity", "m_clrRender")
	g_iOffs_vecOrigin = FindSendPropInfo("CBaseEntity", "m_vecOrigin")
	g_iOffs_vecMins = FindSendPropInfo("CBaseEntity", "m_vecMins")
	g_iOffs_vecMaxs = FindSendPropInfo("CBaseEntity", "m_vecMaxs")

	if (g_bLateLoaded)
		OnPluginPauseChange(false)
}

public OnMapStart()
{
	GetCurrentMap(gS_CurrentMap, 32);
}

public OnMapEnd()
{
	//DF 2012 Jan 20 - I don't know what the fuck is going on here, but I'm too afraid to touch it. It's likely just cruft that should be removed.
	g_bMapEnding = true
	SetConVarBool(g_hCvar_Enable, GetConVarBool(g_hCvar_Enable)) //DF 2012 Jan 20 - This used to always set it to true, Causing the plugin to turn on
	g_bMapEnding = false										// automatically at map change, even if it was disabled.
}

public OnPluginPauseChange(bool pause)
{
	if (pause)
	{
		OnPluginEnd()
	}
	else if (GetConVarBool(g_hCvar_Enable))
	{
		g_iBhopDoorCount = 0
		g_iBhopButtonCount = 0

		FindBhopBlocks()

		if (!g_iBhopDoorCount && !g_iBhopButtonCount)
			SetConVarBool(g_hCvar_Enable, false)
	}
}

public OnPluginEnd()
{
	AlterBhopBlocks(true)

	g_iBhopDoorCount = 0
	g_iBhopButtonCount = 0
}

//=============================================================================================
//=============================================================================================

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	OnPluginPauseChange(false)
}

public Entity_BoostTouch(int bhop, int client)
{
	if (0 < client <= MaxClients)
	{
		float speed = -1.0;

		for (int i = 0; i < g_iBhopDoorCount; ++i)
		{
			if (bhop == g_iBhopDoorList[i])
			{
				speed = g_iBhopDoorSp[i]
				break
			}
		}

		if (speed != -1 && speed)
		{
			float ovel[3]
			Entity_GetBaseVelocity(client, ovel)
			float evel[3]
			Entity_GetLocalVelocity(client, evel)

			if (ovel[2] < speed && evel[2] < speed)
			{
				float vel[3]
				vel[0] = Float:0
				vel[1] = Float:0
				vel[2] = speed * 1.8
				Entity_SetBaseVelocity(client, vel)
			}
		}
	}
}

public Entity_Touch(int bhop, int client)
{
	if (0 < client && client <= MaxClients)
	{
		static float flPunishTime[MAXPLAYERS + 1]
		static int iLastBlock[MAXPLAYERS + 1] = { -1,... }
		float time = GetEngineTime()
		float diff = time - flPunishTime[client]

		if (iLastBlock[client] != bhop || diff > BLOCK_COOLDOWN)
		{
			iLastBlock[client] = bhop
			flPunishTime[client] = time + BLOCK_TELEPORT
		}
		else if (diff > BLOCK_TELEPORT)
		{
			decl i
			new tele = -1, ent = iLastBlock[client]

			iLastBlock[client] = -1

			for (i = 0; i < g_iBhopDoorCount; ++i)
			{
				if (ent == g_iBhopDoorList[i])
				{
					tele = g_iBhopDoorTeleList[i]
					break
				}
			}

			if (tele == -1)
			{
				for (i = 0; i < g_iBhopButtonCount; ++i)
				{
					if (ent == g_iBhopButtonList[i])
					{
						tele = g_iBhopButtonTeleList[i]
						break
					}
				}
			}

			if (tele != -1 && IsValidEntity(tele))
				SDKCall(g_hSDK_Touch, tele, client)
		}
	}
}

public ConVarChanged_Enable(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (g_bMapEnding)
		return

	bool bEnabled = StringToInt(newValue) ? true : false

	if (bEnabled != (StringToInt(oldValue) ? true : false))
		OnPluginPauseChange(!bEnabled)
}

public ConVarChanged_Color(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (!GetConVarBool(g_hCvar_Enable))
		return

	bool bEnabled = StringToInt(newValue) ? true : false

	if (bEnabled != (StringToInt(oldValue) ? true : false))
		ColorBlocks(!bEnabled)
}

//=============================================================================================
//=============================================================================================

FindBhopBlocks()
{
	//decl
	float startpos[3]
	float endpos[3]
	float mins[3]
	float maxs[3]
	int tele
	int ent = -1

	while ((ent = FindEntityByClassname(ent,"func_door")) != -1)
	{
		if (g_iDoorOffs_vecPosition1 == -1)
		{
			g_iDoorOffs_vecPosition1 = FindDataMapInfo(ent, "m_vecPosition1")
			g_iDoorOffs_vecPosition2 = FindDataMapInfo(ent, "m_vecPosition2")
			g_iDoorOffs_flSpeed = FindDataMapInfo(ent, "m_flSpeed")
			g_iDoorOffs_spawnflags = FindDataMapInfo(ent, "m_spawnflags")
			g_iDoorOffs_NoiseMoving = FindDataMapInfo(ent, "m_NoiseMoving")
			g_iDoorOffs_sLockedSound = FindDataMapInfo(ent, "m_ls.sLockedSound")
			g_iDoorOffs_bLocked = FindDataMapInfo(ent, "m_bLocked")
		}

		GetEntDataVector(ent, g_iDoorOffs_vecPosition1, startpos)
		GetEntDataVector(ent, g_iDoorOffs_vecPosition2, endpos)

		GetEntDataVector(ent, g_iOffs_vecMins, mins)
		GetEntDataVector(ent, g_iOffs_vecMaxs, maxs)
		float speed = GetEntDataFloat(ent, g_iDoorOffs_flSpeed)

		if (!StrEqual(gS_CurrentMap, "bhop_monster_jam", false) &&
			(maxs[2] - mins[2]) < 80 && (startpos[2] > endpos[2] || speed > 100))
		{
			startpos[0] += (mins[0] + maxs[0]) * 0.5
			startpos[1] += (mins[1] + maxs[1]) * 0.5
			startpos[2] += maxs[2]

			if ((tele = CustomTraceForTeleports(startpos, endpos[2] + maxs[2])) != -1 ||
				(speed > 100 && startpos[2] < endpos[2]))
			{
				g_iBhopDoorList[g_iBhopDoorCount] = ent
				g_iBhopDoorTeleList[g_iBhopDoorCount] = tele

				if (++g_iBhopDoorCount == sizeof(g_iBhopDoorList))
					break
			}
		}
	}

	ent = -1

	while ((ent = FindEntityByClassname(ent, "func_button")) != -1)
	{
		if (g_iButtonOffs_vecPosition1 == -1)
		{
			g_iButtonOffs_vecPosition1 = FindDataMapInfo(ent, "m_vecPosition1")
			g_iButtonOffs_vecPosition2 = FindDataMapInfo(ent, "m_vecPosition2")
			g_iButtonOffs_flSpeed = FindDataMapInfo(ent, "m_flSpeed")
			g_iButtonOffs_spawnflags = FindDataMapInfo(ent, "m_spawnflags")
		}

		GetEntDataVector(ent, g_iButtonOffs_vecPosition1, startpos)
		GetEntDataVector(ent, g_iButtonOffs_vecPosition2, endpos)

		if (startpos[2] > endpos[2] &&
			(GetEntData(ent, g_iButtonOffs_spawnflags, 4) & SF_BUTTON_TOUCH_ACTIVATES))
		{
			GetEntDataVector(ent,g_iOffs_vecMins,mins)
			GetEntDataVector(ent,g_iOffs_vecMaxs,maxs)

			startpos[0] += (mins[0] + maxs[0]) * 0.5
			startpos[1] += (mins[1] + maxs[1]) * 0.5
			startpos[2] += maxs[2]

			if ((tele = CustomTraceForTeleports(startpos, endpos[2] + maxs[2])) != -1)
			{
				g_iBhopButtonList[g_iBhopButtonCount] = ent
				g_iBhopButtonTeleList[g_iBhopButtonCount] = tele

				if (++g_iBhopButtonCount == sizeof(g_iBhopButtonList))
					break
			}
		}
	}

	AlterBhopBlocks(false)
}

AlterBhopBlocks(bool bRevertChanges)
{
	static float vecDoorPosition2[sizeof(g_iBhopDoorList)][3]
	static float flDoorSpeed[sizeof(g_iBhopDoorList)]
	static iDoorSpawnflags[sizeof(g_iBhopDoorList)]
	static bool bDoorLocked[sizeof(g_iBhopDoorList)]

	static float vecButtonPosition2[sizeof(g_iBhopButtonList)][3]
	static float flButtonSpeed[sizeof(g_iBhopButtonList)]
	static iButtonSpawnflags[sizeof(g_iBhopButtonList)]

	int ent
	int i

	if (bRevertChanges)
	{
		for (i = 0; i < g_iBhopDoorCount; ++i)
		{
			ent = g_iBhopDoorList[i]

			if (IsValidEntity(ent))
			{
				SetEntDataVector(ent, g_iDoorOffs_vecPosition2, vecDoorPosition2[i])
				SetEntDataFloat(ent, g_iDoorOffs_flSpeed, flDoorSpeed[i])
				SetEntData(ent, g_iDoorOffs_spawnflags, iDoorSpawnflags[i],4)

				if (!bDoorLocked[i])
					AcceptEntityInput(ent, "Unlock")

				if (flDoorSpeed[i] <= 100)
					SDKUnhook(ent, SDKHook_Touch, Entity_Touch)
				else
					SDKUnhook(ent, SDKHook_Touch, Entity_BoostTouch)
			}
		}

		for (i = 0; i < g_iBhopButtonCount; ++i)
		{
			ent = g_iBhopButtonList[i]

			if (IsValidEntity(ent))
			{
				SetEntDataVector(ent, g_iButtonOffs_vecPosition2, vecButtonPosition2[i])
				SetEntDataFloat(ent, g_iButtonOffs_flSpeed, flButtonSpeed[i])
				SetEntData(ent, g_iButtonOffs_spawnflags, iButtonSpawnflags[i],4)

				SDKUnhook(ent, SDKHook_Touch, Entity_Touch)
			}
		}
	}
	else
	{
		//note: This only gets called directly after finding the blocks, so the entities are valid.

		float startpos[3]

		for (i = 0; i < g_iBhopDoorCount; ++i)
		{
			ent = g_iBhopDoorList[i]

			GetEntDataVector(ent, g_iDoorOffs_vecPosition2, vecDoorPosition2[i])
			flDoorSpeed[i] = GetEntDataFloat(ent, g_iDoorOffs_flSpeed)
			iDoorSpawnflags[i] = GetEntData(ent, g_iDoorOffs_spawnflags, 4)
			bDoorLocked[i] = GetEntData(ent, g_iDoorOffs_bLocked, 1) ? true : false

			GetEntDataVector(ent, g_iDoorOffs_vecPosition1, startpos)
			SetEntDataVector(ent, g_iDoorOffs_vecPosition2, startpos)

			SetEntDataFloat(ent, g_iDoorOffs_flSpeed, 0.0)
			SetEntData(ent, g_iDoorOffs_spawnflags, SF_DOOR_PTOUCH, 4)
			AcceptEntityInput(ent, "Lock")

			SetEntData(ent, g_iDoorOffs_sLockedSound, GetEntData(ent, g_iDoorOffs_NoiseMoving, 4), 4)

			if (flDoorSpeed[i] <= 100)
			{
				SDKHook(ent, SDKHook_Touch, Entity_Touch)
			}
			else
			{
				g_iBhopDoorSp[i] = flDoorSpeed[i]
				SDKHook(ent, SDKHook_Touch, Entity_BoostTouch)
			}
		}

		for (i = 0; i < g_iBhopButtonCount; ++i)
		{
			ent = g_iBhopButtonList[i]

			GetEntDataVector(ent, g_iButtonOffs_vecPosition2, vecButtonPosition2[i])
			flButtonSpeed[i] = GetEntDataFloat(ent, g_iButtonOffs_flSpeed)
			iButtonSpawnflags[i] = GetEntData(ent, g_iButtonOffs_spawnflags, 4)

			GetEntDataVector(ent, g_iButtonOffs_vecPosition1, startpos)
			SetEntDataVector(ent, g_iButtonOffs_vecPosition2, startpos)


			SetEntDataFloat(ent, g_iButtonOffs_flSpeed, 0.0)
			SetEntData(ent, g_iButtonOffs_spawnflags, SF_BUTTON_DONTMOVE|SF_BUTTON_TOUCH_ACTIVATES, 4)

			SDKHook(ent, SDKHook_Touch, Entity_Touch)
		}
	}

	if (GetConVarBool(g_hCvar_Color))
		ColorBlocks(bRevertChanges)
}

ColorBlocks(bool:bRevertChanges)
{
	static iDoorClrRender[sizeof(g_iBhopDoorList)][4]
	static iButtonClrRender[sizeof(g_iBhopButtonList)][4]

	int ent
	int i

	if (bRevertChanges)
	{
		for (i = 0; i < g_iBhopDoorCount; ++i)
		{
			ent = g_iBhopDoorList[i]

			if (IsValidEntity(ent))
				SetEntDataArray(ent, g_iOffs_clrRender, iDoorClrRender[i], sizeof iDoorClrRender[], 1, true)
		}

		for (i = 0; i < g_iBhopButtonCount; ++i)
		{
			ent = g_iBhopButtonList[i]

			if (IsValidEntity(ent))
				SetEntDataArray(ent, g_iOffs_clrRender, iButtonClrRender[i], sizeof iButtonClrRender[], 1, true)
		}
	}
	else
	{
		for (i = 0; i < g_iBhopDoorCount; ++i)
		{
			ent = g_iBhopDoorList[i]

			if (IsValidEntity(ent))
			{
				GetEntDataArray(ent, g_iOffs_clrRender, iDoorClrRender[i], sizeof iDoorClrRender[], 1)
				SetEntDataArray(ent, g_iOffs_clrRender, COLOR_DOOR, 4, 1, true)
			}
		}

		for (i = 0; i < g_iBhopButtonCount; ++i)
		{
			ent = g_iBhopButtonList[i]

			if (IsValidEntity(ent))
			{
				GetEntDataArray(ent, g_iOffs_clrRender, iButtonClrRender[i], sizeof iButtonClrRender[], 1)
				SetEntDataArray(ent, g_iOffs_clrRender, COLOR_BUTTON, 4, 1, true)
			}
		}
	}
}

CustomTraceForTeleports(const float startpos[3], float endheight, float step=1.0)
{
	int teleports[512]
	int tpcount
	int ent = -1

	while ((ent = FindEntityByClassname(ent, "trigger_teleport")) != -1 &&
		tpcount != sizeof(teleports))
	{
		teleports[tpcount++] = ent
	}

	//decl
	float mins[3]
	float maxs[3]
	float origin[3]
	int i

	origin[0] = startpos[0]
	origin[1] = startpos[1]
	origin[2] = startpos[2]

	do
	{
		for (i = 0; i < tpcount; i++)
		{
			ent = teleports[i]
			GetAbsBoundingBox(ent, mins, maxs)

			if (mins[0] <= origin[0] <= maxs[0] && mins[1] <= origin[1] <= maxs[1] && mins[2] <= origin[2] <= maxs[2])
				return ent
		}

		origin[2] -= step
	} while (origin[2] >= endheight)

	return -1
}

GetAbsBoundingBox(ent, float mins[3], float maxs[3])
{
	float origin[3]

	GetEntDataVector(ent, g_iOffs_vecOrigin, origin)
	GetEntDataVector(ent, g_iOffs_vecMins, mins)
	GetEntDataVector(ent, g_iOffs_vecMaxs, maxs)

	mins[0] += origin[0]
	mins[1] += origin[1]
	mins[2] += origin[2]

	maxs[0] += origin[0]
	maxs[1] += origin[1]
	maxs[2] += origin[2]
}
