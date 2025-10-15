# Login/Register System Implementation TODO

- [ ] 1. Add includes and defines: Include bcrypt.inc and mdialog.inc, define dialog IDs, timeouts, max attempts, and table creation queries.
- [ ] 2. Define player data enums: Create enums for user data (id, username, password, admin_level, etc.) and character data (name, money, etc.), plus login state variables.
- [ ] 3. Create database tables: In OnGameModeInit, execute CREATE TABLE queries for users and characters if they don't exist.
- [ ] 4. Implement login/register flow: In OnPlayerConnect, query database for user existence and show appropriate dialog (login or register).
- [ ] 5. Create dialog functions: Use mdialog to create dialogs for login, register, character selection, and creation.
- [ ] 6. Handle dialog responses: In OnDialogResponse, process inputs, validate, hash/check passwords, query database, handle attempts/timeouts.
- [ ] 7. Add timers and attempts: Use SetTimer for timeouts, track login attempts per player.
- [ ] 8. Prevent unauthorized actions: Block spawning, commands until logged in and character selected.
- [ ] 9. Update on disconnect: In OnPlayerDisconnect, save user/character data to database if logged in/spawned.
