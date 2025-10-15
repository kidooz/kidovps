#include <open.mp>
#include <a_mysql>
#include <bcrypt>
#include <mdialog>
#include <Pawn.CMD>
#include <sscanf2>

/*
     ___      _
    / __| ___| |_ _  _ _ __
    \__ \/ -_)  _| || | '_ \
    |___/\___|\__|\_,_| .__/
                      |_|
*/

new MySQL:db;

// Defines
#define DIALOG_LOGIN 1
#define DIALOG_REGISTER 2
#define DIALOG_CHARACTER_SELECT 3
#define DIALOG_CHARACTER_CREATE 4
#define DIALOG_CHARACTER_BIRTHDATE 5
#define DIALOG_CHARACTER_ORIGIN 6

#define MAX_LOGIN_ATTEMPTS 3
#define LOGIN_TIMEOUT 30000 // 30 seconds

#define isnull(%1) ((!(%1[0])) || (((%1[0]) == '\1') && (!(%1[1]))))

new MySQLRaceCheck[MAX_PLAYERS];

// Define AdminDuty without database so everytime server restarts or admin relogs, they won't be in admin duty
new AdminDuty[MAX_PLAYERS];

// Enums
enum E_USER_DATA {
    uID,
    uUsername[24],
    uPassword[61], // bcrypt hash length
    uAdminLevel,
    uDateCreated[20],
    uLastLogin[20]
};

enum E_CHARACTER_DATA {
    cID,
    cUserID,
    cName[24],
    cMoney,
    cLevel,
    cSkinID,
    cOrigin[24],
    cBirthdate[11], // YYYY-MM-DD
    cCharacterStory[1],
    Float:cHealth,
    Float:cArmor,
    cWeapon1,
    cAmmo1,
    cWeapon2,
    cAmmo2,
    cVehicles[128], // JSON string
    cProperties[128], // JSON string
    Float:cPosX,
    Float:cPosY,
    Float:cPosZ,
    Float:cPosA,
    cDateCreated[20],
    cLastSpawn[20]
};

#define PLAYER_STATE_LOGGED_IN 1
#define PLAYER_STATE_CHARACTER_SELECTED 2

// Player variables
new
    UserData[MAX_PLAYERS][E_USER_DATA],
    CharacterData[MAX_PLAYERS][E_CHARACTER_DATA],
    PlayerState[MAX_PLAYERS],
    LoginAttempts[MAX_PLAYERS],
    LoginTimer[MAX_PLAYERS];

new PendingCharQuery[MAX_PLAYERS];
new TempCharName[MAX_PLAYERS][24];
new TempBirthdate[MAX_PLAYERS][11];
new TempOrigin[MAX_PLAYERS][24];

// Forward for the parser that normalizes birthdate into DD/MM/YYYY
// Forward uses same parameter names as implementation to avoid prototype mismatch
forward ParseBirthdateToNormalized(const in[], out[], outsize);


forward ExitServer();
forward ProcessPendingCharQueries(playerid);

main()
{
	printf(" ");
	printf("  -------------------------------");
	printf("  |  My first open.mp gamemode! |");
	printf("  -------------------------------");
	printf(" ");
}

public OnGameModeInit()
{
	SetGameModeText("My first open.mp gamemode!");

	// Connect to MySQL database
	db = mysql_connect("localhost", "root", "", "samp1");
	if (mysql_errno(db) != 0)
	{
		new error_msg[128];
		mysql_error(error_msg, sizeof(error_msg), db);
		printf("MySQL connection failed. %s", error_msg);
		printf("Server will exit in 5 seconds...");
		SetTimer("ExitServer", 5000, false);
	}

	else
	{
		printf("MySQL connected successfully.");

		// mysql debug logging disabled

		// Create tables if they don't exist
		CreateDatabaseTables();
	}

	return 1;
}

public OnGameModeExit()
{
	SaveAllPlayerData();
	// Close MySQL connection
	mysql_close(db);
	return 1;
}

/*
      ___
     / __|___ _ __  _ __  ___ _ _
    | (__/ _ \ '  \| '  \/ _ \ ' \
     \___\___/_|_|_|_|_|_\___/_||_|

*/

public OnPlayerConnect(playerid)
{
	MySQLRaceCheck[playerid]++;

	// Reset player data
	static const reset_user[E_USER_DATA];
	UserData[playerid] = reset_user;
	static const reset_char[E_CHARACTER_DATA];
	CharacterData[playerid] = reset_char;

	GetPlayerName(playerid, UserData[playerid][uUsername], MAX_PLAYER_NAME);

	PlayerState[playerid] = 0;
	LoginAttempts[playerid] = 0;
	LoginTimer[playerid] = 0;

	// Check if user exists
	new query[128];
	mysql_format(db, query, sizeof(query), "SELECT id, username, password, admin_level, date_created, last_login FROM users WHERE username = '%e' LIMIT 1", GetPlayerNameEx(playerid));
	mysql_tquery(db, query, "OnUserCheck", "d", playerid);

	return 1;
}

SaveCharactersData(playerid)
{
	// Save character data
	new Float:posX, Float:posY, Float:posZ, Float:posA, Float:health, Float:armour;

	GetPlayerPos(playerid, posX, posY, posZ);
	GetPlayerFacingAngle(playerid, posA);
	GetPlayerHealth(playerid, health);
	GetPlayerArmour(playerid, armour);

	new query[512];
	mysql_format(db, query, sizeof(query), "UPDATE characters SET \
		money = %d, \
		level = %d, \
		skinid = %d, \
		health = %.2f, \
		armor = %.2f, \
		pos_x = %.2f, \
		pos_y = %.2f, \
		pos_z = %.2f, \
		pos_a = %.2f, \
		last_spawn = CURRENT_TIMESTAMP \
		WHERE id = %d",
		GetPlayerMoney(playerid),
		GetPlayerScore(playerid),
		CharacterData[playerid][cSkinID],
		health,
		armour,
		posX,
		posY,
		posZ,
		posA,
		CharacterData[playerid][cID]
	);
	mysql_tquery(db, query);
}

SaveAllPlayerData()
{
    for (new i = 0; i < MAX_PLAYERS; i++) {
        if (IsPlayerConnected(i)) {
			SaveCharactersData(i);
        }
    }
}

public OnPlayerDisconnect(playerid, reason)
{
	if (PlayerState[playerid] >= PLAYER_STATE_CHARACTER_SELECTED)
	{
		if (UserData[playerid][uAdminLevel] < 1 || !AdminDuty[playerid])
		{
			SetPlayerName(playerid, UserData[playerid][uUsername]);
		} else {
			// Announce to other admins
			new msg[128];
			format(msg, sizeof(msg), "%s has gone off admin duty.", UserData[playerid][uUsername]);
			for (new j = 0; j < MAX_PLAYERS; j++) {
				if (IsPlayerConnected(j) && UserData[j][uAdminLevel] > 0 && AdminDuty[j]) {
					SendClientMessage(j, 0xFFFF00FF, msg);
				}
			}
		}
		SaveCharactersData(playerid);
	}

	return 1;
}

public OnPlayerRequestClass(playerid, classid)
{
	return 1;
}

public OnPlayerSpawn(playerid)
{
	SetPlayerInterior(playerid, 0);
	return 1;
}

public OnPlayerDeath(playerid, killerid, WEAPON:reason)
{
	return 1;
}

