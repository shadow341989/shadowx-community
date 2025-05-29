#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = 
{
    name = "L4D2 End Vote",
    author = "shadowx",
    description = "Creates a vote to end the game when score difference is 2000+",
    version = "1.0",
    url = "https://github.com/shadow341989/shadowx-community"
};

ConVar g_cvScoreDifference;
bool g_bVoteInProgress;
int g_iVoteYesCount;

public void OnPluginStart()
{
    g_cvScoreDifference = CreateConVar("sm_endvote_score_diff", "2000", "Minimum score difference to trigger end vote", FCVAR_NONE, true, 0.0);
    
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    
    // Admin commands
    RegAdminCmd("sm_endvote", Cmd_EndVote, ADMFLAG_VOTE, "Force an end vote (Admin only)");
    RegAdminCmd("sm_endgame", Cmd_EndGame, ADMFLAG_ROOT, "Immediately end the game and kick all players (Admin only)");
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    int scoreA = GetTeamScore(2);
    int scoreB = GetTeamScore(3);
    int diff = scoreA > scoreB ? scoreA - scoreB : scoreB - scoreA;

    if (diff >= g_cvScoreDifference.IntValue)
    {
        CreateTimer(5.0, Timer_StartVote, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    
    return Plugin_Continue;
}

public Action Timer_StartVote(Handle timer)
{
    if (g_bVoteInProgress)
        return Plugin_Stop;
        
    StartVote();
    return Plugin_Stop;
}

void StartVote()
{
    g_bVoteInProgress = true;
    g_iVoteYesCount = 0;
    
    Menu menu = new Menu(VoteMenuHandler, MenuAction_VoteStart | MenuAction_VoteCancel | MenuAction_VoteEnd | MenuAction_End | MenuAction_Select);
    menu.SetTitle("The score is 2000+ difference!\nDo you want to end the game?");
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(60);
}

public int VoteMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_End:
        {
            g_bVoteInProgress = false;
            delete menu;
        }
        case MenuAction_VoteStart:
        {
            g_iVoteYesCount = 0;
        }
        case MenuAction_VoteCancel:
        {
            if (param1 == VoteCancel_NoVotes)
            {
                PrintToChatAll("Vote cancelled: No votes were received.");
            }
        }
        case MenuAction_VoteEnd:
        {
            if (param1 == 0) // 'Yes' won
            {
                if (g_iVoteYesCount >= 5)
                {
                    PrintToChatAll("Vote passed! Ending game...");
                    CreateTimer(3.0, Timer_KickAllPlayers, false, TIMER_FLAG_NO_MAPCHANGE);
                }
                else
                {
                    PrintToChatAll("Vote passed but not enough yes votes (needed 5+).");
                }
            }
            else // 'No' won
            {
                PrintToChatAll("Vote failed. Continuing game.");
            }
        }
        case MenuAction_Select:
        {
            if (param2 == 0) // 'Yes' was selected
            {
                g_iVoteYesCount++;
            }
        }
    }
    
    return 0; // Added return value to fix the warning
}

public Action Cmd_EndVote(int client, int args)
{
    if (!client)
    {
        ReplyToCommand(client, "This command can only be used in-game.");
        return Plugin_Handled;
    }

    if (g_bVoteInProgress)
    {
        ReplyToCommand(client, "A vote is already in progress.");
        return Plugin_Handled;
    }
    
    StartVote();
    return Plugin_Handled;
}

public Action Cmd_EndGame(int client, int args)
{
    if (!client)
    {
        ReplyToCommand(client, "This command can only be used in-game.");
        return Plugin_Handled;
    }

    PrintToChatAll("[SM] Admin has forced the game to end!");
    CreateTimer(3.0, Timer_KickAllPlayers, true, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Timer_KickAllPlayers(Handle timer, bool adminForced)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            KickClient(i, adminForced ? "Game ended by admin" : "Game ended by vote");
        }
    }
    return Plugin_Stop;
}