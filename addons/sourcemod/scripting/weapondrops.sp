#pragma semicolon 1

#include <sourcemod>
#include <cstrike>

public Plugin myinfo =
{
	name = "Drop all & remove drops",
	author = "Me",
	description = "Enable dropping of knives & all drops are removed.",
	version = "1.0",
	url = "https://www.google.com/"
}

public void OnPluginStart()
{
	AddCommandListener(Command_drop, "drop");
}

public Action Command_drop(int client, const char[] command, int argc)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (!IsValidEdict(weapon))
		return Plugin_Stop;

	CS_DropWeapon(client, weapon, true, true);
	RemoveEdict(weapon);

	return Plugin_Handled;
}