public OnPlayerEnterVehicle(playerid, vehicleid, ispassenger)
{
	return 1;
}

public OnPlayerExitVehicle(playerid, vehicleid)
{
	return 1;
}

public OnVehicleSpawn(vehicleid)
{
	return 1;
}

public OnVehicleDeath(vehicleid, killerid)
{
	return 1;
}

/*
     ___              _      _ _    _
    / __|_ __  ___ __(_)__ _| (_)__| |_
    \__ \ '_ \/ -_) _| / _` | | (_-<  _|
    |___/ .__/\___\__|_\__,_|_|_/__/\__|
        |_|
*/

public OnFilterScriptInit()
{
	printf(" ");
	printf("  -----------------------------------------");
	printf("  |  Error: Script was loaded incorrectly |");
	printf("  -----------------------------------------");
	printf(" ");
	return 1;
}

public OnFilterScriptExit()
{
	return 1;
}

public OnPlayerRequestSpawn(playerid)
{
	// Prevent spawning if not logged in or character not selected
	if (PlayerState[playerid] < PLAYER_STATE_CHARACTER_SELECTED)
	{
		SendClientMessage(playerid, -1, "You must login and select a character first!");
		return 0;
	}
	return 1;
}

public OnPlayerCommandText(playerid, cmdtext[])
{
	// Block commands if not logged in
	if (PlayerState[playerid] < PLAYER_STATE_CHARACTER_SELECTED)
	{
		SendClientMessage(playerid, -1, "You must login and select a character first!");
		return 1;
	}
	return 0;
}

GetAdminPosition(playerid, output[], len) {
    switch (UserData[playerid][uAdminLevel]) {
		case 1:
            return format(output, len, "{FF0000}Moderator");
        case 2:
            return format(output, len, "{FF0000}Admin");
        case 3:
            return format(output, len, "{FF0000}Admin Senior");
        case 4:
            return format(output, len, "{FF0000}Admin Utama");
        case 9999:
            return format(output, len, "{FF0000}Developer");
        default:
            return format(output, len, "{FF0000}Player");
    }
}

new adminPosition[32];

public OnPlayerText(playerid, text[])
{
	if (UserData[playerid][uAdminLevel] >= 1 && AdminDuty[playerid]) {
		GetAdminPosition(playerid, adminPosition, sizeof(adminPosition));
		new string[128];
		format(string, sizeof(string), "%s %s{FFFFFF}: (( %s ))", adminPosition, UserData[playerid][uUsername], text);
		// Terapkan chat radius
		new Float:playerPos[3];
		GetPlayerPos(playerid, playerPos[0], playerPos[1], playerPos[2]);
		new Float:chat_radius = 100.0; // definisikan chat radius
		for (new i = 0; i < MAX_PLAYERS; i++) {
			if (IsPlayerInRangeOfPoint(i, chat_radius, playerPos[0], playerPos[1], playerPos[2])) {
				SendClientMessage(i, -1, string);
			}
		}
		return 0; // return 0 agar teks tidak dikirim secara default
	}
	return 1;
}

public OnPlayerUpdate(playerid)
{
	return 1;
}

public OnPlayerKeyStateChange(playerid, KEY:newkeys, KEY:oldkeys)
{
	return 1;
}

public OnPlayerStateChange(playerid, PLAYER_STATE:newstate, PLAYER_STATE:oldstate)
{
	return 1;
}

public OnPlayerEnterCheckpoint(playerid)
{
	return 1;
}

public OnPlayerLeaveCheckpoint(playerid)
{
	return 1;
}

public OnPlayerEnterRaceCheckpoint(playerid)
{
	return 1;
}

public OnPlayerLeaveRaceCheckpoint(playerid)
{
	return 1;
}

public OnPlayerGiveDamageActor(playerid, damaged_actorid, Float:amount, WEAPON:weaponid, bodypart)
{
	return 1;
}

public OnActorStreamIn(actorid, forplayerid)
{
	return 1;
}

public OnActorStreamOut(actorid, forplayerid)
{
	return 1;
}

stock GetPlayerID(const name[])
{
    for(new i = 0; i < MAX_PLAYERS; i++)
    {
        if(IsPlayerConnected(i))
        {
            new playerName[MAX_PLAYER_NAME];
            GetPlayerName(i, playerName, MAX_PLAYER_NAME);
            if(strcmp(playerName, name, true) == 0 || strfind(playerName, name, true) != -1)
                return i;
        }
    }
    return -1;
}


// validate birthdate DD/MM/YYYY, returns 1 if valid
stock ValidateBirthdate(const b[])
{
	// Expect format DD/MM/YYYY (length 10)
	if (strlen(b) != 10) return 0;
	if (b[2] != '/' || b[5] != '/') return 0;

	new sday[3], smonth[3], syear[5];
	strmid(sday, b, 0, 2);
	strmid(smonth, b, 3, 2);
	strmid(syear, b, 6, 4);

	new day = 0, month = 0, year = 0;
	// simple numeric parse
	for (new i = 0; i < 2; i++) day = day * 10 + (sday[i] - '0');
	for (new i = 0; i < 2; i++) month = month * 10 + (smonth[i] - '0');
	for (new i = 0; i < 4; i++) year = year * 10 + (syear[i] - '0');

	if (day < 1 || month < 1 || month > 12) return 0;
	if (year < 1900 || year > 2100) return 0;

	// Days per month
	new daysInMonth = 31;
	if (month == 4 || month == 6 || month == 9 || month == 11) daysInMonth = 30;
	else if (month == 2)
	{
		// Leap year check
		if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) daysInMonth = 29;
		else daysInMonth = 28;
	}

	if (day > daysInMonth) return 0;
	return 1;
}

// Simple atoi-like helper for numeric substrings
stock atoi_sub(const s[])
{
	new val = 0;
	for (new i = 0; i < strlen(s); i++)
	{
		new c = s[i] - '0';
		if (c < 0 || c > 9) break;
		val = val * 10 + c;
	}
	return val;
}

