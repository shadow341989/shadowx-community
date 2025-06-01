#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>

#define PLUGIN_VERSION "1.0"
#define SM_REQUIRED_MAJOR 1
#define SM_REQUIRED_MINOR 12

public Plugin myinfo = 
{
    name = "Score Difference Display",
    author = "Your Name",
    description = "Displays score differences between teams after each round",
    version = PLUGIN_VERSION,
    url = "https://yourwebsite.com"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Check if we're running on L4D2
    EngineVersion game = GetEngineVersion();
    if (game != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "This plugin only runs on Left 4 Dead 2.");
        return APLRes_Failure;
    }
    
    return APLRes_Success;
}

public void OnPluginStart()
{
    // Check SourceMod version
    char sm_version[32];
    FindConVar("sourcemod_version").GetString(sm_version, sizeof(sm_version));
    
    // Parse version manually
    int maj, min;
    if (ParseVersionString(sm_version, maj, min) == false || maj < SM_REQUIRED_MAJOR || (maj == SM_REQUIRED_MAJOR && min < SM_REQUIRED_MINOR))
    {
        SetFailState("This plugin requires SourceMod %d.%d.0 or higher (detected %s).", SM_REQUIRED_MAJOR, SM_REQUIRED_MINOR, sm_version);
    }
    
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

bool ParseVersionString(const char[] version, int &major, int &minor)
{
    // Simple version parser that handles formats like:
    // "1.12.0" or "1.12" or "1.12.0.1234"
    char parts[3][12];
    if (ExplodeString(version, ".", parts, sizeof(parts), sizeof(parts[])) < 2)
    {
        return false;
    }
    
    major = StringToInt(parts[0]);
    minor = StringToInt(parts[1]);
    return true;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    // Get team scores
    int team2_score = GetTeamScore(2);
    int team3_score = GetTeamScore(3);
    int score_diff = team2_score - team3_score;
    
    // Get map name
    char map_name[128];
    GetCurrentMap(map_name, sizeof(map_name));
    
    // Get round information
    int round_number = GameRules_GetProp("m_nRoundNumber");
    int max_rounds = GameRules_GetProp("m_nMaxRounds");
    
    // Calculate absolute difference for comeback message
    int comeback_diff = score_diff;
    if (comeback_diff < 0)
    {
        comeback_diff = -comeback_diff;
    }
    
    // Display the message
    CPrintToChatAll("{blue}survivor score(team2) %d {red}infected score(team3) %d", team2_score, team3_score);
    CPrintToChatAll("{green}>score difference %d", score_diff);
    CPrintToChatAll("{lightgreen}>comeback score %d", comeback_diff);
    CPrintToChatAll("{red}>%s", map_name);
    CPrintToChatAll("{blue}>round %d of %d", round_number, max_rounds);
}