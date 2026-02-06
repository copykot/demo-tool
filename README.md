## Documentation
Right click to open the main menu. There will be several options including:
- Spectate: In the main menu, you'll be able to select nearby players. However, in the options panel, you'll be able to select all players.
- Console kill logs: Whenever a player kills another player, it will be printed in the console. **Due to networking limitations, this feature is unreliable; sometimes it does not log kills.**
- Voice isolation: Mutes everyone besides a specific player. Useful for when you want to hear one person in a crowd of people.
- Disable UIs: Prevents certain panels from showing up.
- Quick actions: While aiming at someone (except while spectating), you'll be able to perform a select few actions on them.

Other features are:
- Thirdperson (with mouse controls)
- Customisable ESP
- Demo controls
- Being able to hear and see normally whilst dead

## Installation
Go over to Steam -> Library and find Garry's Mod. Then right click -> Manage -> Browse local files. From there open `garrysmod` and put [dem.lua](https://github.com/copykot/demo-tool/blob/main/dem.lua) inside the `lua` folder.

Once you're in a demo, type in console `sv_allowcslua 1` followed by `lua_openscript_cl dem.lua`.

## FAQ
What is a dormant player? When a player is dormant, the client doesn't receive updates regarding most of their information.

I see overlapping text that is different to the screenshots: You probably have `perp_esp` set to 1.

Can I get VAC banned for using this? No.