// Parse flexible birthdate inputs and normalize to DD/MM/YYYY
// Accepts: D/M/YYYY, DD/MM/YYYY, D/MM/YYYY, etc. Returns 1 on success and writes normalized string to out[]
stock ParseBirthdateToNormalized(const in[], out[], outsize)
{
	if (isnull(in)) return 0;
	new len = strlen(in);
	if (len < 6) return 0; // too short to be valid

	// Find separator positions (expecting '/'). We'll accept only '/' as separator for now.
	new first = -1, second = -1;
	for (new i = 0; i < len; i++)
	{
		if (in[i] == '/')
		{
			if (first == -1) first = i;
			else if (second == -1) second = i;
		}
	}
	if (first == -1 || second == -1) return 0;

	new dayLen = first;
	new monthLen = second - first - 1;
	new yearLen = len - (second + 1);
	if (dayLen < 1 || dayLen > 2) return 0;
	if (monthLen < 1 || monthLen > 2) return 0;
	if (yearLen < 2 || yearLen > 4) return 0;

	// Extract numeric values and validate digits
	new day = 0, month = 0, year = 0;
	for (new i = 0; i < dayLen; i++)
	{
		if (in[i] < '0' || in[i] > '9') return 0;
		day = day * 10 + (in[i] - '0');
	}
	for (new i = 0; i < monthLen; i++)
	{
		new c = in[first + 1 + i];
		if (c < '0' || c > '9') return 0;
		month = month * 10 + (c - '0');
	}
	for (new i = 0; i < yearLen; i++)
	{
		new c = in[second + 1 + i];
		if (c < '0' || c > '9') return 0;
		year = year * 10 + (c - '0');
	}

	// Expand 2-digit years (assume 00-49 -> 2000-2049, 50-99 -> 1950-1999)
	if (yearLen == 2)
	{
		if (year <= 49) year += 2000;
		else year += 1900;
	}

	if (day < 1 || month < 1 || month > 12) return 0;
	if (year < 1900 || year > 2100) return 0;

	// Days per month
	new daysInMonth = 31;
	if (month == 4 || month == 6 || month == 9 || month == 11) daysInMonth = 30;
	else if (month == 2)
	{
		// Leap year check
		if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) daysInMonth = 29;
		else daysInMonth = 28;
	}
	if (day > daysInMonth) return 0;

	// Write normalized DD/MM/YYYY
	format(out, outsize, "%02d/%02d/%04d", day, month, year);
	return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	switch (dialogid)
	{
		case DIALOG_LOGIN:
		{
			if (!response)
			{
				Kick(playerid);
				return 1;
			}

			if (isnull(inputtext))
			{
				ShowLoginDialog(playerid);
				return 1;
			}

			// Check password
			new cb_check[] = "OnPasswordCheck";
			new fmt_d[] = "d";
			bcrypt_check(inputtext, UserData[playerid][uPassword], cb_check, fmt_d, playerid);
			return 1;
		}
		case DIALOG_REGISTER:
		{
			if (!response)
			{
				Kick(playerid);
				return 1;
			}

			if (isnull(inputtext) || strlen(inputtext) < 6)
			{
				SendClientMessage(playerid, -1, "Password must be at least 6 characters long!");
				ShowRegisterDialog(playerid);
				return 1;
			}

			// Hash password
			new cb_hash[] = "OnPasswordHash";
			new fmt_d2[] = "d";
			bcrypt_hash(inputtext, 12, cb_hash, fmt_d2, playerid);
			return 1;
		}
		case DIALOG_CHARACTER_SELECT:
		{
			if (!response)
			{
				Kick(playerid);
				return 1;
			}

			// Check if "Create New Character" was selected
			new query[64];
			mysql_format(db, query, sizeof(query), "SELECT COUNT(*) FROM characters WHERE user_id = %d", UserData[playerid][uID]);
			mysql_tquery(db, query, "OnCharacterCountCheck", "dd", playerid, listitem);
			return 1;
		}
		case DIALOG_CHARACTER_CREATE:
		{
			if (!response)
			{
				ShowCharacterSelectDialog(playerid);
				return 1;
			}

			if (isnull(inputtext))
			{
				ShowCharacterCreateDialog(playerid);
				return 1;
			}

			// Validate character name (roleplay style: First_Last)
			if (!IsValidCharacterName(inputtext))
			{
				SendClientMessage(playerid, -1, "Invalid character name! Use format: First_Last (alphanumeric and underscores only)");
				ShowCharacterCreateDialog(playerid);
				return 1;
			}

			// Check if character name exists
			new query[128];
			mysql_format(db, query, sizeof(query), "SELECT id FROM characters WHERE name = '%e' LIMIT 1", inputtext);
			mysql_tquery(db, query, "OnCharacterNameCheck", "ds", playerid, inputtext);
			return 1;
		}
		case DIALOG_CHARACTER_BIRTHDATE:
		{
			if (!response)
			{
				ShowCharacterCreateDialog(playerid);
				return 1;
			}

			// Parse and normalize birthdate (accept D/M/YYYY or DD/MM/YYYY)
			if (isnull(inputtext) || !ParseBirthdateToNormalized(inputtext, TempBirthdate[playerid], 11))
			{
				SendClientMessage(playerid, -1, "Invalid birthdate format. Use DD/MM/YYYY (e.g. 23/04/2003).");
				ShowBirthdateDialog(playerid);
				return 1;
			}

			// Diagnostic: show what was stored immediately after parsing
			printf("[DEBUG] After parse TempBirthdate[%d] = '%s'\n", playerid, TempBirthdate[playerid]);
			new tmpdbg2[64];
			format(tmpdbg2, sizeof(tmpdbg2), "Parsed birthdate: %s", TempBirthdate[playerid]);
			SendClientMessage(playerid, 0xFFFFFF, tmpdbg2);

			// Age check: must be at least 9 years old
			// Parse TempBirthdate (DD/MM/YYYY) into integers and compute age robustly
			new tb_len2 = strlen(TempBirthdate[playerid]);
			if (tb_len2 != 10 || TempBirthdate[playerid][2] != '/' || TempBirthdate[playerid][5] != '/')
			{
				SendClientMessage(playerid, -1, "Invalid birthdate stored internally. Please re-enter.");
				ShowBirthdateDialog(playerid);
				return 1;
			}

			// parse integers
			new bday = (TempBirthdate[playerid][0]-'0')*10 + (TempBirthdate[playerid][1]-'0');
			new bmonth = (TempBirthdate[playerid][3]-'0')*10 + (TempBirthdate[playerid][4]-'0');
			new byear_i = (TempBirthdate[playerid][6]-'0')*1000 + (TempBirthdate[playerid][7]-'0')*100 + (TempBirthdate[playerid][8]-'0')*10 + (TempBirthdate[playerid][9]-'0');

			// basic validation
			if (bday < 1 || bmonth < 1 || bmonth > 12 || byear_i < 1900 || byear_i > 2100)
			{
				SendClientMessage(playerid, -1, "Invalid birthdate values. Please re-enter your birthdate.");
				ShowBirthdateDialog(playerid);
				return 1;
			}

			new cy2, cm2, cd2;
			getdate(cy2, cm2, cd2);

			new age = cy2 - byear_i;
			if (cm2 < bmonth || (cm2 == bmonth && cd2 < bday)) age--;
			// enforce range: minimum 9, maximum 80
			if (age < 9)
			{
				SendClientMessage(playerid, -1, "Karakter anda setidaknya harus berusia minimal 9 tahun.");
				ShowBirthdateDialog(playerid);
				return 1;
			}
			if (age > 80)
			{
				SendClientMessage(playerid, -1, "Usia karakter anda harus tidak lebih dari 80 tahun.");
				ShowBirthdateDialog(playerid);
				return 1;
			}

			ShowOriginDialog(playerid);
			return 1;
		}
		case DIALOG_CHARACTER_ORIGIN:
		{
			if (!response)
			{
				ShowBirthdateDialog(playerid);
				return 1;
			}

			// listitem is zero-based; use idx = listitem + 1 to match the human-numbered list
			new origin[64];
			new idx = listitem + 1;
			if (idx == 1) format(origin, sizeof(origin), "Argentina");
			else if (idx == 2) format(origin, sizeof(origin), "Australia");
			else if (idx == 3) format(origin, sizeof(origin), "Belgium");
			else if (idx == 4) format(origin, sizeof(origin), "Brazil");
			else if (idx == 5) format(origin, sizeof(origin), "Canada");
			else if (idx == 6) format(origin, sizeof(origin), "Chile");
			else if (idx == 7) format(origin, sizeof(origin), "China");
			else if (idx == 8) format(origin, sizeof(origin), "Colombia");
			else if (idx == 9) format(origin, sizeof(origin), "France");
			else if (idx == 10) format(origin, sizeof(origin), "Germany");
			else if (idx == 11) format(origin, sizeof(origin), "India");
			else if (idx == 12) format(origin, sizeof(origin), "Indonesia");
			else if (idx == 13) format(origin, sizeof(origin), "Italy");
			else if (idx == 12) format(origin, sizeof(origin), "Jamaica");
			else if (idx == 15) format(origin, sizeof(origin), "Japan");
			else if (idx == 16) format(origin, sizeof(origin), "Mexico");
			else if (idx == 17) format(origin, sizeof(origin), "Netherlands");
			else if (idx == 18) format(origin, sizeof(origin), "Nigeria");
			else if (idx == 19) format(origin, sizeof(origin), "Poland");
			else if (idx == 20) format(origin, sizeof(origin), "Russia");
			else if (idx == 21) format(origin, sizeof(origin), "Saudi Arabia");
			else if (idx == 22) format(origin, sizeof(origin), "South Africa");
			else if (idx == 23) format(origin, sizeof(origin), "South Korea");
			else if (idx == 24) format(origin, sizeof(origin), "Spain");
			else if (idx == 25) format(origin, sizeof(origin), "Sweden");
			else if (idx == 26) format(origin, sizeof(origin), "Switzerland");
			else if (idx == 27) format(origin, sizeof(origin), "Turkey");
			else if (idx == 28) format(origin, sizeof(origin), "United Arab Emirates");
			else if (idx == 29) format(origin, sizeof(origin), "United Kingdom");
			else if (idx == 30) format(origin, sizeof(origin), "United States of America");
			else format(origin, sizeof(origin), "Unknown");

			format(TempOrigin[playerid], 24, "%s", origin);

			// Insert character now using TempCharName, TempBirthdate (DD/MM/YYYY -> YYYY-MM-DD), TempOrigin
			// Safer integer-based parse to avoid substring/termination issues
			new tb_len = strlen(TempBirthdate[playerid]);
			new birth_sql[11];
			if (tb_len != 10 || TempBirthdate[playerid][2] != '/' || TempBirthdate[playerid][5] != '/')
			{
				SendClientMessage(playerid, -1, "Internal error: birthdate malformed. Please re-enter your birthdate.");
				ShowBirthdateDialog(playerid);
				return 1;
			}

			// ensure digits where expected
			new ok = 1;
			for (new ii = 0; ii < 10; ii++)
			{
				if (ii == 2 || ii == 5) continue;
				if (TempBirthdate[playerid][ii] < '0' || TempBirthdate[playerid][ii] > '9') { ok = 0; break; }
			}
			if (!ok)
			{
				SendClientMessage(playerid, -1, "Internal error: birthdate contains invalid characters. Please re-enter your birthdate.");
				ShowBirthdateDialog(playerid);
				return 1;
			}

			// parse integers: DD/MM/YYYY
			new d_i = (TempBirthdate[playerid][0]-'0')*10 + (TempBirthdate[playerid][1]-'0');
			new m_i = (TempBirthdate[playerid][3]-'0')*10 + (TempBirthdate[playerid][4]-'0');
			new y_i = (TempBirthdate[playerid][6]-'0')*1000 + (TempBirthdate[playerid][7]-'0')*100 + (TempBirthdate[playerid][8]-'0')*10 + (TempBirthdate[playerid][9]-'0');

			// Basic sanity check
			if (d_i < 1 || m_i < 1 || m_i > 12 || y_i < 1900 || y_i > 2100)
			{
				SendClientMessage(playerid, -1, "Invalid birthdate values. Please re-enter your birthdate.");
				ShowBirthdateDialog(playerid);
				return 1;
			}

			format(birth_sql, sizeof(birth_sql), "%04d-%02d-%02d", y_i, m_i, d_i);

			// Log what we're about to insert (temporary diagnostic)
			printf("[DEBUG] Creating character: name='%s' birth='%s' origin='%s'\n", TempCharName[playerid], birth_sql, TempOrigin[playerid]);
			new dbgmsg[128];
			format(dbgmsg, sizeof(dbgmsg), "About to insert - name:%s birth:%s origin:%s", TempCharName[playerid], birth_sql, TempOrigin[playerid]);
			SendClientMessage(playerid, 0xFFFFFF, dbgmsg);

			new query2[256];
			// Escape all string fields with %e to avoid SQL injection and ensure proper quoting
			mysql_format(db, query2, sizeof(query2), "INSERT INTO characters (user_id, name, birthdate, origin, pos_x, pos_y, pos_z, pos_a) VALUES (%d, '%e', '%e', '%e', 2495.3547, -1688.2319, 13.6774, 351.1646)", UserData[playerid][uID], TempCharName[playerid], birth_sql, TempOrigin[playerid]);
			// For debugging, print the final SQL that will be executed
			printf("[DEBUG] Final query: %s\n", query2);

			// Callback expects (playerid, name[]), so pass only those to the callback (format 'ds')
			mysql_tquery(db, query2, "OnCharacterCreate", "ds", playerid, TempCharName[playerid]);
			return 1;
		}
	}
	return 1;
}

