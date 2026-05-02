REVIEW (2026-05-01): This is the SDK-shipped generic readme — it's NOT specific to this repo.
References to "streamable_resources/.build/OUT", `compile_streamable_resources.bat`, and the
SDK `sample_item` upload staging are SDK boilerplate, not how this repo's active mods build.
For repo-specific build/deploy instructions, see DEVELOPMENT.md and CLAUDE.md.

Recommendation: rename this file to readme_sdk_reference.txt or move it to old-backup/ to
prevent confusion with repo-level docs. Leaving it in place at root is harmless but
unintentionally suggests it's a project README.

Example mod, options_injector.mod in mod_data folder.

Basic Setup
===========
The .mod file contains the metadata needed for the mod, what packages to load and the entry point for the mod.
When the mod is done loading and the packages specified are loaded into memory the run function specified in this file will be called. To create a mod you will need one .mod file and a .package file that contains that .mod file.

Packages
========
Packages (specified by .package-files) are resource bundles to be loaded into the memory and the way the game loads resources. Packages can contain most types of resources used by the game, including but not limited to:
unit - an entity in the game world, it can have a graphical mesh, game logic, animations, physics shapes, etc
lua - lua files (gameplay code)
package - a reference to another package so that package then is able to be loaded into memory as well.
material - graphics materials, usually used for UI when loaded explicitly into a package
particles - particle system VFX
shading_environment - environments that define lighting conditions, can be switched runtime to achieve different weather, lighting, etc.
vector_field - vector fields to animate physics, particles etc
wwise_dep = wwise sound banks to be able to load sounds that aren't loaded through a unit.
font - text fonts for GUIs
mouse_cursor - mouse cursors
textures - specific textures not tied to anything else
physics_properties - physics metadata

Most assets can be used as soon as they are loaded, notable exceptions are:
lua files need to be loaded through require or dofile after being loaded through a package to actually be ran. Packages don't automatically load because they are in another package that is loaded, this just means it's not possible to load them at will and discretion.

Other Files
===========
settings.ini - specifies what package should be the first package to build the mod from
core/physx_metadata files - needed for compiling resources


To Build
========
run compile_streamable_resources.bat to compile the streamable_resources example mod.
The ready mod can be found in streamable_resources/.build/OUT

For building your own mod, one way is to make a similar .bat file but change the mod_name variable to the directory name of your mod.

To Upload to Steam Workshop
===========================
Copy the bundle files you wish to include in your workshop mod to your mod content directory (default is ugc_uploader/sample_item/content) and use the ugc_uploader/ugc_tool.exe to upload your mod to the steam workshop.

For a more detailed run down of how this works, what options you can set, how to config your steam app, see the README.txt in the /ugc_uploader folder. There is a sample config and upload.bat to give an example of how you might configure your workshop mod.


How do I download and use a workshop mod?
=========================================
Find the mod in the Workshop tab in the Warhammer: Vermintide 2 Steam Hub, click the subscribe button and Steam should start downloading the mod for you. Steam will continue to make sure all your mods are up to date using the latest version from now on.

To enable the mod itself, start the launcher, click the Mods button and the launcher will get info for all your subscribed and installed mods. From here you are able to enable/disable, change what order they are loaded as well as check information like who made the mod, get a brief description of what the mod does and when it was last updated.

When you are all done configuring your mods, all you need to do is close the mod window and start the game.

Mod development settings
========================
In user_settings.config in the %appdata%/Fatshark/Vermintide 2/ folder you will find a new table mods and you are able to add another, mod_settings,  to set up your settings for mod development/debug.

mods will contain all the mods you currently have subbed or installed as well as any info that the launcher has stored about them. This is also where load order, which are enabled, etc is stored.

for mod_settings you have the folllowing default values.
mod_settings = {
	developer_mode = false, //turning on developer mode will make the game always scan for mods even if the launcher hsan't indicated any are installed. It will also enable reloading lua code while the game is running by pressing ctrl+shift+R
	log_level = 1, //log level decides how much should be logged to the logs and to the chat regarding your mods. 
}

log levels are as follows:
	0 - no logging
	1 - only errors
	2 - errors + warnings
	3 - errors + warnings + info
	4 - errors + warnings + info + spew prints
	
The mod manager itself has some logging, but mod creators that wish to add error printing to their mods are free to use the following function:
Managers.mod:print( level, error_msg, [...])

level - level of print, allowed values: "error", "warning", "info", "spew"
error_msg - The message to be printed, works like printf in vermintide lua or c++ with %variables.
[...] - an optional amount of variable values.

eg.
Managers.mod:print("info", "Too many %s, need to destroy at least %i %s or you will take %2.1f points of damage!", "pigs", 3, "pigs", 40.6666667)

