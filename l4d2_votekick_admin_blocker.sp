#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>

public Plugin myinfo = 
{
    name = "L4D2 Admin Vote Kick Blocker",
    author = "shadowx",
    description = "Blocks vote kicks against admins and notifies both parties",
    version = "1.0",
    url = "https://github.com/shadow341989/shadowx-community"
};

public void OnPluginStart()
{
    AddCommandListener(Command_CallVote, "callvote");
}

public Action Command_CallVote(int client, const char[] command, int argc)
{
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Continue;
    
    if (argc < 1)
        return Plugin_Continue;
    
    char sArg[32];
    GetCmdArg(1, sArg, sizeof(sArg));
    
    if (StrEqual(sArg, "kick", false))
    {
        if (argc < 2)
            return Plugin_Continue;
            
        char sTarget[32];
        GetCmdArg(2, sTarget, sizeof(sTarget));
        
        int target = FindTarget(client, sTarget, true, false);
        if (target == -1)
            return Plugin_Continue;
            
        if (CheckCommandAccess(target, "sm_kick", ADMFLAG_GENERIC))
        {
            CPrintToChat(client, "{blue}[!] Cannot call a votekick against the admin");
            CPrintToChat(target, "{blue}[!] %N has tried to call a vote kick against you!", client);
            return Plugin_Stop;
        }
    }
    
    return Plugin_Continue;
}