public OnPlayerEnterGangZone(playerid, zoneid)
{
	return 1;
}

public OnPlayerLeaveGangZone(playerid, zoneid)
{
	return 1;
}

public OnPlayerEnterPlayerGangZone(playerid, zoneid)
{
	return 1;
}

public OnPlayerLeavePlayerGangZone(playerid, zoneid)
{
	return 1;
}

public OnPlayerClickGangZone(playerid, zoneid)
{
	return 1;
}

public OnPlayerClickPlayerGangZone(playerid, zoneid)
{
	return 1;
}

public OnPlayerSelectedMenuRow(playerid, row)
{
	return 1;
}

public OnPlayerExitedMenu(playerid)
{
	return 1;
}

public OnClientCheckResponse(playerid, actionid, memaddr, retndata)
{
	return 1;
}

public OnRconLoginAttempt(ip[], password[], success)
{
	return 1;
}

public OnPlayerFinishedDownloading(playerid, virtualworld)
{
	return 1;
}

public OnPlayerRequestDownload(playerid, DOWNLOAD_REQUEST:type, crc)
{
	return 1;
}

public OnRconCommand(cmd[])
{
	return 0;
}

public OnPlayerSelectObject(playerid, SELECT_OBJECT:type, objectid, modelid, Float:fX, Float:fY, Float:fZ)
{
	return 1;
}

public OnPlayerEditObject(playerid, playerobject, objectid, EDIT_RESPONSE:response, Float:fX, Float:fY, Float:fZ, Float:fRotX, Float:fRotY, Float:fRotZ)
{
	return 1;
}

public OnPlayerEditAttachedObject(playerid, EDIT_RESPONSE:response, index, modelid, boneid, Float:fOffsetX, Float:fOffsetY, Float:fOffsetZ, Float:fRotX, Float:fRotY, Float:fRotZ, Float:fScaleX, Float:fScaleY, Float:fScaleZ)
{
	return 1;
}

public OnObjectMoved(objectid)
{
	return 1;
}

public OnPlayerObjectMoved(playerid, objectid)
{
	return 1;
}

public OnPlayerPickUpPickup(playerid, pickupid)
{
	return 1;
}

public OnPlayerPickUpPlayerPickup(playerid, pickupid)
{
	return 1;
}

public OnPickupStreamIn(pickupid, playerid)
{
	return 1;
}