> [MOD MANAGER] [info] Too many pigs, need to destroy at least 3 pigs or you will take 40.7 points of damage!"

Mod Sanctioning
===============
All mods can be used in the Modded Realm of the game which provides no progression, achievements or loot and is separated from the Official Realm matchmaking.

Some mods can be used in the Official Realm of the game, these mods are called Sanctioned Mods. For a mod to be Sanctioned it needs to reviewed and approved by Fatshark. Mods are selected for Sanction review at regular intervals based on their approval rating in the Steam Workshop, so if you want an applied mod Sanctioned, upvote it in the workshop. Fatshark will also reserve the possibility to give priority to any individual mods they feel are exceptional and should be premiered.

To apply for Sanctioning your mod needs to:
- contain a /source directory in the uploaded data that contains all uncompiled data needed to build the mod in it's entirity.
- be uploaded to the steam workshop with the "apply_for_sanctioned_status" flag set to true in the item.cfg

All mods that are selected for Sanction review will be reviewed on a case by case basis, but this is a non-exhaustive list of guidelines that might cause you to fail review.
- Mods are opt-in, so an unmodded user joining a random game should never be exposed to Mods that affect their experience unless they have chosen to. In practice this means that it might be completely ok with a mod that turns all weapons into bananas, as long as it can only be seen by players that have this mod installed.
- Mods should not give a significant gameplay advantage over unmodded users or allow them to do something an unmodded user cannot. We don't want cheats or mods that cheapen the challenge of the game. If you have an awesome portrait frame earned by finishing a difficult challenge, you should be able to trust that people you meet will know you got it legit. This guideline will have a very large grey area and there will be many judgement calls by Fatshark of what actually constitutes a " significant gameplay advantage".
- Mods that datamine and enable in progress features will not get sanctioned. If we're working on a feature and some modder finds it and manages to activate it, you're free to try it out in the Modded Realm, but we won't sanction the mod, you'll have to wait for it to get finished before it's released.
- The mod should not cause an unwarranted extra work load for reviewers or other Fatshark work. This means but is not exclusive to that a mod that is implemented in such a way that it very likely will break when Fatshark updates the game, requiring re-review of bug fix update, that requires vast amounts of code reviewed (like big third party libraries, etc) or simply that is coded in such a way that it is very time consuming to review for other reasons (unstructured code, bad variable naming, etc).
- Mods that open up for arbitary code or content to be loaded will not be Sanctioned as they would allow loading cheats.
- Mods that infringe on any copyright will not only fail sanction review, they will also get removed from the Workshop as they break the modding EULA.
- Mods that require third party downloads will not be Sanctioned for reasons of user security. Everything needed in the mod should be uploaded to the Workshop.

This is not an exhaustive list and will likely change as new cases pop up. As it stated this will most likely rule out a lot of custom game modes, custom maps, custom art, for instance, something we're very interested in. If you have such a game mode and want some way to get it into the Official Realm, please speak to any Fatsharker on the Vermintide Modders discord (link below) and we'll talk about how to best cater to this type of content. It will likely require a more elaborate solution than the mod Sanction program, but going forward it is something we want to do.

If you are unsure if your mod will pass review or not, submit it for review! Any mods that fail review will get notification in the Steam Workshop why the mod failed review and what could be done (if anything) to resolve the infraction. When a mod gets an unresolved deny verdict, we will post the reason why on the public board of that Workshop mod so that users can see why it was denied to maximize transparency.

Your mod passed review? What now?
If your mod passed review, you still get a zip containing two folders, /source containing the source data used to build the mod and /uploaded containing the built mod with the certificates needed to run it in the Official Realm. All you need to do is to upload the contents of the /uploaded folder to the workshop and notify the reviewers that this has been done so they can flag the mod in the workshop so it gets sorted under the Approved section and is listed as Sanctioned in the mod screen in the launcher. You will receive the mod zip either through a posted link in the Workshop or over discord pm if you frequent the Modder discord.

Your mod got sanctioned and you want to update it?
If you need to update a sanctioned mod, upload a new /source folder and re-apply for Sanction review. If the fix is urgent, contact one of the Fatsharkers on the modder discord. When the update has been reviewed you will be sent a new zip. The /uploaded folder of this zip can then be uploaded to the Workshop and no further steps are necessary.

Community Resources
===================
All community created tools and content are completely unaffiliated with, and unsupported by Fatshark Studios and to be used completely are your own risk.

https://github.com/griffin02/BundleReaderBetaRelease - A bundle reader to extract and read data from the Vermintide data bundles shipped with the game.
https://discord.gg/XwST7fN - Vermintide Modders discord, a community run discord.
https://vmf-docs.verminti.de/ - Homepage of the Vermintide Modding Framework (VMF), a community-run framework of modules that provides enhanced modding capabilities.