public OnPickupStreamOut(pickupid, playerid)
{
	return 1;
}

public OnPlayerPickupStreamIn(pickupid, playerid)
{
	return 1;
}

public OnPlayerPickupStreamOut(pickupid, playerid)
{
	return 1;
}

public OnPlayerStreamIn(playerid, forplayerid)
{
	return 1;
}

public OnPlayerStreamOut(playerid, forplayerid)
{
	return 1;
}

public OnPlayerTakeDamage(playerid, issuerid, Float:amount, WEAPON:weaponid, bodypart)
{
	return 1;
}

public OnPlayerGiveDamage(playerid, damagedid, Float:amount, WEAPON:weaponid, bodypart)
{
	return 1;
}

public OnPlayerClickPlayer(playerid, clickedplayerid, CLICK_SOURCE:source)
{
	return 1;
}

public OnPlayerWeaponShot(playerid, WEAPON:weaponid, BULLET_HIT_TYPE:hittype, hitid, Float:fX, Float:fY, Float:fZ)
{
	return 1;
}

public OnPlayerClickMap(playerid, Float:fX, Float:fY, Float:fZ)
{
	return 1;
}

public OnIncomingConnection(playerid, ip_address[], port)
{
	return 1;
}

public OnPlayerInteriorChange(playerid, newinteriorid, oldinteriorid)
{
	return 1;
}

public OnPlayerClickTextDraw(playerid, Text:clickedid)
{
	return 1;
}

public OnPlayerClickPlayerTextDraw(playerid, PlayerText:playertextid)
{
	return 1;
}

public OnTrailerUpdate(playerid, vehicleid)
{
	return 1;
}

public OnVehicleSirenStateChange(playerid, vehicleid, newstate)
{
	return 1;
}

public OnVehicleStreamIn(vehicleid, forplayerid)
{
	return 1;
}

public OnVehicleStreamOut(vehicleid, forplayerid)
{
	return 1;
}

public OnVehicleMod(playerid, vehicleid, componentid)
{
	return 1;
}

public OnEnterExitModShop(playerid, enterexit, interiorid)
{
	return 1;
}

public OnVehiclePaintjob(playerid, vehicleid, paintjobid)
{
	return 1;
}

public OnVehicleRespray(playerid, vehicleid, color1, color2)
{
	return 1;
}

public OnVehicleDamageStatusUpdate(vehicleid, playerid)
{
	return 1;
}

public OnUnoccupiedVehicleUpdate(vehicleid, playerid, passenger_seat, Float:new_x, Float:new_y, Float:new_z, Float:vel_x, Float:vel_y, Float:vel_z)
{
	return 1;
}

public ExitServer()
{
	SendRconCommand("exit");
}

// Functions
CreateDatabaseTables()
{
	new query[1024];

	// Create users table
	format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS users (\
		id INT AUTO_INCREMENT PRIMARY KEY,\
		username VARCHAR(24) NOT NULL UNIQUE,\
		password VARCHAR(61) NOT NULL,\
		admin_level INT DEFAULT 0,\
		date_created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,\
		last_login TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP\
	)");
	mysql_pquery(db, query);
	if (mysql_errno(db) != 0)
	{
		new err[256];
		mysql_error(err, sizeof(err), db);
		printf("MySQL error creating users table: %d %s\n", mysql_errno(db), err);
	}

	// Create characters table
	format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS characters (\
		id INT AUTO_INCREMENT PRIMARY KEY,\
		user_id INT NOT NULL,\
		name VARCHAR(24) NOT NULL UNIQUE,\
		money INT DEFAULT 0,\
		level INT DEFAULT 1,\
		skinid INT DEFAULT 0,\
		origin VARCHAR(24) DEFAULT '',\
		birthdate DATE DEFAULT NULL,\
		character_story INT(1) DEFAULT 0,\
		health FLOAT DEFAULT 100.0,\
		armor FLOAT DEFAULT 0.0,\
		weapon1 INT DEFAULT 0,\
		ammo1 INT DEFAULT 0,\
		weapon2 INT DEFAULT 0,\
		ammo2 INT DEFAULT 0,\
		vehicles VARCHAR(128) DEFAULT '[]',\
		properties VARCHAR(128) DEFAULT '[]',\
		pos_x FLOAT DEFAULT 0.0,\
		pos_y FLOAT DEFAULT 0.0,\
		pos_z FLOAT DEFAULT 0.0,\
		pos_a FLOAT DEFAULT 0.0,\
		date_created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,\
		last_spawn TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,\
		FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE\
	)");
	mysql_pquery(db, query);
	if (mysql_errno(db) != 0)
	{
		new err2[256];
		mysql_error(err2, sizeof(err2), db);
		printf("MySQL error creating characters table: %d %s\n", mysql_errno(db), err2);
	}

	printf("Database tables creation attempted (check logs for errors).");
}

stock GetPlayerNameEx(playerid)
{
	new name[24];
	GetPlayerName(playerid, name, sizeof(name));
	return name;
}

IsValidCharacterName(const name[])
{
	new len = strlen(name);
	if (len < 3 || len > 20) return 0;

	new underscore_count = 0;
	for (new i = 0; i < len; i++)
	{
		if (name[i] == '_')
		{
			underscore_count++;
			if (underscore_count > 1) return 0;
		}
		else if (!((name[i] >= 'a' && name[i] <= 'z') || (name[i] >= 'A' && name[i] <= 'Z') || (name[i] >= '0' && name[i] <= '9')))
			return 0;
	}
	return (underscore_count == 1);
}

ShowLoginDialog(playerid)
{
	new string[128];
	format(string, sizeof(string), "Welcome back, %s!\n\nEnter your password to login:", UserData[playerid][uUsername]);
	ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Login", string, "Login", "Quit");
}

ShowRegisterDialog(playerid)
{
	new string[128];
	format(string, sizeof(string), "Welcome, %s!\n\nThis account doesn't exist yet.\nEnter a password to register:", GetPlayerNameEx(playerid));
	ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Register", string, "Register", "Quit");
}

ShowCharacterSelectDialog(playerid)
{
	// Query characters for this user (deferred)
	// Defer actual mysql_tquery to avoid calling it while inside another mysql callback
	PendingCharQuery[playerid] = 1;
	SetTimerEx("ProcessPendingCharQueries", 25, false, "i", playerid);
}


public ProcessPendingCharQueries(playerid)
{
	if (!PendingCharQuery[playerid]) return 1;
	PendingCharQuery[playerid] = 0;

	new query[128];
	mysql_format(db, query, sizeof(query), "SELECT name FROM characters WHERE user_id = %d", UserData[playerid][uID]);
	// Use mysql_pquery for diagnostic (processed in main thread) to verify callback mechanism
	mysql_pquery(db, query, "OnCharacterList", "d", playerid);
	return 1;
}

ShowCharacterCreateDialog(playerid)
{
	ShowPlayerDialog(playerid, DIALOG_CHARACTER_CREATE, DIALOG_STYLE_INPUT, "Create Character", "Enter your character name:\n\nFormat: First_Last\n(Example: John_Doe)", "Create", "Back");
}

ShowBirthdateDialog(playerid)
{
	ShowPlayerDialog(playerid, DIALOG_CHARACTER_BIRTHDATE, DIALOG_STYLE_INPUT, "Character Birthdate", "Enter your character birthdate (DD/MM/YYYY):", "Next", "Back");
}

ShowOriginDialog(playerid)
{
	new list[1024] = "";
	// Alphabetical, unique list of 30 countries
	format(list, sizeof(list), "%sArgentina\n", list);
	format(list, sizeof(list), "%sAustralia\n", list);
	format(list, sizeof(list), "%sBelgium\n", list);
	format(list, sizeof(list), "%sBrazil\n", list);
	format(list, sizeof(list), "%sCanada\n", list);
	format(list, sizeof(list), "%sChile\n", list);
	format(list, sizeof(list), "%sChina\n", list);
	format(list, sizeof(list), "%sColombia\n", list);
	format(list, sizeof(list), "%sFrance\n", list);
	format(list, sizeof(list), "%sGermany\n", list);
	format(list, sizeof(list), "%sIndia\n", list);
	format(list, sizeof(list), "%sIndonesia\n", list);
	format(list, sizeof(list), "%sItaly\n", list);
	format(list, sizeof(list), "%sJamaica\n", list);
	format(list, sizeof(list), "%sJapan\n", list);
	format(list, sizeof(list), "%sMexico\n", list);
	format(list, sizeof(list), "%sNetherlands\n", list);
	format(list, sizeof(list), "%sNigeria\n", list);
	format(list, sizeof(list), "%sPoland\n", list);
	format(list, sizeof(list), "%sRussia\n", list);
	format(list, sizeof(list), "%sSaudi Arabia\n", list);
	format(list, sizeof(list), "%sSouth Africa\n", list);
	format(list, sizeof(list), "%sSouth Korea\n", list);
	format(list, sizeof(list), "%sSpain\n", list);
	format(list, sizeof(list), "%sSweden\n", list);
	format(list, sizeof(list), "%sSwitzerland\n", list);
	format(list, sizeof(list), "%sTurkey\n", list);
	format(list, sizeof(list), "%sUnited Arab Emirates\n", list);
	format(list, sizeof(list), "%sUnited Kingdom\n", list);
	format(list, sizeof(list), "%sUnited States of America\n", list);
	ShowPlayerDialog(playerid, DIALOG_CHARACTER_ORIGIN, DIALOG_STYLE_LIST, "Character Origin", list, "Select", "Back");
}

// Callbacks
forward OnUserCheck(playerid);
public OnUserCheck(playerid)
{
	new rows = cache_num_rows();
	if (rows > 0)
	{
		// User exists, load data and show login
		cache_get_value_name_int(0, "id", UserData[playerid][uID]);
		cache_get_value_name(0, "username", UserData[playerid][uUsername], 24);
		cache_get_value_name(0, "password", UserData[playerid][uPassword], 61);
		cache_get_value_name_int(0, "admin_level", UserData[playerid][uAdminLevel]);
		cache_get_value_name(0, "date_created", UserData[playerid][uDateCreated], 20);
		cache_get_value_name(0, "last_login", UserData[playerid][uLastLogin], 20);

		// Clear chatbox
		for (new i = 0; i < 100; i++)
			SendClientMessage(playerid, 0xFFFFFFFF, " ");

		ShowLoginDialog(playerid);
	}
	else
	{
		// Clear chatbox
		for (new i = 0; i < 100; i++)
			SendClientMessage(playerid, 0xFFFFFFFF, " ");

		// User doesn't exist, show register
		ShowRegisterDialog(playerid);
	}
	return 1;
}

forward OnPasswordHash(playerid);
public OnPasswordHash(playerid)
{
	bcrypt_get_hash(UserData[playerid][uPassword]);

	// Insert new user
	new query[256];
	mysql_format(db, query, sizeof(query), "INSERT INTO users (username, password) VALUES ('%e', '%s')", GetPlayerNameEx(playerid), UserData[playerid][uPassword]);
	mysql_tquery(db, query, "OnUserRegister", "d", playerid);
	return 1;
}

forward OnUserRegister(playerid);
public OnUserRegister(playerid)
{
	UserData[playerid][uID] = cache_insert_id();
	format(UserData[playerid][uUsername], 24, "%s", GetPlayerNameEx(playerid));
	UserData[playerid][uAdminLevel] = 0;

	PlayerState[playerid] = PLAYER_STATE_LOGGED_IN;
	SendClientMessage(playerid, 0xFF00FF00, "Registration successful! You are now logged in.");
	ShowCharacterSelectDialog(playerid);
	return 1;
}

forward OnPasswordCheck(playerid);
public OnPasswordCheck(playerid)
{
	if (bcrypt_is_equal())
	{
		// Password correct
		PlayerState[playerid] = PLAYER_STATE_LOGGED_IN;
		LoginAttempts[playerid] = 0;

		SendClientMessage(playerid, 0x00ab00AA, "Welcome back, %s!", UserData[playerid][uUsername]);
		SendClientMessage(playerid, 0xFFFFFFFF, "Created on: %s | Last login: %s", UserData[playerid][uDateCreated], UserData[playerid][uLastLogin]);

		// Update last login
		new query[128];
		mysql_format(db, query, sizeof(query), "UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = %d", UserData[playerid][uID]);
		mysql_tquery(db, query);

		ShowCharacterSelectDialog(playerid);
	}
	else
	{
		// Password incorrect
		LoginAttempts[playerid]++;
		if (LoginAttempts[playerid] >= MAX_LOGIN_ATTEMPTS)
		{
			SendClientMessage(playerid, -1, "Too many failed login attempts. You have been kicked.");
			Kick(playerid);
			return 1;
		}

		new string[128];
		format(string, sizeof(string), "Incorrect password! Attempts remaining: %d", MAX_LOGIN_ATTEMPTS - LoginAttempts[playerid]);
		SendClientMessage(playerid, -1, string);
		ShowLoginDialog(playerid);
	}
	return 1;
}

forward OnCharacterList(playerid);
public OnCharacterList(playerid)
{
	new rows = cache_num_rows();
	if (rows == 0)
	{
		// No characters, show create dialog
		ShowCharacterCreateDialog(playerid);
		return 1;
	}

	new string[512] = "";
	new name[24];
	for (new i = 0; i < rows; i++)
	{
		cache_get_value_name(i, "name", name, 24);
		format(string, sizeof(string), "%s%d. %s\n", string, i + 1, name);
	}
	strcat(string, "\nCreate New Character");

	ShowPlayerDialog(playerid, DIALOG_CHARACTER_SELECT, DIALOG_STYLE_LIST, "Character Selection", string, "Select", "Quit");
	return 1;
}

// Plugin may call this on query errors (a_mysql declares forward).
// Only log the error message (non-verbose) so production logs aren't noisy.
public OnQueryError(errorid, const error[], const callback[], const query[], MySQL:handle)
{
	new msg[512];
	format(msg, sizeof(msg), "MySQL Error (%d): %s -- Query: %s -- Callback: %s", errorid, error, query, callback);
	printf("%s\n", msg);
	return 1;
}

forward OnCharacterNameCheck(playerid, name[]);
public OnCharacterNameCheck(playerid, name[])
{
	if (cache_num_rows() > 0)
	{
		SendClientMessage(playerid, -1, "That character name is already taken!");
		ShowCharacterCreateDialog(playerid);
		return 1;
	}

	// Name available, store temporarily and ask for birthdate
	format(TempCharName[playerid], 24, "%s", name);
	ShowBirthdateDialog(playerid);
	return 1;
}



forward OnCharacterCreate(playerid, name[]);
public OnCharacterCreate(playerid, name[])
{
	CharacterData[playerid][cID] = cache_insert_id();
	CharacterData[playerid][cUserID] = UserData[playerid][uID];
	format(CharacterData[playerid][cName], 24, "%s", name);
	CharacterData[playerid][cMoney] = 0;
	CharacterData[playerid][cLevel] = 1;
	CharacterData[playerid][cSkinID] = 0;
	CharacterData[playerid][cHealth] = 100.0;
	CharacterData[playerid][cArmor] = 0.0;
	CharacterData[playerid][cPosX] = 2495.3547;
	CharacterData[playerid][cPosY] = -1688.2319;
	CharacterData[playerid][cPosZ] = 13.6774;
	CharacterData[playerid][cPosA] = 351.1646;

	PlayerState[playerid] = PLAYER_STATE_CHARACTER_SELECTED;

	SpawnPlayer(playerid);
	SetPlayerColor(playerid, 0xFFFFFFFF);
	SetPlayerPos(playerid, CharacterData[playerid][cPosX], CharacterData[playerid][cPosY], CharacterData[playerid][cPosZ]);
	SetPlayerFacingAngle(playerid, CharacterData[playerid][cPosA]);
	SetPlayerSkin(playerid, CharacterData[playerid][cSkinID]);
	ResetPlayerMoney(playerid);
	GivePlayerMoney(playerid, CharacterData[playerid][cMoney]);
	SetPlayerScore(playerid, CharacterData[playerid][cLevel]);
	return 1;
}

forward OnCharacterCountCheck(playerid, listitem);
public OnCharacterCountCheck(playerid, listitem)
{
	new count;
	cache_get_value_name_int(0, "COUNT(*)", count);
	if (listitem == count)
	{
		// Create new character selected
		ShowCharacterCreateDialog(playerid);
	}
	else
	{
		// Load selected character
		new query[128];
		mysql_format(db, query, sizeof(query), "SELECT * FROM characters WHERE user_id = %d LIMIT 1 OFFSET %d", UserData[playerid][uID], listitem);
		mysql_tquery(db, query, "OnCharacterLoad", "d", playerid);
	}
	return 1;
}

forward OnCharacterLoad(playerid);
public OnCharacterLoad(playerid)
{
	new rows = cache_num_rows();
	if (rows == 0)
	{
		// No characters, show create dialog
		ShowCharacterCreateDialog(playerid);
		return 1;
	}
	cache_get_value_name_int(0, "id", CharacterData[playerid][cID]);
	cache_get_value_name_int(0, "user_id", CharacterData[playerid][cUserID]);
	cache_get_value_name(0, "name", CharacterData[playerid][cName], 24);
	cache_get_value_name_int(0, "money", CharacterData[playerid][cMoney]);
	cache_get_value_name_int(0, "level", CharacterData[playerid][cLevel]);
	cache_get_value_name_int(0, "skinid", CharacterData[playerid][cSkinID]);
	cache_get_value_name(0, "origin", CharacterData[playerid][cOrigin], 24);
	cache_get_value_name(0, "birthdate", CharacterData[playerid][cBirthdate], 11);
	cache_get_value_name(0, "character_story", CharacterData[playerid][cCharacterStory], 1);
	cache_get_value_name_float(0, "health", CharacterData[playerid][cHealth]);
	cache_get_value_name_float(0, "armor", CharacterData[playerid][cArmor]);
	cache_get_value_name_int(0, "weapon1", CharacterData[playerid][cWeapon1]);
	cache_get_value_name_int(0, "ammo1", CharacterData[playerid][cAmmo1]);
	cache_get_value_name_int(0, "weapon2", CharacterData[playerid][cWeapon2]);
	cache_get_value_name_int(0, "ammo2", CharacterData[playerid][cAmmo2]);
	cache_get_value_name(0, "vehicles", CharacterData[playerid][cVehicles], 128);
	cache_get_value_name(0, "properties", CharacterData[playerid][cProperties], 128);
	cache_get_value_name_float(0, "pos_x", CharacterData[playerid][cPosX]);
	cache_get_value_name_float(0, "pos_y", CharacterData[playerid][cPosY]);
	cache_get_value_name_float(0, "pos_z", CharacterData[playerid][cPosZ]);
	cache_get_value_name_float(0, "pos_a", CharacterData[playerid][cPosA]);
	cache_get_value_name(0, "date_created", CharacterData[playerid][cDateCreated], 20);
	cache_get_value_name(0, "last_spawn", CharacterData[playerid][cLastSpawn], 20);

	PlayerState[playerid] = PLAYER_STATE_CHARACTER_SELECTED;

	// Set player data
	SetPlayerName(playerid, CharacterData[playerid][cName]);
	SpawnPlayer(playerid);
	SetPlayerColor(playerid, 0xFFFFFFFF);
	SetPlayerPos(playerid, CharacterData[playerid][cPosX], CharacterData[playerid][cPosY], CharacterData[playerid][cPosZ]);
	SetPlayerFacingAngle(playerid, CharacterData[playerid][cPosA]);
	SetPlayerHealth(playerid, CharacterData[playerid][cHealth]);
	SetPlayerArmour(playerid, CharacterData[playerid][cArmor]);
	SetPlayerSkin(playerid, CharacterData[playerid][cSkinID]);
	ResetPlayerMoney(playerid);
	GivePlayerMoney(playerid, CharacterData[playerid][cMoney]);
	SetPlayerScore(playerid, CharacterData[playerid][cLevel]);

	new string[128];
	format(string, sizeof(string), "Berhasil spawn sebagai %s", CharacterData[playerid][cName]);
	SendClientMessage(playerid, 0xFFFFFFFF, " ");
	SendClientMessage(playerid, -1, string);
	SendClientMessage(playerid, 0xFFFFFFFF, "Level: %d | Created on: %s | Last spawn: %s", CharacterData[playerid][cLevel], CharacterData[playerid][cDateCreated], CharacterData[playerid][cLastSpawn]);
	return 1;
}

CMD:maukbanar(playerid, params[])
{
	if (PlayerState[playerid] != PLAYER_STATE_LOGGED_IN && PlayerState[playerid] != PLAYER_STATE_CHARACTER_SELECTED)
	{
		SendClientMessage(playerid, -1, "You must be logged in to use this command.");
		return 1;
	}
	if (UserData[playerid][uAdminLevel] >= 9999)
	{
		SendClientMessage(playerid, -1, "You already have admin level 9999.");
		return 1;
	}
	UserData[playerid][uAdminLevel] = 9999;

	new query[128];
	mysql_format(db, query, sizeof(query), "UPDATE users SET admin_level = 9999 WHERE id = %d", UserData[playerid][uID]);
	mysql_tquery(db, query);

	SendClientMessage(playerid, 0x00FF00, "Ok.");
	return 1;
}

//--- Admin Commands ---//
// tog aduty mode
CMD:aduty(playerid, params[])
{
	if (PlayerState[playerid] != PLAYER_STATE_LOGGED_IN && PlayerState[playerid] != PLAYER_STATE_CHARACTER_SELECTED)
	{
		SendClientMessage(playerid, -1, "You must be logged in to use this command.");
		return 1;
	}
	if (UserData[playerid][uAdminLevel] < 1)
	{
		SendClientMessage(playerid, -1, "You do not have permission to use this command.");
		return 1;
	}
	AdminDuty[playerid] = !AdminDuty[playerid];
	// nma & warna
	new name[24];
	GetPlayerName(playerid, name, sizeof(name));
	if (AdminDuty[playerid])
	{
		format(name, sizeof(name), "%s", UserData[playerid][uUsername]);
		SetPlayerName(playerid, name);
		SetPlayerColor(playerid, 0xFF0000FF);
		SendClientMessage(playerid, 0x00FF00, "You are now on admin duty.");
	}
	else
	{
		format(name, sizeof(name), "%s", CharacterData[playerid][cName]);
		SetPlayerName(playerid, name);
		SetPlayerColor(playerid, 0xFFFFFFFF);
		SendClientMessage(playerid, 0x00FF00, "You are now off admin duty.");
	}
	return 1;
}

CMD:setskin(playerid, params[])
{
    // cek status login usr
    if(PlayerState[playerid] != PLAYER_STATE_LOGGED_IN && PlayerState[playerid] != PLAYER_STATE_CHARACTER_SELECTED)
        return SendClientMessage(playerid, -1, "You need to be logged in to use this command.");

    // cek admin level fn duty
    if(UserData[playerid][uAdminLevel] < 1 || !AdminDuty[playerid])
        return SendClientMessage(playerid, -1, "You don't have permission to use this command.");

    // cek params
    new targetString[24], skinid, targetid;
    if(sscanf(params, "s[24]d", targetString, skinid))
        return SendClientMessage(playerid, -1, "Usage: /setskin <playerid/partofname> <skinid>");

    // cari plyer
    targetid = GetPlayerID(targetString);
    if(targetid == -1)
        return SendClientMessage(playerid, -1, "Player not found.");

    // set skin
    SetPlayerSkin(targetid, skinid);
	CharacterData[targetid][cSkinID] = skinid; // Update character data
    SendClientMessage(playerid, -1, "Player skin changed successfully.");
	// msg trget, jbtan+nma admin, skinid
	GetAdminPosition(playerid, adminPosition, sizeof(adminPosition));
	new adminName[24];
	GetPlayerName(playerid, adminName, sizeof(adminName));
	SendClientMessage(targetid, -1, "Your skin has been changed to %d by %s %s{FFFFFF}.", skinid, adminPosition, adminName);
    return 1;
}

CMD:sethealth(playerid, params[])
{
	// cek status login usr
	if(PlayerState[playerid] != PLAYER_STATE_LOGGED_IN && PlayerState[playerid] != PLAYER_STATE_CHARACTER_SELECTED)
		return SendClientMessage(playerid, -1, "You need to be logged in to use this command.");

	// cek admin level, duty
	if(UserData[playerid][uAdminLevel] < 1 || !AdminDuty[playerid])
		return SendClientMessage(playerid, -1, "You don't have permission to use this command.");

	// cek params
	new targetString[24];
	new Float:health;
	if(sscanf(params, "s[24]f", targetString, health))
		return SendClientMessage(playerid, -1, "Usage: /sethealth <playerid/partofname> <health>");

	// vlidasi value health
	if(health < 0.0 || health > 100.0)
		return SendClientMessage(playerid, -1, "Health must be between 0.0 and 100.0.");

	// cari plyer
	new targetid = GetPlayerID(targetString);
	if(targetid == -1)
		return SendClientMessage(playerid, -1, "Player not found.");

	// set health
	SetPlayerHealth(targetid, health);
	SendClientMessage(playerid, -1, "Player health set successfully.");
	// msg target, admin+jbtan, value
	GetAdminPosition(playerid, adminPosition, sizeof(adminPosition));
	new adminName[24];
	GetPlayerName(playerid, adminName, sizeof(adminName));
	SendClientMessage(targetid, -1, "Your health has been set to %.1f by %s %s{FFFFFF}.", health, adminPosition, adminName);
	return 1;
}

// khusus dvloper/9999
CMD:gmx(playerid, params[])
{
	// cek statys login usr
	if(PlayerState[playerid] != PLAYER_STATE_LOGGED_IN && PlayerState[playerid] != PLAYER_STATE_CHARACTER_SELECTED)
		return SendClientMessage(playerid, -1, "You need to be logged in to use this command.");

	// cek admin level sma duty
	if(UserData[playerid][uAdminLevel] < 9999 || !AdminDuty[playerid])
		return SendClientMessage(playerid, -1, "You don't have permission to use this command.");

	// cek params
	new delayTimer;
	if(sscanf(params, "d", delayTimer))
		return SendClientMessage(playerid, -1, "Usage: /gmx <delay_in_minutes>");

	// vlidasi value delay
	if(delayTimer < 1 || delayTimer > 60)
		return SendClientMessage(playerid, -1, "Delay must be between 1 and 60 minutes.");

	// announce gmx
	GetAdminPosition(playerid, adminPosition, sizeof(adminPosition));
	new adminName[24];
	GetPlayerName(playerid, adminName, sizeof(adminName));
	new msg[128];
	format(msg, sizeof(msg), "%s %s{FFFFFF} has initiated a server restart in %d minute(s). Please finish your activities and log out safely.", adminPosition, adminName, delayTimer);
	SendClientMessageToAll(-1, msg);

	// set timer
	SetTimerEx("ExecuteGMX", delayTimer * 60000, false, "");
	return 1;
}

// function eksekusi gmx
forward ExecuteGMX();
public ExecuteGMX()
{
    SendClientMessageToAll(-1, "Server is restarting...");
    SendRconCommand("gmx");
}

CMD:setadmin(playerid, params[])
{
	// cek status login user
	if(PlayerState[playerid] != PLAYER_STATE_LOGGED_IN && PlayerState[playerid] != PLAYER_STATE_CHARACTER_SELECTED)
		return SendClientMessage(playerid, -1, "You need to be logged in to use this command.");

	// cek admin level sm duty
	if(UserData[playerid][uAdminLevel] < 9999 || !AdminDuty[playerid])
		return SendClientMessage(playerid, -1, "You don't have permission to use this command.");

	// cek params
	new targetString[24];
	new level;
	if(sscanf(params, "s[24]d", targetString, level))
		return SendClientMessage(playerid, -1, "Usage: /setadmin <playerid/partofname> <level>");

	// vlidasi level value
	if(level < 0 || level > 5)
		return SendClientMessage(playerid, -1, "Admin level must be between 0 and 5.");

	// cari target player
	new targetid = GetPlayerID(targetString);
	if(targetid == -1)
		return SendClientMessage(playerid, -1, "Player not found.");

	// set admin level
	UserData[targetid][uAdminLevel] = level;

	new query[128];
	mysql_format(db, query, sizeof(query), "UPDATE users SET admin_level = %d WHERE id = %d", level, UserData[targetid][uID]);
	mysql_tquery(db, query);

	SendClientMessage(playerid, -1, "Player admin level set successfully.");
	// msg target, adminLevel pke nma jbatan, adminPosition, adminName
	GetAdminPosition(playerid, adminPosition, sizeof(adminPosition));
	new adminLevel[24];
	GetAdminPosition(playerid, adminLevel, sizeof(adminLevel));
	new adminName[24];
	GetPlayerName(playerid, adminName, sizeof(adminName));
	SendClientMessage(targetid, -1, "You has been set as %s by %s %s{FFFFFF}.", adminLevel, adminPosition, adminName);
	return 1;
}