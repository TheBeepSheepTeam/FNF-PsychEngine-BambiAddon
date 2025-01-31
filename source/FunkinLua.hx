package;

import openfl.display.BitmapData;
#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
#end
import animateatlas.AtlasFrameMaker;
import flixel.FlxG;
import flixel.addons.effects.FlxTrail;
import flixel.input.keyboard.FlxKey;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.system.FlxSound;
import flixel.util.FlxTimer;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.util.FlxColor;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSprite;
import openfl.Lib;
import openfl.display.BlendMode;
import openfl.filters.BitmapFilter;
import openfl.utils.Assets;
import flixel.math.FlxMath;
import flixel.util.FlxSave;
import flixel.addons.transition.FlxTransitionableState;
import flixel.system.FlxAssets.FlxShader;
#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end
#if sys
import sys.FileSystem;
import sys.io.File;
#end
import Type.ValueType;
import Controls;
import DialogueBoxPsych;
#if hscript
import hscript.Parser;
import hscript.Interp;
import hscript.Expr;
#end
#if desktop
import Discord;
#end

using StringTools;

class FunkinLua
{
	public static var Function_Stop:Dynamic = 1;
	public static var Function_Continue:Dynamic = 0;
	public static var Function_StopLua:Dynamic = 2;

	// public var errorHandler:String->Void;
	#if LUA_ALLOWED
	public var lua:State = null;
	#end
	public var camTarget:FlxCamera;
	public var scriptName:String = '';
	public var closed:Bool = false;

	#if hscript
	public static var hscript:HScript = null;
	#end

	public static var curInstance:MusicBeatState;

	public function new(script:String)
	{
		#if LUA_ALLOWED
		lua = LuaL.newstate();
		LuaL.openlibs(lua);
		Lua.init_callbacks(lua);

		// add events for libraries and also set other things up
		addCallback('trace', function(what:String)
		{
			trace(what);
		});
		LuaL.dostring(lua, "
		-- [[LUA 5.3 FUNCTIONS]]
		function table.find(table,v)
			for i,v2 in next,table do
				if v2 == v then
					return i;
				end
			end
		end

		function table.clear(t)
			while #t ~= 0 do 
				rawset(t, #t, nil); 
			end
		end

		function math.clamp(x,min,max)return math.max(min,math.min(x,max)); end

		-- INITIAL FUNCTIONS
		function table.copy(t,st,copyMeta,x)
			if (copyMeta == nil) then copyMeta = true; end
			x = x or 0;
			getfenv().things = getfenv().things or {};
			local things = getfenv().things;
			if (things[t] ~= nil) then return things[t]; end

			st = st or {};
			
			things[t] = st;
			
			for i,v in pairs(t) do
				st[i] = type(v) == \"table\" and table.copy(v,{},copyMeta,x + 1) or v;
			end
			if (x <= 0) then getfenv().things = {}; end
			
			if (copyMeta) then
				local meta = getmetatable(t);
				if (type(meta) == \"table\") then
					setmetatable(st, meta);
				end
			end
			
			return st;
		end
		--i stole this from super :grin:
		-- Simple endsWith and startsWith functions in pure lua. Using string.sub to allow things like \"gf-\" to work as expected
		function string.endsWith(str,match) return (str:sub(-#match) == match) end
		function string.startsWith(str,match) return (str:sub(0,#match) == match) end
		-- Count a table that uses more than just numbers for indices
		function table.count(tbl) 
			local count = 0
			for _,_ in pairs(tbl) do count = count + 1 end
			return count
		end
		-- Interpolates 2 values
		function math.lerp(a,b,x)
			return a + (b - a) * x
		end
		-- Converts a hex string into a table
		function hexToTbl(hex)
			hex = tostring(hex):gsub('^0x','')
			local ret = {}
			for e in hex:gmatch('[A-z0-9][A-z0-9]') do
				table.insert(ret,tonumber('0x' .. e))
			end
			return ret
		end

		_psych = {eventList = {}}; --make a psych table for psych things
		function _event(event, ...) --events for libraries
			if _psych.eventList[event] then
				for i,event in pairs(_psych.eventList[event]) do
					event(...);
				end
			end
			if _psych.eventList.onEvent then
				for i,event2 in pairs(_psych.eventList.onEvent) do
					event2(event, {...});
				end
			end
		end
		function addEvent(event, callback)
			if not _psych.eventList[event] then 
				_psych.eventList[event] = {};
			end
			table.insert(_psych.eventList[event], callback);
		end");

		try
		{
			Lua.getglobal(lua, "package");
			Lua.pushstring(lua, Paths.getLuaPackagePath());
			Lua.setfield(lua, -2, "path");
			Lua.pop(lua, 1);
			var result:Dynamic = LuaL.dofile(lua, script);
			var resultStr:String = Lua.tostring(lua, result);
			if (resultStr != null && result != 0)
			{
				trace('Error on lua script! ' + resultStr);
				lime.app.Application.current.window.alert(resultStr, 'Error on lua script!');
				lua = null;
				return;
			}
		}
		catch (e:Dynamic)
		{
			trace(e);
			return;
		}
		scriptName = script;
		initHaxeModule();

		trace('lua file loaded succesfully:' + script);

		// Lua shit
		set('Function_StopLua', Function_StopLua);
		set('Function_Stop', Function_Stop);
		set('Function_Continue', Function_Continue);
		set('luaDebugMode', true);
		set('luaDeprecatedWarnings', true);
		set('inChartEditor', false);
		set('CoolUtil.curLuaState', CoolUtil.curLuaState);

		switch (CoolUtil.curLuaState)
		{
			case 'playstate':
				// Song/Week shit
				set('curBpm', Conductor.bpm);
				set('bpm', PlayState.SONG.bpm);
				set('scrollSpeed', PlayState.SONG.speed);
				set('crochet', Conductor.crochet);
				set('stepCrochet', Conductor.stepCrochet);
				set('songLength', FlxG.sound.music.length);
				set('songName', PlayState.SONG.song);
				set('songPath', Paths.formatToSongPath(PlayState.SONG.song));
				set('startedCountdown', false);
				set('curStage', PlayState.SONG.stage);

				set('isStoryMode', PlayState.isStoryMode);
				set('difficulty', PlayState.storyDifficulty);

				var difficultyName:String = CoolUtil.difficulties[PlayState.storyDifficulty];
				set('difficultyName', difficultyName);
				set('difficultyPath', Paths.formatToSongPath(difficultyName));
				set('weekRaw', PlayState.storyWeek);
				set('week', WeekData.weeksList[PlayState.storyWeek]);
				set('seenCutscene', PlayState.seenCutscene);

				// Gameplay settings
				set('healthGainMult', PlayState.instance.healthGain);
				set('healthLossMult', PlayState.instance.healthLoss);
				set('playbackRate', PlayState.instance.playbackRate);
				set('instakillOnMiss', PlayState.instance.instakillOnMiss);
				set('botPlay', PlayState.instance.cpuControlled);
				set('practice', PlayState.instance.practiceMode);

				for (i in 0...4)
				{
					set('defaultPlayerStrumX' + i, 0);
					set('defaultPlayerStrumY' + i, 0);
					set('defaultOpponentStrumX' + i, 0);
					set('defaultOpponentStrumY' + i, 0);
				}
				set('defaultStrumPos', [for (i in 0...4) 0]);
				set('defaultStrumPosY', [for (i in 0...4) 0]);

				// Default character positions woooo
				set('defaultBoyfriendX', PlayState.instance.BF_X);
				set('defaultBoyfriendY', PlayState.instance.BF_Y);
				set('defaultOpponentX', PlayState.instance.DAD_X);
				set('defaultOpponentY', PlayState.instance.DAD_Y);
				set('defaultGirlfriendX', PlayState.instance.GF_X);
				set('defaultGirlfriendY', PlayState.instance.GF_Y);

				// Character shit
				set('boyfriendName', PlayState.SONG.player1);
				set('dadName', PlayState.SONG.player2);
				set('gfName', PlayState.SONG.gfVersion);

				set('inGameOver', false);
				set('mustHitSection', false);
				set('altAnim', false);
				set('gfSection', false);
		}

		// Camera poo
		set('cameraX', 0);
		set('cameraY', 0);

		// Screen stuff
		set('screenWidth', FlxG.width);
		set('screenHeight', FlxG.height);

		// PlayState cringe ass nae nae bullcrap
		set('curBeat', 0);
		set('curStep', 0);
		set('curDecBeat', 0);
		set('curDecStep', 0);

		set('score', 0);
		set('misses', 0);
		set('hits', 0);

		set('rating', 0);
		set('ratingName', '');
		set('ratingFC', '');
		set('version', MainMenuState.psychEngineVersion.trim());

		// Some settings, no jokes
		set('downscroll', ClientPrefs.downScroll);
		set('middlescroll', ClientPrefs.middleScroll);
		set('framerate', ClientPrefs.framerate);
		set('ghostTapping', ClientPrefs.ghostTapping);
		set('hideHud', ClientPrefs.hideHud);
		set('timeBarType', ClientPrefs.timeBarType);
		set('scoreZoom', ClientPrefs.scoreZoom);
		set('cameraZoomOnBeat', ClientPrefs.camZooms);
		set('flashingLights', ClientPrefs.flashing);
		set('noteOffset', ClientPrefs.noteOffset);
		set('healthBarAlpha', ClientPrefs.healthBarAlpha);
		set('noResetButton', ClientPrefs.noReset);
		set('lowQuality', ClientPrefs.lowQuality);
		set('shadersEnabled', ClientPrefs.shaders);
		set('scriptName', scriptName);
		set('currentModDirectory', Paths.currentModDirectory);

		#if windows
		set('buildTarget', 'windows');
		#elseif linux
		set('buildTarget', 'linux');
		#elseif mac
		set('buildTarget', 'mac');
		#elseif html5
		set('buildTarget', 'browser');
		#elseif android
		set('buildTarget', 'android');
		#else
		set('buildTarget', 'unknown');
		#end

		set('curState', CoolUtil.curLuaState);

		// custom substate
		addCallback("openCustomSubstate", function(name:String, pauseGame:Bool = false)
		{
			if (pauseGame)
			{
				FunkinLua.curInstance.persistentUpdate = false;
				FunkinLua.curInstance.persistentDraw = true;
				if (CoolUtil.curLuaState == 'playstate')
					PlayState.instance.paused = true;
				if (FlxG.sound.music != null)
				{
					FlxG.sound.music.pause();
					PlayState.instance.vocals.pause();
				}
			}
			FunkinLua.curInstance.openSubState(new CustomSubstate(name));
		});

		addCallback("closeCustomSubstate", function()
		{
			if (CustomSubstate.instance != null)
			{
				FunkinLua.curInstance.closeSubState();
				CustomSubstate.instance = null;
				return true;
			}
			return false;
		});

		// shader shit
		addCallback("initLuaShader", function(name:String, glslVersion:Int = 120)
		{
			if (!ClientPrefs.shaders)
				return false;

			#if (!flash && MODS_ALLOWED && sys)
			return initLuaShader(name, glslVersion);
			#else
			luaTrace("initLuaShader: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
			return false;
		});

		addCallback("setSpriteShader", function(obj:String, shader:String)
		{
			if (!ClientPrefs.shaders)
				return false;

			#if (!flash && MODS_ALLOWED && sys)
			if (!ShaderHandler.runtimeShaders.exists(shader) && !initLuaShader(shader))
			{
				luaTrace('setSpriteShader: Shader $shader is missing!', false, false, FlxColor.RED);
				return false;
			}

			var killMe:Array<String> = obj.split('.');
			var leObj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				var arr:Array<String> = ShaderHandler.runtimeShaders.get(shader);
				leObj.shader = new FlxRuntimeShader(arr[0], arr[1]);
				return true;
			}
			#else
			luaTrace("setSpriteShader: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
			return false;
		});
		addCallback("removeSpriteShader", function(obj:String)
		{
			var killMe:Array<String> = obj.split('.');
			var leObj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				leObj.shader = null;
				return true;
			}
			return false;
		});

		addCallback("getShaderBool", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return shader.getBool(prop);
			#else
			luaTrace("getShaderBool: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
			#end
		});
		addCallback("getShaderBoolArray", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return shader.getBoolArray(prop);
			#else
			luaTrace("getShaderBoolArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
			#end
		});
		addCallback("getShaderInt", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return shader.getInt(prop);
			#else
			luaTrace("getShaderInt: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
			#end
		});
		addCallback("getShaderIntArray", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return shader.getIntArray(prop);
			#else
			luaTrace("getShaderIntArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
			#end
		});
		addCallback("getShaderFloat", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return shader.getFloat(prop);
			#else
			luaTrace("getShaderFloat: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
			#end
		});
		addCallback("getShaderFloatArray", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return shader.getFloatArray(prop);
			#else
			luaTrace("getShaderFloatArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
			#end
		});

		addCallback("setShaderBool", function(obj:String, prop:String, value:Bool)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setBool(prop, value);
			#else
			luaTrace("setShaderBool: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		addCallback("setShaderBoolArray", function(obj:String, prop:String, values:Dynamic)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setBoolArray(prop, values);
			#else
			luaTrace("setShaderBoolArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		addCallback("setShaderInt", function(obj:String, prop:String, value:Int)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setInt(prop, value);
			#else
			luaTrace("setShaderInt: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		addCallback("setShaderIntArray", function(obj:String, prop:String, values:Dynamic)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setIntArray(prop, values);
			#else
			luaTrace("setShaderIntArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		addCallback("setShaderFloat", function(obj:String, prop:String, value:Float)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setFloat(prop, value);
			#else
			luaTrace("setShaderFloat: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		addCallback("setShaderFloatArray", function(obj:String, prop:String, values:Dynamic)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setFloatArray(prop, values);
			#else
			luaTrace("setShaderFloatArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});

		addCallback("setShaderSampler2D", function(obj:String, prop:String, bitmapdataPath:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			// trace('bitmapdatapath: $bitmapdataPath');
			var value = Paths.image(bitmapdataPath);
			if (value != null && value.bitmap != null)
			{
				// trace('Found bitmapdata. Width: ${value.bitmap.width} Height: ${value.bitmap.height}');
				shader.setSampler2D(prop, value.bitmap);
			}
			#else
			luaTrace("setShaderSampler2D: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});

		//
		addCallback("getRunningScripts", function()
		{
			var runningScripts:Array<String> = [];
			for (idx in 0...FunkinLua.curInstance.luaArray.length)
				runningScripts.push(FunkinLua.curInstance.luaArray[idx].scriptName);

			return runningScripts;
		});

		addCallback("callOnLuas", function(?funcName:String, ?args:Array<Dynamic>, ignoreStops = false, ignoreSelf = true, ?exclusions:Array<String>)
		{
			if (funcName == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #1 to 'callOnLuas' (string expected, got nil)");
				#end
				return;
			}
			if (args == null)
				args = [];

			if (exclusions == null)
				exclusions = [];

			Lua.getglobal(lua, 'scriptName');
			var daScriptName = Lua.tostring(lua, -1);
			Lua.pop(lua, 1);
			if (ignoreSelf && !exclusions.contains(daScriptName))
				exclusions.push(daScriptName);
			FunkinLua.curInstance.callOnLuas(funcName, args, ignoreStops, exclusions);
		});

		addCallback("callScript", function(?luaFile:String, ?funcName:String, ?args:Array<Dynamic>)
		{
			if (luaFile == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #1 to 'callScript' (string expected, got nil)");
				#end
				return;
			}
			if (funcName == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #2 to 'callScript' (string expected, got nil)");
				#end
				return;
			}
			if (args == null)
			{
				args = [];
			}
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end
			if (doPush)
			{
				for (luaInstance in FunkinLua.curInstance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
					{
						luaInstance.call(funcName, args);

						return;
					}
				}
			}
			Lua.pushnil(lua);
		});

		addCallback("getGlobalFromScript", function(?luaFile:String, ?global:String)
		{ // returns the global from a script
			if (luaFile == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #1 to 'getGlobalFromScript' (string expected, got nil)");
				#end
				return;
			}
			if (global == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #2 to 'getGlobalFromScript' (string expected, got nil)");
				#end
				return;
			}
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end
			if (doPush)
			{
				for (luaInstance in FunkinLua.curInstance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
					{
						Lua.getglobal(luaInstance.lua, global);
						if (Lua.isnumber(luaInstance.lua, -1))
						{
							Lua.pushnumber(lua, Lua.tonumber(luaInstance.lua, -1));
						}
						else if (Lua.isstring(luaInstance.lua, -1))
						{
							Lua.pushstring(lua, Lua.tostring(luaInstance.lua, -1));
						}
						else if (Lua.isboolean(luaInstance.lua, -1))
						{
							Lua.pushboolean(lua, Lua.toboolean(luaInstance.lua, -1));
						}
						else
						{
							Lua.pushnil(lua);
						}
						// TODO: table

						Lua.pop(luaInstance.lua, 1); // remove the global

						return;
					}
				}
			}
			Lua.pushnil(lua);
		});
		addCallback("setGlobalFromScript", function(luaFile:String, global:String, val:Dynamic)
		{ // returns the global from a script
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end
			if (doPush)
			{
				for (luaInstance in FunkinLua.curInstance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
					{
						luaInstance.set(global, val);
					}
				}
			}
			Lua.pushnil(lua);
		});
		/*addCallback("getGlobals", function(luaFile:String){ // returns a copy of the specified file's globals
			var cervix = luaFile + ".lua";
			if(luaFile.endsWith(".lua"))cervix=luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if(FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if(FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else {
				cervix = Paths.getPreloadPath(cervix);
				if(FileSystem.exists(cervix)) {
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if(Assets.exists(cervix)) {
				doPush = true;
			}
			#end
			if(doPush)
			{
				for (luaInstance in FunkinLua.curInstance.luaArray)
				{
					if(luaInstance.scriptName == cervix)
					{
						Lua.newtable(lua);
						var tableIdx = Lua.gettop(lua);

						Lua.pushvalue(luaInstance.lua, Lua.LUA_GLOBALSINDEX);
						Lua.pushnil(luaInstance.lua);
						while(Lua.next(luaInstance.lua, -2) != 0) {
							// key = -2
							// value = -1

							var pop:Int = 0;

							// Manual conversion
							// first we convert the key
							if(Lua.isnumber(luaInstance.lua,-2)){
								Lua.pushnumber(lua, Lua.tonumber(luaInstance.lua, -2));
								pop++;
							}else if(Lua.isstring(luaInstance.lua,-2)){
								Lua.pushstring(lua, Lua.tostring(luaInstance.lua, -2));
								pop++;
							}else if(Lua.isboolean(luaInstance.lua,-2)){
								Lua.pushboolean(lua, Lua.toboolean(luaInstance.lua, -2));
								pop++;
							}
							// TODO: table


							// then the value
							if(Lua.isnumber(luaInstance.lua,-1)){
								Lua.pushnumber(lua, Lua.tonumber(luaInstance.lua, -1));
								pop++;
							}else if(Lua.isstring(luaInstance.lua,-1)){
								Lua.pushstring(lua, Lua.tostring(luaInstance.lua, -1));
								pop++;
							}else if(Lua.isboolean(luaInstance.lua,-1)){
								Lua.pushboolean(lua, Lua.toboolean(luaInstance.lua, -1));
								pop++;
							}
							// TODO: table

							if(pop==2)Lua.rawset(lua, tableIdx); // then set it
							Lua.pop(luaInstance.lua, 1); // for the loop
						}
						Lua.pop(luaInstance.lua,1); // end the loop entirely
						Lua.pushvalue(lua, tableIdx); // push the table onto the stack so it gets returned

						return;
					}

				}
			}
			Lua.pushnil(lua);
		});*/

		addCallback("isRunning", function(luaFile:String)
		{
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end

			if (doPush)
			{
				for (luaInstance in FunkinLua.curInstance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
						return true;
				}
			}
			return false;
		});

		addCallback("addLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false)
		{ // would be dope asf.
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end

			if (doPush)
			{
				if (!ignoreAlreadyRunning)
				{
					for (luaInstance in FunkinLua.curInstance.luaArray)
					{
						if (luaInstance.scriptName == cervix)
						{
							luaTrace('addLuaScript: The script "' + cervix + '" is already running!');
							return;
						}
					}
				}
				FunkinLua.curInstance.addNewLua(cervix);
				return;
			}
			luaTrace("addLuaScript: Script doesn't exist!", false, false, FlxColor.RED);
		});
		addCallback("removeLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false)
		{ // would be dope asf.
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end

			if (doPush)
			{
				if (!ignoreAlreadyRunning)
				{
					for (luaInstance in FunkinLua.curInstance.luaArray)
					{
						if (luaInstance.scriptName == cervix)
						{
							// luaTrace('The script "' + cervix + '" is already running!');

							FunkinLua.curInstance.luaArray.remove(luaInstance);
							return;
						}
					}
				}
				return;
			}
			luaTrace("removeLuaScript: Script doesn't exist!", false, false, FlxColor.RED);
		});

		addCallback("runHaxeCode", function(codeToRun:String, ?carryOverVars:Dynamic)
		{
			var retVal:Dynamic = null;
			var addedCode:String = '';

			#if hscript
			initHaxeModule();
			try
			{
				if (carryOverVars != null)
				{
					hscript.set('_carryOverVars', carryOverVars);
					addedCode = [
						for (field in Reflect.fields(carryOverVars))
							"var " + field + " = _carryOverVars." + field + ";"
					].join('\n');
				}
				retVal = hscript.execute(addedCode + codeToRun);
				hscript.set('_carryOverVars', null);
			}
			catch (e:Dynamic)
			{
				luaTrace(scriptName + ":" + lastCalledFunction + " - " + e, false, false, FlxColor.RED);
			}
			#else
			luaTrace("runHaxeCode: HScript isn't supported on this platform!", false, false, FlxColor.RED);
			#end

			if (retVal == null)
				Lua.pushnil(lua);
			return retVal;
		});

		addCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '')
		{
			#if hscript
			initHaxeModule();
			try
			{
				var str:String = '';
				if (libPackage.length > 0)
					str = libPackage + '.';

				hscript.set(libName, Type.resolveClass(str + libName));
			}
			catch (e:Dynamic)
			{
				luaTrace(scriptName + ":" + lastCalledFunction + " - " + e, false, false, FlxColor.RED);
			}
			#end
		});

		addCallback("loadGraphic", function(variable:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0)
		{
			var killMe:Array<String> = variable.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			var animated = gridX != 0 || gridY != 0;

			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null && image != null && image.length > 0)
			{
				spr.loadGraphic(Paths.image(image), animated, gridX, gridY);
			}
		});
		addCallback("loadFrames", function(variable:String, image:String, spriteType:String = "sparrow")
		{
			var killMe:Array<String> = variable.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null && image != null && image.length > 0)
			{
				loadFrames(spr, image, spriteType);
			}
		});

		addCallback("getProperty", function(variable:String)
		{
			var result:Dynamic = null;
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
				result = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			else
				result = getVarInArray(getInstance(), variable);

			if (result == null)
				Lua.pushnil(lua);
			return result;
		});
		addCallback("setProperty", function(variable:String, value:Dynamic)
		{
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
			{
				setVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1], value);
				return true;
			}
			setVarInArray(getInstance(), variable, value);
			return true;
		});
		addCallback("getPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic)
		{
			var shitMyPants:Array<String> = obj.split('.');
			var realObject:Dynamic = Reflect.getProperty(getInstance(), obj);
			if (shitMyPants.length > 1)
				realObject = getPropertyLoopThingWhatever(shitMyPants, true, false);

			if (Std.isOfType(realObject, FlxTypedGroup))
			{
				var result:Dynamic = getGroupStuff(realObject.members[index], variable);
				if (result == null)
					Lua.pushnil(lua);
				return result;
			}

			var leArray:Dynamic = realObject[index];
			if (leArray != null)
			{
				var result:Dynamic = null;
				if (Type.typeof(variable) == ValueType.TInt)
					result = leArray[variable];
				else
					result = getGroupStuff(leArray, variable);

				if (result == null)
					Lua.pushnil(lua);
				return result;
			}
			luaTrace("getPropertyFromGroup: Object #" + index + " from group: " + obj + " doesn't exist!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
		});
		addCallback("setPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic, value:Dynamic)
		{
			var shitMyPants:Array<String> = obj.split('.');
			var realObject:Dynamic = Reflect.getProperty(getInstance(), obj);
			if (shitMyPants.length > 1)
				realObject = getPropertyLoopThingWhatever(shitMyPants, true, false);

			if (Std.isOfType(realObject, FlxTypedGroup))
			{
				setGroupStuff(realObject.members[index], variable, value);
				return;
			}

			var leArray:Dynamic = realObject[index];
			if (leArray != null)
			{
				if (Type.typeof(variable) == ValueType.TInt)
				{
					leArray[variable] = value;
					return;
				}
				setGroupStuff(leArray, variable, value);
			}
		});
		addCallback("getPropertyFromClass", function(classVar:String, variable:String)
		{
			@:privateAccess
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
			{
				var coverMeInPiss:Dynamic = getVarInArray(Type.resolveClass(classVar), killMe[0]);
				for (i in 1...killMe.length - 1)
				{
					coverMeInPiss = getVarInArray(coverMeInPiss, killMe[i]);
				}
				return getVarInArray(coverMeInPiss, killMe[killMe.length - 1]);
			}
			return getVarInArray(Type.resolveClass(classVar), variable);
		});
		addCallback("setPropertyFromClass", function(classVar:String, variable:String, value:Dynamic)
		{
			@:privateAccess
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
			{
				var coverMeInPiss:Dynamic = getVarInArray(Type.resolveClass(classVar), killMe[0]);
				for (i in 1...killMe.length - 1)
				{
					coverMeInPiss = getVarInArray(coverMeInPiss, killMe[i]);
				}
				setVarInArray(coverMeInPiss, killMe[killMe.length - 1], value);
				return true;
			}
			setVarInArray(Type.resolveClass(classVar), variable, value);
			return true;
		});

		// shitass stuff for epic coders like me B)  *image of obama giving himself a medal*
		addCallback("getObjectOrder", function(obj:String)
		{
			var killMe:Array<String> = obj.split('.');
			var leObj:FlxBasic = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				return getInstance().members.indexOf(leObj);
			}
			luaTrace("getObjectOrder: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return -1;
		});
		addCallback("setObjectOrder", function(obj:String, position:Int)
		{
			var killMe:Array<String> = obj.split('.');
			var leObj:FlxBasic = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				getInstance().remove(leObj, true);
				getInstance().insert(position, leObj);
				return;
			}
			luaTrace("setObjectOrder: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
		});

		// gay ass tweens
		addCallback('doTween', function(tag:String, obj:String, vars:Dynamic, duration:Float, options:Dynamic)
		{
			trace('hello!');
			var ok:Dynamic = tweenShit(tag, obj);
			FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(ok, vars, duration, (options != null) ? {
				startDelay: Reflect.hasField(options, 'startDelay') ? options.startDelay : null,
				ease: Reflect.hasField(options, 'ease') ? getFlxEaseByString(options.ease) : null,
				onStart: function(twn:FlxTween)
				{
					call('_tweenStart', [tag]);
				},
				onComplete: function(twn:FlxTween)
				{
					call('_tweenComplete', [tag]);
				},
				onUpdate: function(twn:FlxTween)
				{
					call('_tweenUpdate', [tag, twn.percent]);
				}
			} : null));
		});
		// add callback functionality
		LuaL.dostring(lua, "
		local _dt = doTween; --store the haxe function
		_psych.tweens = {}; --make empty table
		function doTween(tag, obj, vars, duration, options) --overwrite the function
			if options then --store the options and callbacks as an index
				_psych.tweens[tag] = options;
			end
			local copycat = table.copy(options); --copy the options table to remove functions
			copycat.onStart = nil;
			copycat.onComplete = nil;
			copycat.onUpdate = nil;
			_dt(tag, obj, vars, duration, copycat); --do tween
		end
		--self explanatory
		function _tweenStart(tag)
			if _psych.eventList.onTweenStart then
				for i,event in pairs(_psych.eventList.onTweenStart) do
					event(tag);
				end
			end
			if _psych.tweens[tag] and _psych.tweens[tag].onStart then
				_psych.tweens[tag].onStart();
			end
			onTweenStart(tag)
		end
		function _tweenComplete(tag)
			if _psych.eventList.onTweenCompleted then
				for i,event in pairs(_psych.eventList.onTweenCompleted) do
					event(tag);
				end
			end
			if _psych.tweens[tag] and _psych.tweens[tag].onComplete then
				_psych.tweens[tag].onComplete();
				_psych.tweens[tag] = nil;
			end
		end
		function _tweenUpdate(tag, percent)
			if _psych.eventList.onTweenUpdate then
				for i,event in pairs(_psych.eventList.onTweenUpdate) do
					event(tag, percent);
				end
			end
			if _psych.tweens[tag] and _psych.tweens[tag].onUpdate then
				_psych.tweens[tag].onUpdate(percent);
			end
			onTweenUpdated(tag, percent);
		end
		");
		addCallback("doTweenX", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(penisExam, {x: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
						FunkinLua.curInstance.modchartTweens.remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenX: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		addCallback("doTweenY", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(penisExam, {y: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
						FunkinLua.curInstance.modchartTweens.remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenY: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		addCallback("doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(penisExam, {angle: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
						FunkinLua.curInstance.modchartTweens.remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenAngle: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		addCallback("doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(penisExam, {alpha: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
						FunkinLua.curInstance.modchartTweens.remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenAlpha: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		addCallback("doTweenZoom", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(penisExam, {zoom: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
						FunkinLua.curInstance.modchartTweens.remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenZoom: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		addCallback("doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				var color:Int = Std.parseInt(targetColor);
				if (!targetColor.startsWith('0x'))
					color = Std.parseInt('0xff' + targetColor);

				var curColor:FlxColor = penisExam.color;
				curColor.alphaFloat = penisExam.alpha;
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.color(penisExam, duration, curColor, color, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.modchartTweens.remove(tag);
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
					}
				}));
			}
			else
			{
				luaTrace('doTweenColor: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});

		// Tween shit, but for strums
		addCallback("mouseClicked", function(button:String)
		{
			var boobs = FlxG.mouse.justPressed;
			switch (button)
			{
				case 'middle':
					boobs = FlxG.mouse.justPressedMiddle;
				case 'right':
					boobs = FlxG.mouse.justPressedRight;
			}

			return boobs;
		});
		addCallback("mousePressed", function(button:String)
		{
			var boobs = FlxG.mouse.pressed;
			switch (button)
			{
				case 'middle':
					boobs = FlxG.mouse.pressedMiddle;
				case 'right':
					boobs = FlxG.mouse.pressedRight;
			}
			return boobs;
		});
		addCallback("mouseReleased", function(button:String)
		{
			var boobs = FlxG.mouse.justReleased;
			switch (button)
			{
				case 'middle':
					boobs = FlxG.mouse.justReleasedMiddle;
				case 'right':
					boobs = FlxG.mouse.justReleasedRight;
			}
			return boobs;
		});
		addCallback("noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(testicle, {angle: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
						FunkinLua.curInstance.modchartTweens.remove(tag);
					}
				}));
			}
		});
		addCallback("noteTweenAlpha", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(testicle, {alpha: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
						FunkinLua.curInstance.modchartTweens.remove(tag);
					}
				}));
			}
		});

		addCallback("cancelTween", function(tag:String)
		{
			cancelTween(tag);
		});

		addCallback("timer", function(tag:String, time:Float = 1, loops:Int = 1)
		{
			cancelTimer(tag);
			FunkinLua.curInstance.modchartTimers.set(tag, new FlxTimer().start(time, function(tmr:FlxTimer)
			{
				if (tmr.finished)
				{
					FunkinLua.curInstance.modchartTimers.remove(tag);
				}
				FunkinLua.curInstance.callOnLuas('onTimerCompleted', [tag, tmr.loops, tmr.loopsLeft]);
				call('_timerComplete', [tag, tmr.loops, tmr.loopsLeft]);
			}, loops));
		});
		LuaL.dostring(lua, "
		_psych.timers = {}; --make blank table
		local _rt = timer; --store normal version
		function timer(tag, time, callback, loops) --replace callback
			_psych.timers[tag] = callback; --add the callback as an index in the timer table
			_rt(tag, time or 1, loops or 1); --run the timer from the stored nromal version
			trace ('idiot, '..tag..', '..tostring(callback == _psych.timers[tag]))
			trace 'starting timer'
		end
		function _timerComplete(tag, loops, loopsLeft) --seperate from onTimerCompleted, shouldn't be messed with!
			trace ('idiot, '..tag..', '..tostring(_psych.timers[tag] == nil))
			if _psych.timers[tag] then --check if the tag exists as an index
				trace 'running function'
				_psych.timers[tag](loops, loopsLeft); --run the timer
				_psych.timers[tag] = nil; --delete them!
			end
		end");
		addCallback("cancelTimer", function(tag:String)
		{
			cancelTimer(tag);
		});

		/*addCallback("getPropertyAdvanced", function(varsStr:String) {
				var variables:Array<String> = varsStr.replace(' ', '').split(',');
				var leClass:Class<Dynamic> = Type.resolveClass(variables[0]);
				if(variables.length > 2) {
					var curProp:Dynamic = Reflect.getProperty(leClass, variables[1]);
					if(variables.length > 3) {
						for (i in 2...variables.length-1) {
							curProp = Reflect.getProperty(curProp, variables[i]);
						}
					}
					return Reflect.getProperty(curProp, variables[variables.length-1]);
				} else if(variables.length == 2) {
					return Reflect.getProperty(leClass, variables[variables.length-1]);
				}
				return null;
			});
			addCallback("setPropertyAdvanced", function(varsStr:String, value:Dynamic) {
				var variables:Array<String> = varsStr.replace(' ', '').split(',');
				var leClass:Class<Dynamic> = Type.resolveClass(variables[0]);
				if(variables.length > 2) {
					var curProp:Dynamic = Reflect.getProperty(leClass, variables[1]);
					if(variables.length > 3) {
						for (i in 2...variables.length-1) {
							curProp = Reflect.getProperty(curProp, variables[i]);
						}
					}
					return Reflect.setProperty(curProp, variables[variables.length-1], value);
				} else if(variables.length == 2) {
					return Reflect.setProperty(leClass, variables[variables.length-1], value);
				}
		});*/


		addCallback("getColorFromHex", function(color:String)
		{
			if (!color.startsWith('0x'))
				color = '0xff' + color;
			return Std.parseInt(color);
		});

		addCallback("keyboardJustPressed", function(name:String)
		{
			return Reflect.getProperty(FlxG.keys.justPressed, name);
		});
		addCallback("keyboardPressed", function(name:String)
		{
			return Reflect.getProperty(FlxG.keys.pressed, name);
		});
		addCallback("keyboardReleased", function(name:String)
		{
			return Reflect.getProperty(FlxG.keys.justReleased, name);
		});

		addCallback("anyGamepadJustPressed", function(name:String)
		{
			return FlxG.gamepads.anyJustPressed(name);
		});
		addCallback("anyGamepadPressed", function(name:String)
		{
			return FlxG.gamepads.anyPressed(name);
		});
		addCallback("anyGamepadReleased", function(name:String)
		{
			return FlxG.gamepads.anyJustReleased(name);
		});

		addCallback("gamepadAnalogX", function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return 0.0;
			}
			return controller.getXAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		addCallback("gamepadAnalogY", function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return 0.0;
			}
			return controller.getYAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		addCallback("gamepadJustPressed", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return false;
			}
			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		addCallback("gamepadPressed", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return false;
			}
			return Reflect.getProperty(controller.pressed, name) == true;
		});
		addCallback("gamepadReleased", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return false;
			}
			return Reflect.getProperty(controller.justReleased, name) == true;
		});
		addCallback("precacheImage", function(name:String)
		{
			Paths.returnGraphic(name);
		});
		addCallback("precacheSound", function(name:String)
		{
			CoolUtil.precacheSound(name);
		});
		addCallback("precacheMusic", function(name:String)
		{
			CoolUtil.precacheMusic(name);
		});
		addCallback("getMouseX", function(camera:String)
		{
			var cam:FlxCamera = cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).x;
		});
		addCallback("getMouseY", function(camera:String)
		{
			var cam:FlxCamera = cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).y;
		});

		addCallback("getMidpointX", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getMidpoint().x;

			return 0;
		});
		addCallback("getMidpointY", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getMidpoint().y;

			return 0;
		});
		addCallback("getGraphicMidpointX", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getGraphicMidpoint().x;

			return 0;
		});
		addCallback("getGraphicMidpointY", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getGraphicMidpoint().y;

			return 0;
		});
		addCallback("getScreenPositionX", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getScreenPosition().x;

			return 0;
		});
		addCallback("getScreenPositionY", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getScreenPosition().y;

			return 0;
		});

		addCallback("makeLuaSprite", function(tag:String, image:String, x:Float, y:Float)
		{
			tag = tag.replace('.', '');
			resetSpriteTag(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);
			if (image != null && image.length > 0)
			{
				leSprite.loadGraphic(Paths.image(image));
			}
			leSprite.antialiasing = ClientPrefs.globalAntialiasing;
			FunkinLua.curInstance.modchartSprites.set(tag, leSprite);
			leSprite.active = true;
		});
		addCallback("makeAnimatedLuaSprite", function(tag:String, image:String, x:Float, y:Float, ?spriteType:String = "sparrow")
		{
			tag = tag.replace('.', '');
			resetSpriteTag(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);

			loadFrames(leSprite, image, spriteType);
			leSprite.antialiasing = ClientPrefs.globalAntialiasing;
			FunkinLua.curInstance.modchartSprites.set(tag, leSprite);
		});

		addCallback("makeGraphic", function(obj:String, width:Int, height:Int, color:String)
		{
			var colorNum:Int = Std.parseInt(color);
			if (!color.startsWith('0x'))
				colorNum = Std.parseInt('0xff' + color);

			var spr:FlxSprite = FunkinLua.curInstance.getLuaObject(obj, false);
			if (spr != null)
			{
				FunkinLua.curInstance.getLuaObject(obj, false).makeGraphic(width, height, colorNum);
				return;
			}

			var object:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (object != null)
			{
				object.makeGraphic(width, height, colorNum);
			}
		});
		addCallback("addAnimationByPrefix", function(obj:String, name:String, prefix:String, framerate:Int = 24, loop:Bool = true)
		{
			if (FunkinLua.curInstance.getLuaObject(obj, false) != null)
			{
				var cock:FlxSprite = FunkinLua.curInstance.getLuaObject(obj, false);
				cock.animation.addByPrefix(name, prefix, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
				return;
			}

			var cock:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (cock != null)
			{
				cock.animation.addByPrefix(name, prefix, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
			}
		});

		addCallback("addAnimation", function(obj:String, name:String, frames:Array<Int>, framerate:Int = 24, loop:Bool = true)
		{
			if (FunkinLua.curInstance.getLuaObject(obj, false) != null)
			{
				var cock:FlxSprite = FunkinLua.curInstance.getLuaObject(obj, false);
				cock.animation.add(name, frames, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
				return;
			}

			var cock:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (cock != null)
			{
				cock.animation.add(name, frames, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
			}
		});

		addCallback("addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:String, framerate:Int = 24, loop:Bool = false)
		{
			return addAnimByIndices(obj, name, prefix, indices, framerate, loop);
		});

		addCallback("playAnim", function(obj:String, name:String, forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0)
		{
			if (FunkinLua.curInstance.getLuaObject(obj, false) != null)
			{
				var luaObj:FlxSprite = FunkinLua.curInstance.getLuaObject(obj, false);
				if (luaObj.animation.getByName(name) != null)
				{
					luaObj.animation.play(name, forced, reverse, startFrame);
					if (Std.isOfType(luaObj, ModchartSprite))
					{
						// convert luaObj to ModchartSprite
						var obj:Dynamic = luaObj;
						var luaObj:ModchartSprite = obj;

						var daOffset = luaObj.animOffsets.get(name);
						if (luaObj.animOffsets.exists(name))
						{
							luaObj.offset.set(daOffset[0], daOffset[1]);
						}
					}
				}
				return true;
			}

			var spr:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (spr != null)
			{
				if (spr.animation.getByName(name) != null)
				{
					if (Std.isOfType(spr, Character))
					{
						// convert spr to Character
						var obj:Dynamic = spr;
						var spr:Character = obj;
						spr.playAnim(name, forced, reverse, startFrame);
					}
					else
						spr.animation.play(name, forced, reverse, startFrame);
				}
				return true;
			}
			return false;
		});
		addCallback("addOffset", function(obj:String, anim:String, x:Float, y:Float)
		{
			if (FunkinLua.curInstance.modchartSprites.exists(obj))
			{
				FunkinLua.curInstance.modchartSprites.get(obj).animOffsets.set(anim, [x, y]);
				return true;
			}

			var char:Character = Reflect.getProperty(getInstance(), obj);
			if (char != null)
			{
				char.addOffset(anim, x, y);
				return true;
			}
			return false;
		});

		addCallback("setScrollFactor", function(obj:String, scrollX:Float, scrollY:Float)
		{
			if (FunkinLua.curInstance.getLuaObject(obj, false) != null)
			{
				FunkinLua.curInstance.getLuaObject(obj, false).scrollFactor.set(scrollX, scrollY);
				return;
			}

			var object:FlxObject = Reflect.getProperty(getInstance(), obj);
			if (object != null)
			{
				object.scrollFactor.set(scrollX, scrollY);
			}
		});
		addCallback("addLuaSprite", function(tag:String, front:Bool = false)
		{
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var shit:ModchartSprite = FunkinLua.curInstance.modchartSprites.get(tag);
				if (!shit.wasAdded)
				{
					if (front || CoolUtil.curLuaState != 'playstate')
					{
						getInstance().add(shit);
					}
					else
					{
						if (PlayState.instance.isDead)
						{
							GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), shit);
						}
						else
						{
							var position:Int = FunkinLua.curInstance.members.indexOf(PlayState.instance.gfGroup);
							if (FunkinLua.curInstance.members.indexOf(PlayState.instance.boyfriendGroup) < position)
							{
								position = FunkinLua.curInstance.members.indexOf(PlayState.instance.boyfriendGroup);
							}
							else if (FunkinLua.curInstance.members.indexOf(PlayState.instance.dadGroup) < position)
							{
								position = FunkinLua.curInstance.members.indexOf(PlayState.instance.dadGroup);
							}
							FunkinLua.curInstance.insert(position, shit);
						}
					}
					shit.wasAdded = true;
					// trace('added a thing: ' + tag);
				}
			}
			if (FunkinLua.curInstance.variables.exists(tag) && Std.isOfType(FunkinLua.curInstance.variables.get(tag), MenuBG))
			{
				var meThing:MenuBG = FunkinLua.curInstance.variables.get(tag);
				FunkinLua.curInstance.add(meThing);
			}
		});
		addCallback('insertLuaSprite', function(tag:String, position:Int)
		{
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var shit:ModchartSprite = FunkinLua.curInstance.modchartSprites.get(tag);
				FunkinLua.curInstance.insert(position, shit);
			}
		});
		addCallback("setGraphicSize", function(obj:String, x:Int, y:Int = 0, updateHitbox:Bool = true)
		{
			if (FunkinLua.curInstance.getLuaObject(obj) != null)
			{
				var shit:FlxSprite = FunkinLua.curInstance.getLuaObject(obj);
				shit.setGraphicSize(x, y);
				if (updateHitbox)
					shit.updateHitbox();
				return;
			}

			var killMe:Array<String> = obj.split('.');
			var poop:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				poop = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (poop != null)
			{
				poop.setGraphicSize(x, y);
				if (updateHitbox)
					poop.updateHitbox();
				return;
			}
			luaTrace('setGraphicSize: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		addCallback("scaleObject", function(obj:String, x:Float, y:Float, updateHitbox:Bool = true)
		{
			if (FunkinLua.curInstance.getLuaObject(obj) != null)
			{
				var shit:FlxSprite = FunkinLua.curInstance.getLuaObject(obj);
				shit.scale.set(x, y);
				if (updateHitbox)
					shit.updateHitbox();
				return;
			}

			var killMe:Array<String> = obj.split('.');
			var poop:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				poop = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (poop != null)
			{
				poop.scale.set(x, y);
				if (updateHitbox)
					poop.updateHitbox();
				return;
			}
			luaTrace('scaleObject: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		addCallback("updateHitbox", function(obj:String)
		{
			if (FunkinLua.curInstance.getLuaObject(obj) != null)
			{
				var shit:FlxSprite = FunkinLua.curInstance.getLuaObject(obj);
				shit.updateHitbox();
				return;
			}

			var poop:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (poop != null)
			{
				poop.updateHitbox();
				return;
			}
			luaTrace('updateHitbox: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		addCallback("updateHitboxFromGroup", function(group:String, index:Int)
		{
			if (Std.isOfType(Reflect.getProperty(getInstance(), group), FlxTypedGroup))
			{
				Reflect.getProperty(getInstance(), group).members[index].updateHitbox();
				return;
			}
			Reflect.getProperty(getInstance(), group)[index].updateHitbox();
		});

		addCallback("removeLuaSprite", function(tag:String, destroy:Bool = true)
		{
			if (!FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				return;
			}

			var pee:ModchartSprite = FunkinLua.curInstance.modchartSprites.get(tag);
			if (destroy)
			{
				pee.kill();
			}

			if (pee.wasAdded)
			{
				getInstance().remove(pee, true);
				pee.wasAdded = false;
			}

			if (destroy)
			{
				pee.destroy();
				FunkinLua.curInstance.modchartSprites.remove(tag);
			}
		});

		addCallback("luaSpriteExists", function(tag:String)
		{
			return FunkinLua.curInstance.modchartSprites.exists(tag);
		});
		addCallback("luaTextExists", function(tag:String)
		{
			return FunkinLua.curInstance.modchartTexts.exists(tag);
		});
		addCallback("luaSoundExists", function(tag:String)
		{
			return FunkinLua.curInstance.modchartSounds.exists(tag);
		});
		addCallback("setBlendMode", function(obj:String, blend:String = '')
		{
			var real = FunkinLua.curInstance.getLuaObject(obj);
			if (real != null)
			{
				real.blend = blendModeFromString(blend);
				return true;
			}

			var killMe:Array<String> = obj.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null)
			{
				spr.blend = blendModeFromString(blend);
				return true;
			}
			luaTrace("setBlendMode: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("screenCenter", function(obj:String, pos:String = 'xy')
		{
			var spr:FlxSprite = FunkinLua.curInstance.getLuaObject(obj);

			if (spr == null)
			{
				var killMe:Array<String> = obj.split('.');
				spr = getObjectDirectly(killMe[0]);
				if (killMe.length > 1)
				{
					spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
				}
			}

			if (spr != null)
			{
				switch (pos.trim().toLowerCase())
				{
					case 'x':
						spr.screenCenter(X);
						return;
					case 'y':
						spr.screenCenter(Y);
						return;
					default:
						spr.screenCenter(XY);
						return;
				}
			}
			luaTrace("screenCenter: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
		});
		addCallback("objectsOverlap", function(obj1:String, obj2:String)
		{
			var namesArray:Array<String> = [obj1, obj2];
			var objectsArray:Array<FlxSprite> = [];
			for (i in 0...namesArray.length)
			{
				var real = FunkinLua.curInstance.getLuaObject(namesArray[i]);
				if (real != null)
				{
					objectsArray.push(real);
				}
				else
				{
					objectsArray.push(Reflect.getProperty(getInstance(), namesArray[i]));
				}
			}

			if (!objectsArray.contains(null) && FlxG.overlap(objectsArray[0], objectsArray[1]))
			{
				return true;
			}
			return false;
		});
		addCallback("getPixelColor", function(obj:String, x:Int, y:Int)
		{
			var killMe:Array<String> = obj.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null)
			{
				if (spr.framePixels != null)
					spr.framePixels.getPixel32(x, y);
				return spr.pixels.getPixel32(x, y);
			}
			return 0;
		});
		addCallback("getRandomInt", function(min:Int, max:Int = FlxMath.MAX_VALUE_INT, exclude:String = '')
		{
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Int> = [];
			for (i in 0...excludeArray.length)
			{
				toExclude.push(Std.parseInt(excludeArray[i].trim()));
			}
			return FlxG.random.int(min, max, toExclude);
		});
		addCallback("getRandomFloat", function(min:Float, max:Float = 1, exclude:String = '')
		{
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Float> = [];
			for (i in 0...excludeArray.length)
			{
				toExclude.push(Std.parseFloat(excludeArray[i].trim()));
			}
			return FlxG.random.float(min, max, toExclude);
		});
		addCallback("getRandomBool", function(chance:Float = 50)
		{
			return FlxG.random.bool(chance);
		});
		addCallback("playMusic", function(sound:String, volume:Float = 1, loop:Bool = false)
		{
			FlxG.sound.playMusic(Paths.music(sound), volume, loop);
		});
		addCallback("playSound", function(sound:String, volume:Float = 1, ?tag:String = null)
		{
			if (tag != null && tag.length > 0)
			{
				tag = tag.replace('.', '');
				if (FunkinLua.curInstance.modchartSounds.exists(tag))
				{
					FunkinLua.curInstance.modchartSounds.get(tag).stop();
				}
				FunkinLua.curInstance.modchartSounds.set(tag, FlxG.sound.play(Paths.sound(sound), volume, false, function()
				{
					FunkinLua.curInstance.modchartSounds.remove(tag);
					FunkinLua.curInstance.callOnLuas('onSoundFinished', [tag]);
				}));
				return;
			}
			FlxG.sound.play(Paths.sound(sound), volume);
		});
		addCallback("stopSound", function(tag:String)
		{
			if (tag != null && tag.length > 1 && FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				FunkinLua.curInstance.modchartSounds.get(tag).stop();
				FunkinLua.curInstance.modchartSounds.remove(tag);
			}
		});
		addCallback("pauseSound", function(tag:String)
		{
			if (tag != null && tag.length > 1 && FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				FunkinLua.curInstance.modchartSounds.get(tag).pause();
			}
		});
		addCallback("resumeSound", function(tag:String)
		{
			if (tag != null && tag.length > 1 && FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				FunkinLua.curInstance.modchartSounds.get(tag).play();
			}
		});
		addCallback("soundFadeIn", function(tag:String, duration:Float, fromValue:Float = 0, toValue:Float = 1)
		{
			if (tag == null || tag.length < 1)
			{
				FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			}
			else if (FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				FunkinLua.curInstance.modchartSounds.get(tag).fadeIn(duration, fromValue, toValue);
			}
		});
		addCallback("soundFadeOut", function(tag:String, duration:Float, toValue:Float = 0)
		{
			if (tag == null || tag.length < 1)
			{
				FlxG.sound.music.fadeOut(duration, toValue);
			}
			else if (FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				FunkinLua.curInstance.modchartSounds.get(tag).fadeOut(duration, toValue);
			}
		});
		addCallback("soundFadeCancel", function(tag:String)
		{
			if (tag == null || tag.length < 1)
			{
				if (FlxG.sound.music.fadeTween != null)
				{
					FlxG.sound.music.fadeTween.cancel();
				}
			}
			else if (FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				var theSound:FlxSound = FunkinLua.curInstance.modchartSounds.get(tag);
				if (theSound.fadeTween != null)
				{
					theSound.fadeTween.cancel();
					FunkinLua.curInstance.modchartSounds.remove(tag);
				}
			}
		});
		addCallback("getSoundVolume", function(tag:String)
		{
			if (tag == null || tag.length < 1)
			{
				if (FlxG.sound.music != null)
				{
					return FlxG.sound.music.volume;
				}
			}
			else if (FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				return FunkinLua.curInstance.modchartSounds.get(tag).volume;
			}
			return 0;
		});
		addCallback("setSoundVolume", function(tag:String, value:Float)
		{
			if (tag == null || tag.length < 1)
			{
				if (FlxG.sound.music != null)
				{
					FlxG.sound.music.volume = value;
				}
			}
			else if (FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				FunkinLua.curInstance.modchartSounds.get(tag).volume = value;
			}
		});
		addCallback("getSoundTime", function(tag:String)
		{
			if (tag != null && tag.length > 0 && FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				return FunkinLua.curInstance.modchartSounds.get(tag).time;
			}
			return 0;
		});
		addCallback("setSoundTime", function(tag:String, value:Float)
		{
			if (tag != null && tag.length > 0 && FunkinLua.curInstance.modchartSounds.exists(tag))
			{
				var theSound:FlxSound = FunkinLua.curInstance.modchartSounds.get(tag);
				if (theSound != null)
				{
					var wasResumed:Bool = theSound.playing;
					theSound.pause();
					theSound.time = value;
					if (wasResumed)
						theSound.play();
				}
			}
		});

		addCallback("changePresence", function(details:String, state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float)
		{
			#if desktop
			DiscordClient.changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp);
			#end
		});

		// LUA TEXTS
		addCallback("makeLuaText", function(tag:String, text:String, width:Int, x:Float, y:Float)
		{
			tag = tag.replace('.', '');
			resetTextTag(tag);
			var leText:ModchartText = new ModchartText(x, y, text, width);
			FunkinLua.curInstance.modchartTexts.set(tag, leText);
		});

		addCallback("setTextString", function(tag:String, text:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.text = text;
				return true;
			}
			luaTrace("setTextString: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setTextSize", function(tag:String, size:Int)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.size = size;
				return true;
			}
			luaTrace("setTextSize: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setTextWidth", function(tag:String, width:Float)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.fieldWidth = width;
				return true;
			}
			luaTrace("setTextWidth: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setTextBorder", function(tag:String, size:Int, color:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				var colorNum:Int = Std.parseInt(color);
				if (!color.startsWith('0x'))
					colorNum = Std.parseInt('0xff' + color);

				obj.borderSize = size;
				obj.borderColor = colorNum;
				return true;
			}
			luaTrace("setTextBorder: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setTextColor", function(tag:String, color:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				var colorNum:Int = Std.parseInt(color);
				if (!color.startsWith('0x'))
					colorNum = Std.parseInt('0xff' + color);

				obj.color = colorNum;
				return true;
			}
			luaTrace("setTextColor: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setTextFont", function(tag:String, newFont:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.font = Paths.font(newFont);
				return true;
			}
			luaTrace("setTextFont: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setTextItalic", function(tag:String, italic:Bool)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.italic = italic;
				return true;
			}
			luaTrace("setTextItalic: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setTextAlignment", function(tag:String, alignment:String = 'left')
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.alignment = LEFT;
				switch (alignment.trim().toLowerCase())
				{
					case 'right':
						obj.alignment = RIGHT;
					case 'center':
						obj.alignment = CENTER;
				}
				return true;
			}
			luaTrace("setTextAlignment: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});

		addCallback("getTextString", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null && obj.text != null)
			{
				return obj.text;
			}
			luaTrace("getTextString: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
		});
		addCallback("getTextSize", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				return obj.size;
			}
			luaTrace("getTextSize: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return -1;
		});
		addCallback("getTextFont", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				return obj.font;
			}
			luaTrace("getTextFont: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			Lua.pushnil(lua);
			return null;
		});
		addCallback("getTextWidth", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				return obj.fieldWidth;
			}
			luaTrace("getTextWidth: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return 0;
		});

		addCallback("addLuaText", function(tag:String)
		{
			if (FunkinLua.curInstance.modchartTexts.exists(tag))
			{
				var shit:ModchartText = FunkinLua.curInstance.modchartTexts.get(tag);
				if (!shit.wasAdded)
				{
					getInstance().add(shit);
					shit.wasAdded = true;
					// trace('added a thing: ' + tag);
				}
			}
		});
		addCallback("removeLuaText", function(tag:String, destroy:Bool = true)
		{
			if (!FunkinLua.curInstance.modchartTexts.exists(tag))
			{
				return;
			}

			var pee:ModchartText = FunkinLua.curInstance.modchartTexts.get(tag);
			if (destroy)
			{
				pee.kill();
			}

			if (pee.wasAdded)
			{
				getInstance().remove(pee, true);
				pee.wasAdded = false;
			}

			if (destroy)
			{
				pee.destroy();
				FunkinLua.curInstance.modchartTexts.remove(tag);
			}
		});

		addCallback("initSaveData", function(name:String, ?folder:String = 'psychenginemods')
		{
			if (!FunkinLua.curInstance.modchartSaves.exists(name))
			{
				var save:FlxSave = new FlxSave();
				// folder goes unused for flixel 5 users. @BeastlyGhost
				save.bind(name #if (flixel < "5.0.0"), folder #end);
				FunkinLua.curInstance.modchartSaves.set(name, save);
				return;
			}
			luaTrace('initSaveData: Save file already initialized: ' + name);
		});
		addCallback("flushSaveData", function(name:String)
		{
			if (name == null)
			{
				FlxG.save.flush();
				return;
			}
			else if (FunkinLua.curInstance.modchartSaves.exists(name))
			{
				FunkinLua.curInstance.modchartSaves.get(name).flush();
				return;
			}
			luaTrace('flushSaveData: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});
		addCallback("getDataFromSave", function(name:String, field:String, ?defaultValue:Dynamic = null)
		{
			if (FunkinLua.curInstance.modchartSaves.exists(name))
			{
				var retVal:Dynamic = Reflect.field(FunkinLua.curInstance.modchartSaves.get(name).data, field);
				return retVal;
			}
			luaTrace('getDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
			return defaultValue;
		});
		addCallback("setDataFromSave", function(name:String, field:String, value:Dynamic)
		{
			if (FunkinLua.curInstance.modchartSaves.exists(name))
			{
				Reflect.setField(FunkinLua.curInstance.modchartSaves.get(name).data, field, value);
				return;
			}
			luaTrace('setDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});

		addCallback("checkFileExists", function(filename:String, ?absolute:Bool = false)
		{
			#if MODS_ALLOWED
			if (absolute)
			{
				return FileSystem.exists(filename);
			}

			var path:String = Paths.modFolders(filename);
			if (FileSystem.exists(path))
			{
				return true;
			}
			return FileSystem.exists(Paths.getPath('assets/$filename', TEXT));
			#else
			if (absolute)
			{
				return Assets.exists(filename);
			}
			return Assets.exists(Paths.getPath('assets/$filename', TEXT));
			#end
		});
		addCallback("saveFile", function(path:String, content:String, ?absolute:Bool = false)
		{
			try
			{
				if (!absolute)
					File.saveContent(Paths.mods(path), content);
				else
					File.saveContent(path, content);

				return true;
			}
			catch (e:Dynamic)
			{
				luaTrace("saveFile: Error trying to save " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		addCallback("deleteFile", function(path:String, ?ignoreModFolders:Bool = false)
		{
			try
			{
				#if MODS_ALLOWED
				if (!ignoreModFolders)
				{
					var lePath:String = Paths.modFolders(path);
					if (FileSystem.exists(lePath))
					{
						FileSystem.deleteFile(lePath);
						return true;
					}
				}
				#end

				var lePath:String = Paths.getPath(path, TEXT);
				if (Assets.exists(lePath))
				{
					FileSystem.deleteFile(lePath);
					return true;
				}
			}
			catch (e:Dynamic)
			{
				luaTrace("deleteFile: Error trying to delete " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		addCallback("getTextFromFile", function(path:String, ?ignoreModFolders:Bool = false)
		{
			return Paths.getTextFromFile(path, ignoreModFolders);
		});

		// DEPRECATED, DONT MESS WITH THESE SHITS, ITS JUST THERE FOR BACKWARD COMPATIBILITY
		addCallback("objectPlayAnimation", function(obj:String, name:String, forced:Bool = false, ?startFrame:Int = 0)
		{
			luaTrace("objectPlayAnimation is deprecated! Use playAnim instead", false, true);
			if (FunkinLua.curInstance.getLuaObject(obj, false) != null)
			{
				FunkinLua.curInstance.getLuaObject(obj, false).animation.play(name, forced, false, startFrame);
				return true;
			}

			var spr:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (spr != null)
			{
				spr.animation.play(name, forced, false, startFrame);
				return true;
			}
			return false;
		});
		addCallback("characterPlayAnim", function(character:String, anim:String, ?forced:Bool = false)
		{
			luaTrace("characterPlayAnim is deprecated! Use playAnim instead", false, true);
			switch (character.toLowerCase())
			{
				case 'dad':
					if (PlayState.instance.dad.animOffsets.exists(anim))
						PlayState.instance.dad.playAnim(anim, forced);
				case 'gf' | 'girlfriend':
					if (PlayState.instance.gf != null && PlayState.instance.gf.animOffsets.exists(anim))
						PlayState.instance.gf.playAnim(anim, forced);
				default:
					if (PlayState.instance.boyfriend.animOffsets.exists(anim))
						PlayState.instance.boyfriend.playAnim(anim, forced);
			}
		});
		addCallback("luaSpriteMakeGraphic", function(tag:String, width:Int, height:Int, color:String)
		{
			luaTrace("luaSpriteMakeGraphic is deprecated! Use makeGraphic instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var colorNum:Int = Std.parseInt(color);
				if (!color.startsWith('0x'))
					colorNum = Std.parseInt('0xff' + color);

				FunkinLua.curInstance.modchartSprites.get(tag).makeGraphic(width, height, colorNum);
			}
		});
		addCallback("luaSpriteAddAnimationByPrefix", function(tag:String, name:String, prefix:String, framerate:Int = 24, loop:Bool = true)
		{
			luaTrace("luaSpriteAddAnimationByPrefix is deprecated! Use addAnimationByPrefix instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var cock:ModchartSprite = FunkinLua.curInstance.modchartSprites.get(tag);
				cock.animation.addByPrefix(name, prefix, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
			}
		});
		addCallback("luaSpriteAddAnimationByIndices", function(tag:String, name:String, prefix:String, indices:String, framerate:Int = 24)
		{
			luaTrace("luaSpriteAddAnimationByIndices is deprecated! Use addAnimationByIndices instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var strIndices:Array<String> = indices.trim().split(',');
				var die:Array<Int> = [];
				for (i in 0...strIndices.length)
				{
					die.push(Std.parseInt(strIndices[i]));
				}
				var pussy:ModchartSprite = FunkinLua.curInstance.modchartSprites.get(tag);
				pussy.animation.addByIndices(name, prefix, die, '', framerate, false);
				if (pussy.animation.curAnim == null)
				{
					pussy.animation.play(name, true);
				}
			}
		});
		addCallback("luaSpritePlayAnimation", function(tag:String, name:String, forced:Bool = false)
		{
			luaTrace("luaSpritePlayAnimation is deprecated! Use playAnim instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				FunkinLua.curInstance.modchartSprites.get(tag).animation.play(name, forced);
			}
		});
		addCallback("setLuaSpriteCamera", function(tag:String, camera:String = '')
		{
			luaTrace("setLuaSpriteCamera is deprecated! Use setObjectCamera instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				FunkinLua.curInstance.modchartSprites.get(tag).cameras = [cameraFromString(camera)];
				return true;
			}
			luaTrace("Lua sprite with tag: " + tag + " doesn't exist!");
			return false;
		});
		addCallback("setLuaSpriteScrollFactor", function(tag:String, scrollX:Float, scrollY:Float)
		{
			luaTrace("setLuaSpriteScrollFactor is deprecated! Use setScrollFactor instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				FunkinLua.curInstance.modchartSprites.get(tag).scrollFactor.set(scrollX, scrollY);
				return true;
			}
			return false;
		});
		addCallback("scaleLuaSprite", function(tag:String, x:Float, y:Float)
		{
			luaTrace("scaleLuaSprite is deprecated! Use scaleObject instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var shit:ModchartSprite = FunkinLua.curInstance.modchartSprites.get(tag);
				shit.scale.set(x, y);
				shit.updateHitbox();
				return true;
			}
			return false;
		});
		addCallback("getPropertyLuaSprite", function(tag:String, variable:String)
		{
			luaTrace("getPropertyLuaSprite is deprecated! Use getProperty instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var killMe:Array<String> = variable.split('.');
				if (killMe.length > 1)
				{
					var coverMeInPiss:Dynamic = Reflect.getProperty(FunkinLua.curInstance.modchartSprites.get(tag), killMe[0]);
					for (i in 1...killMe.length - 1)
					{
						coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
					}
					return Reflect.getProperty(coverMeInPiss, killMe[killMe.length - 1]);
				}
				return Reflect.getProperty(FunkinLua.curInstance.modchartSprites.get(tag), variable);
			}
			return null;
		});
		addCallback("setPropertyLuaSprite", function(tag:String, variable:String, value:Dynamic)
		{
			luaTrace("setPropertyLuaSprite is deprecated! Use setProperty instead", false, true);
			if (FunkinLua.curInstance.modchartSprites.exists(tag))
			{
				var killMe:Array<String> = variable.split('.');
				if (killMe.length > 1)
				{
					var coverMeInPiss:Dynamic = Reflect.getProperty(FunkinLua.curInstance.modchartSprites.get(tag), killMe[0]);
					for (i in 1...killMe.length - 1)
					{
						coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
					}
					Reflect.setProperty(coverMeInPiss, killMe[killMe.length - 1], value);
					return true;
				}
				Reflect.setProperty(FunkinLua.curInstance.modchartSprites.get(tag), variable, value);
				return true;
			}
			luaTrace("setPropertyLuaSprite: Lua sprite with tag: " + tag + " doesn't exist!");
			return false;
		});
		addCallback("musicFadeIn", function(duration:Float, fromValue:Float = 0, toValue:Float = 1)
		{
			FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			luaTrace('musicFadeIn is deprecated! Use soundFadeIn instead.', false, true);
		});
		addCallback("musicFadeOut", function(duration:Float, toValue:Float = 0)
		{
			FlxG.sound.music.fadeOut(duration, toValue);
			luaTrace('musicFadeOut is deprecated! Use soundFadeOut instead.', false, true);
		});

		// Other stuff
		addCallback("stringStartsWith", function(str:String, start:String)
		{
			return str.startsWith(start);
		});
		addCallback("stringEndsWith", function(str:String, end:String)
		{
			return str.endsWith(end);
		});
		addCallback("stringSplit", function(str:String, split:String)
		{
			return str.split(split);
		});
		addCallback("stringTrim", function(str:String)
		{
			return str.trim();
		});

		addCallback("directoryFileList", function(folder:String)
		{
			var list:Array<String> = [];
			#if sys
			if (FileSystem.exists(folder))
			{
				for (folder in FileSystem.readDirectory(folder))
				{
					if (!list.contains(folder))
					{
						list.push(folder);
					}
				}
			}
			#end
			return list;
		});
		addCallback("debugPrint", function(text1:Dynamic = '', text2:Dynamic = '', text3:Dynamic = '', text4:Dynamic = '', text5:Dynamic = '')
		{
			if (text1 == null)
				text1 = '';
			if (text2 == null)
				text2 = '';
			if (text3 == null)
				text3 = '';
			if (text4 == null)
				text4 = '';
			if (text5 == null)
				text5 = '';
			luaTrace('' + text1 + text2 + text3 + text4 + text5, true, false);
		});

		addCallback("close", function()
		{
			closed = true;
			return closed;
		});

		addCallback('callMethod', function(func:String, args:Array<Dynamic>)
		{
			return Reflect.callMethod(FunkinLua.curInstance, Reflect.field(FunkinLua.curInstance, func), args);
		});

		addCallback('setDebugTextOnTop', function()
		{
			FunkinLua.curInstance.setDebugTextOnTop();
		});

		addCallback('getGlobalProperty', function(variable:String)
		{
			var YEAH:Dynamic = CoolUtil.globalLuaVariables.get(variable);
			if (YEAH == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return YEAH;
		});

		addCallback('setGlobalProperty', function(variable:String, value:String)
		{
			CoolUtil.globalLuaVariables.set(variable, value);
		});

		addCallback("loadSong", function(?name:String = null, ?difficultyNum:Int = -1)
		{
			luaTrace("loadSong is deprecated! Use enterSong instead", false, true);
			if (CoolUtil.curLuaState == 'playstate')
			{
				trace('ok dude');
				if (name == null || name.length < 1)
					name = PlayState.SONG.song;
				if (difficultyNum == -1)
					difficultyNum = PlayState.storyDifficulty;

				var poop = Highscore.formatSong(name, difficultyNum);
				PlayState.SONG = Song.loadFromJson(poop, name);
				PlayState.storyDifficulty = difficultyNum;
				PlayState.instance.persistentUpdate = false;
				LoadingState.loadAndSwitchState(new PlayState());

				FlxG.sound.music.pause();
				FlxG.sound.music.volume = 0;
				if (PlayState.instance.vocals != null)
				{
					PlayState.instance.vocals.pause();
					PlayState.instance.vocals.volume = 0;
				}
			}
		});

		addCallback('enterSong', function(name:String, diff:String) {
			PlayState.SONG = Song.loadFromJson('$name-$diff', name);
			PlayState.storyDifficulty = CoolUtil.difficulties.indexOf(diff);
			if (CoolUtil.curLuaState == 'playstate')
				PlayState.instance.persistentUpdate = false;
			LoadingState.loadAndSwitchState(new PlayState());
			FlxG.sound.music.pause();
			FlxG.sound.music.volume = 0;
			if (CoolUtil.curLuaState == 'playstate' && PlayState.instance.vocals != null)
			{
				PlayState.instance.vocals.pause();
				PlayState.instance.vocals.volume = 0;
			}
		});

		addCallback('getGameplayChanger', function(name:String)
		{
			var YEAH:Dynamic = ClientPrefs.gameplaySettings.get(name);
			if (YEAH == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return YEAH;
		});

		addCallback('getClientPref', function(name:String)
		{
			var YEAH:Dynamic = Reflect.getProperty(ClientPrefs, name);
			if (YEAH == null)
				YEAH = ClientPrefs.luaPrefs.get(name);
			if (YEAH == null)
			{
				Lua.pushnil(lua);
				return null;
			}
			return YEAH;
		});

		// makes a menubg and disguses it as a modchartSprite
		addCallback('makeMenuBG', function(tag:String, x:Float, y:Float, ?color:Int, ?image:String)
		{
			var bg:MenuBG = new MenuBG(x, y, color, image);
			FunkinLua.curInstance.variables.set(tag, bg);
		});
		addCallback('setMenuBgs', function(newBgs:Array<Array<Dynamic>>)
		{
			MenuBG.bgs = newBgs;
		});
		addCallback('saveSet', function(variable:String, value:Dynamic)
		{
			if (FlxG.save.data.luaSaves == null)
				FlxG.save.data.luaSaves = new Map<String, Dynamic>();
			FlxG.save.data.luaSaves.set(variable, value);
		});
		addCallback('saveGet', function(variable:String)
		{
			var thing = null;
			if (FlxG.save.data.luaSaves != null)
				thing = FlxG.save.data.luaSaves.get(variable);
			if (thing == null)
				Lua.pushnil(lua);
			return thing;
		});
		addCallback('setVar', function(variable:String, value:Dynamic)
		{
			FunkinLua.curInstance.variables.set(variable, value);
		});
		addCallback('contains', function(t:Array<Dynamic>, what:Dynamic)
		{
			return t.contains(what);
		});
		addCallback('indexOf', function(t:Array<Dynamic>, what:Dynamic)
		{
			return t.indexOf(what);
		});

		addCallback('switchState', function(name:String)
		{
			switch (name.toLowerCase().trim())
			{
				case 'playstate':
					MusicBeatState.switchState(new PlayState());
				case 'mainmenustate':
					MusicBeatState.switchState(new MainMenuState());
				case 'titlestate':
					MusicBeatState.switchState(new TitleState());
				case 'freeplaystate':
					MusicBeatState.switchState(new FreeplayState());
				case 'mastereditormenu' | 'editors.mastereditormenu':
					MusicBeatState.switchState(new editors.MasterEditorMenu());
				case 'optionsstate' | 'options.optionsstate':
					LoadingState.loadAndSwitchState(new options.OptionsState());
				default:
					CustomLuaState.curState = name;
					MusicBeatState.switchState(new CustomLuaState());
			}
			// ill get this working eventually, probably not lol
			// if(FileSystem.exists(Paths.mods('scripts/${name}'))) //check for custom states
			// {
			// 	CustomLuaState.curState = name;
			// 	MusicBeatState.switchState(new CustomLuaState());
			// }
			// else
			// {
			// 	try{
			// 		if(args == null)
			// 			args = [];
			// 		MusicBeatState.switchState(Type.createInstance(Type.resolveClass(name), args));
			// 	}catch(e:Dynamic){
			// 		luaTrace('Error switching state: ${e.toString()}', false, false, FlxColor.RED);
			// 	}
			// }
		});

		switch (CoolUtil.curLuaState) // state specific callbacks
		{
			case 'playstate':
				addCallback("characterDance", function(character:String)
				{
					switch (character.toLowerCase())
					{
						case 'dad':
							PlayState.instance.dad.dance();
						case 'gf' | 'girlfriend':
							if (PlayState.instance.gf != null)
								PlayState.instance.gf.dance();
						default:
							PlayState.instance.boyfriend.dance();
					}
				});
				addCallback("noteTweenX", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
				{
					cancelTween(tag);
					if (note < 0)
						note = 0;
					var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

					if (testicle != null)
					{
						FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(testicle, {x: value}, duration, {
							ease: getFlxEaseByString(ease),
							onComplete: function(twn:FlxTween)
							{
								FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
								FunkinLua.curInstance.modchartTweens.remove(tag);
							}
						}));
					}
				});
				addCallback("noteTweenY", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
				{
					cancelTween(tag);
					if (note < 0)
						note = 0;
					var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

					if (testicle != null)
					{
						FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(testicle, {y: value}, duration, {
							ease: getFlxEaseByString(ease),
							onComplete: function(twn:FlxTween)
							{
								FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
								FunkinLua.curInstance.modchartTweens.remove(tag);
							}
						}));
					}
				});
				addCallback("noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
				{
					cancelTween(tag);
					if (note < 0)
						note = 0;
					var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

					if (testicle != null)
					{
						FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(testicle, {angle: value}, duration, {
							ease: getFlxEaseByString(ease),
							onComplete: function(twn:FlxTween)
							{
								FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
								FunkinLua.curInstance.modchartTweens.remove(tag);
							}
						}));
					}
				});
				addCallback("noteTweenDirection", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
				{
					cancelTween(tag);
					if (note < 0)
						note = 0;
					var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

					if (testicle != null)
					{
						FunkinLua.curInstance.modchartTweens.set(tag, FlxTween.tween(testicle, {direction: value}, duration, {
							ease: getFlxEaseByString(ease),
							onComplete: function(twn:FlxTween)
							{
								FunkinLua.curInstance.callOnLuas('onTweenCompleted', [tag]);
								FunkinLua.curInstance.modchartTweens.remove(tag);
							}
						}));
					}
				});
				addCallback("addScore", function(value:Int = 0)
				{
					PlayState.instance.songScore += value;
					PlayState.instance.RecalculateRating();
				});
				addCallback("addMisses", function(value:Int = 0)
				{
					PlayState.instance.songMisses += value;
					PlayState.instance.RecalculateRating();
				});
				addCallback("addHits", function(value:Int = 0)
				{
					PlayState.instance.songHits += value;
					PlayState.instance.RecalculateRating();
				});
				addCallback("setScore", function(value:Int = 0)
				{
					PlayState.instance.songScore = value;
					PlayState.instance.RecalculateRating();
				});
				addCallback("setMisses", function(value:Int = 0)
				{
					PlayState.instance.songMisses = value;
					PlayState.instance.RecalculateRating();
				});
				addCallback("setHits", function(value:Int = 0)
				{
					PlayState.instance.songHits = value;
					PlayState.instance.RecalculateRating();
				});
				addCallback("getScore", function()
				{
					return PlayState.instance.songScore;
				});
				addCallback("getMisses", function()
				{
					return PlayState.instance.songMisses;
				});
				addCallback("getHits", function()
				{
					return PlayState.instance.songHits;
				});
				addCallback("setHealth", function(value:Float = 0)
				{
					PlayState.instance.health = value;
				});
				addCallback("addHealth", function(value:Float = 0)
				{
					PlayState.instance.health += value;
				});
				addCallback("getHealth", function()
				{
					return PlayState.instance.health;
				});
				addCallback("startDialogue", function(dialogueFile:String, music:String = null)
				{
					var path:String;
					#if MODS_ALLOWED
					path = Paths.modsJson(Paths.formatToSongPath(PlayState.SONG.song) + '/' + dialogueFile);
					if (!FileSystem.exists(path))
					#end
					path = Paths.json(Paths.formatToSongPath(PlayState.SONG.song) + '/' + dialogueFile);
	
					luaTrace('startDialogue: Trying to load dialogue: ' + path);
	
					#if MODS_ALLOWED
					if (FileSystem.exists(path))
					#else
					if (Assets.exists(path))
					#end
					{
						var shit:DialogueFile = DialogueBoxPsych.parseDialogue(path);
						if (shit.dialogue.length > 0)
						{
							PlayState.instance.startDialogue(shit, music);
							luaTrace('startDialogue: Successfully loaded dialogue', false, false, FlxColor.GREEN);
							return true;
						}
						else
						{
							luaTrace('startDialogue: Your dialogue file is badly formatted!', false, false, FlxColor.RED);
						}
					}
				else
				{
					luaTrace('startDialogue: Dialogue file not found', false, false, FlxColor.RED);
					if (PlayState.instance.endingSong)
					{
						PlayState.instance.endSong();
					}
					else
					{
						PlayState.instance.startCountdown();
					}
				}
					return false;
				});
				addCallback("startVideo", function(videoFile:String)
				{
					#if VIDEOS_ALLOWED
					if (FileSystem.exists(Paths.video(videoFile)))
					{
						PlayState.instance.startVideo(videoFile);
						return true;
					}
					else
					{
						luaTrace('startVideo: Video file not found: ' + videoFile, false, false, FlxColor.RED);
					}
					return false;
					#else
					if (PlayState.instance.endingSong)
					{
						PlayState.instance.endSong();
					}
					else
					{
						PlayState.instance.startCountdown();
					}
					return true;
					#end
				});
				addCallback("keyJustPressed", function(name:String)
				{
					var key:Bool = false;
					switch (name)
					{
						case 'left':
							key = PlayState.instance.getControl('NOTE_LEFT_P');
						case 'down':
							key = PlayState.instance.getControl('NOTE_DOWN_P');
						case 'up':
							key = PlayState.instance.getControl('NOTE_UP_P');
						case 'right':
							key = PlayState.instance.getControl('NOTE_RIGHT_P');
						case 'accept':
							key = PlayState.instance.getControl('ACCEPT');
						case 'back':
							key = PlayState.instance.getControl('BACK');
						case 'pause':
							key = PlayState.instance.getControl('PAUSE');
						case 'reset':
							key = PlayState.instance.getControl('RESET');
						case 'space':
							key = FlxG.keys.justPressed.SPACE; // an extra key for convinience
					}
					return key;
				});
				addCallback("keyPressed", function(name:String)
				{
					var key:Bool = false;
					switch (name)
					{
						case 'left':
							key = PlayState.instance.getControl('NOTE_LEFT');
						case 'down':
							key = PlayState.instance.getControl('NOTE_DOWN');
						case 'up':
							key = PlayState.instance.getControl('NOTE_UP');
						case 'right':
							key = PlayState.instance.getControl('NOTE_RIGHT');
						case 'space':
							key = FlxG.keys.pressed.SPACE; // an extra key for convinience
					}
					return key;
				});
				addCallback("keyReleased", function(name:String)
				{
					var key:Bool = false;
					switch (name)
					{
						case 'left':
							key = PlayState.instance.getControl('NOTE_LEFT_R');
						case 'down':
							key = PlayState.instance.getControl('NOTE_DOWN_R');
						case 'up':
							key = PlayState.instance.getControl('NOTE_UP_R');
						case 'right':
							key = PlayState.instance.getControl('NOTE_RIGHT_R');
						case 'space':
							key = FlxG.keys.justReleased.SPACE; // an extra key for convinience
					}
					return key;
				});
				addCallback("addCharacterToList", function(name:String, type:String)
				{
					var charType:Int = 0;
					switch (type.toLowerCase())
					{
						case 'dad':
							charType = 1;
						case 'gf' | 'girlfriend':
							charType = 2;
					}
					PlayState.instance.addCharacterToList(name, charType);
				});
				addCallback("setHealthBarColors", function(leftHex:String, rightHex:String)
				{
					var left:FlxColor = Std.parseInt(leftHex);
					if (!leftHex.startsWith('0x'))
						left = Std.parseInt('0xff' + leftHex);
					var right:FlxColor = Std.parseInt(rightHex);
					if (!rightHex.startsWith('0x'))
						right = Std.parseInt('0xff' + rightHex);
	
					PlayState.instance.healthBar.createFilledBar(left, right);
					PlayState.instance.healthBar.updateBar();
				});
				addCallback("setTimeBarColors", function(leftHex:String, rightHex:String)
				{
					var left:FlxColor = Std.parseInt(leftHex);
					if (!leftHex.startsWith('0x'))
						left = Std.parseInt('0xff' + leftHex);
					var right:FlxColor = Std.parseInt(rightHex);
					if (!rightHex.startsWith('0x'))
						right = Std.parseInt('0xff' + rightHex);
	
					PlayState.instance.timeBar.createFilledBar(right, left);
					PlayState.instance.timeBar.updateBar();
				});
	
				addCallback("setObjectCamera", function(obj:String, camera:String = '')
				{
					/*if(FunkinLua.curInstance.modchartSprites.exists(obj)) {
							FunkinLua.curInstance.modchartSprites.get(obj).cameras = [cameraFromString(camera)];
							return true;
						}
						else if(FunkinLua.curInstance.modchartTexts.exists(obj)) {
							FunkinLua.curInstance.modchartTexts.get(obj).cameras = [cameraFromString(camera)];
							return true;
					}*/
					var real = FunkinLua.curInstance.getLuaObject(obj);
					if (real != null)
					{
						real.cameras = [cameraFromString(camera)];
						return true;
					}
	
					var killMe:Array<String> = obj.split('.');
					var object:FlxSprite = getObjectDirectly(killMe[0]);
					if (killMe.length > 1)
					{
						object = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
					}
	
					if (object != null)
					{
						object.cameras = [cameraFromString(camera)];
						return true;
					}
					luaTrace("setObjectCamera: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
					return false;
				});
				addCallback("triggerEvent", function(name:String, arg1:Dynamic, arg2:Dynamic)
				{
					var value1:String = arg1;
					var value2:String = arg2;
					PlayState.instance.triggerEventNote(name, value1, value2);
					// trace('Triggered event: ' + name + ', ' + value1 + ', ' + value2);
					return true;
				});
				addCallback("startCountdown", function()
				{
					PlayState.instance.startCountdown();
					return true;
				});
				addCallback("endSong", function()
				{
					PlayState.instance.KillNotes();
					PlayState.instance.endSong();
					return true;
				});
				addCallback("restartSong", function(?skipTransition:Bool = false)
				{
					FunkinLua.curInstance.persistentUpdate = false;
					PauseSubState.restartSong(skipTransition);
					return true;
				});
				addCallback("exitSong", function(?skipTransition:Bool = false)
				{
					if (skipTransition)
					{
						FlxTransitionableState.skipNextTransIn = true;
						FlxTransitionableState.skipNextTransOut = true;
					}
	
					PlayState.cancelMusicFadeTween();
					CustomFadeTransition.nextCamera = PlayState.instance.camOther;
					if (FlxTransitionableState.skipNextTransIn)
						CustomFadeTransition.nextCamera = null;
	
					if (PlayState.isStoryMode)
						MusicBeatState.switchState(new StoryMenuState());
					else
						MusicBeatState.switchState(new FreeplayState());
	
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					PlayState.changedDifficulty = false;
					PlayState.chartingMode = false;
					PlayState.instance.transitioning = true;
					WeekData.loadTheFirstEnabledMod();
					return true;
				});
				addCallback("getSongPosition", function()
				{
					return Conductor.songPosition;
				});
				addCallback("getCharacterX", function(type:String)
				{
					switch (type.toLowerCase())
					{
						case 'dad' | 'opponent':
							return PlayState.instance.dadGroup.x;
						case 'gf' | 'girlfriend':
							return PlayState.instance.gfGroup.x;
						default:
							return PlayState.instance.boyfriendGroup.x;
					}
				});
				addCallback("setCharacterX", function(type:String, value:Float)
				{
					switch (type.toLowerCase())
					{
						case 'dad' | 'opponent':
							PlayState.instance.dadGroup.x = value;
						case 'gf' | 'girlfriend':
							PlayState.instance.gfGroup.x = value;
						default:
							PlayState.instance.boyfriendGroup.x = value;
					}
				});
				addCallback("getCharacterY", function(type:String)
				{
					switch (type.toLowerCase())
					{
						case 'dad' | 'opponent':
							return PlayState.instance.dadGroup.y;
						case 'gf' | 'girlfriend':
							return PlayState.instance.gfGroup.y;
						default:
							return PlayState.instance.boyfriendGroup.y;
					}
				});
				addCallback("setCharacterY", function(type:String, value:Float)
				{
					switch (type.toLowerCase())
					{
						case 'dad' | 'opponent':
							PlayState.instance.dadGroup.y = value;
						case 'gf' | 'girlfriend':
							PlayState.instance.gfGroup.y = value;
						default:
							PlayState.instance.boyfriendGroup.y = value;
					}
				});
				addCallback("cameraSetTarget", function(target:String)
				{
					var isDad:Bool = false;
					if (target == 'dad')
					{
						isDad = true;
					}
					PlayState.instance.moveCamera(isDad);
					return isDad;
				});
				addCallback("cameraShake", function(camera:String, intensity:Float, duration:Float)
				{
					cameraFromString(camera).shake(intensity, duration);
				});
				addCallback("cameraFlash", function(camera:String, color:String, duration:Float, forced:Bool)
				{
					var colorNum:Int = Std.parseInt(color);
					if (!color.startsWith('0x'))
						colorNum = Std.parseInt('0xff' + color);
					cameraFromString(camera).flash(colorNum, duration, null, forced);
				});
				addCallback("cameraFade", function(camera:String, color:String, duration:Float, forced:Bool)
				{
					var colorNum:Int = Std.parseInt(color);
					if (!color.startsWith('0x'))
						colorNum = Std.parseInt('0xff' + color);
					cameraFromString(camera).fade(colorNum, duration, false, null, forced);
				});
				addCallback("setRatingPercent", function(value:Float)
				{
					PlayState.instance.ratingPercent = value;
				});
				addCallback("setRatingName", function(value:String)
				{
					PlayState.instance.ratingName = value;
				});
				addCallback("setRatingFC", function(value:String)
				{
					PlayState.instance.ratingFC = value;
				});
			// im gotta add the rest here at some point but not rn
			case 'titlestate':
				addCallback('createCoolText', function(text:Array<String>, ?offset:Float)
				{
					TitleState.instance.createCoolText(text, offset);
				});
				addCallback('addMoreText', function(text:String, ?offset:Float)
				{
					TitleState.instance.addMoreText(text, offset);
				});
			case 'mainmenustate':

			case 'freeplaystate':
				addCallback('getSongs', function()
				{ // basically return an object that doesnt have the constructor so that it can be used in lua
					var songs:Array<Dynamic> = [
						for (i in FreeplayState.instance.songs)
							{
								songName: i.songName,
								week: i.week,
								songCharacter: i.songCharacter,
								color: i.color,
								folder: i.folder
							}
					];
					return songs;
				});
				addCallback('addGameplayChanger', function(optionStuff:GameplayChangersSubstate.GameplayOptionLua)
				{
					if (FreeplayState.substateInstance != null)
					{
						FreeplayState.substateInstance.addOption(optionStuff);
					}
				});
				addCallback('getOptionValue', function(name:String)
				{
					if (FreeplayState.substateInstance != null)
					{
						FreeplayState.substateInstance.getOptionByName(name).getValue();
					}
				});
				addCallback('setOptionValue', function(name:String, value:Dynamic)
				{
					if (FreeplayState.substateInstance != null)
					{
						FreeplayState.substateInstance.getOptionByName(name).setValue(value);
					}
				});
			case 'optionsstate':
				addCallback('addState', function(name:String)
				{
					trace('adding state', name);
					options.OptionsState.instance.options.push(name);
				});
				addCallback('addOption', function(optionsStuff:options.Option.OptionsData)
				{
					if (CoolUtil.inOptions)
					{
						trace('adding option', optionsStuff);
						options.OptionsState.optionInstance.addOptionByData(optionsStuff);
					}
				});
		}
		addCallback('controls', function(control:String) {
			return Reflect.getProperty(PlayerSettings.player1.controls, control);
		});
		call('onCreate', []);
		#end
	}

	public static function isOfTypes(value:Any, types:Array<Dynamic>)
	{
		for (type in types)
		{
			if (Std.isOfType(value, type))
				return true;
		}
		return false;
	}

	#if hscript
	public function initHaxeModule()
	{
		if (hscript == null)
		{
			trace('initializing haxe interp for: $scriptName');
			hscript = new HScript(this); // TO DO: Fix issue with 2 scripts not being able to use the same variable names
		}
	}
	#end

	public static function setVarInArray(instance:Dynamic, variable:String, value:Dynamic):Any
	{
		var shit:Array<String> = variable.split('[');
		if (shit.length > 1)
		{
			var blah:Dynamic = null;
			if (FunkinLua.curInstance.variables.exists(shit[0]))
			{
				var retVal:Dynamic = FunkinLua.curInstance.variables.get(shit[0]);
				if (retVal != null)
					blah = retVal;
			}
			else
				blah = Reflect.getProperty(instance, shit[0]);

			for (i in 1...shit.length)
			{
				var leNum:Dynamic = shit[i].substr(0, shit[i].length - 1);
				if (i >= shit.length - 1) // Last array
					blah[leNum] = value;
				else // Anything else
					blah = blah[leNum];
			}
			return blah;
		}
		/*if(Std.isOfType(instance, Map))
				instance.set(variable,value);
			else */

		if (FunkinLua.curInstance.variables.exists(variable))
		{
			FunkinLua.curInstance.variables.set(variable, value);
			return true;
		}

		Reflect.setProperty(instance, variable, value);
		return true;
	}

	public static function getVarInArray(instance:Dynamic, variable:String):Any
	{
		var shit:Array<String> = variable.split('[');
		if (shit.length > 1)
		{
			var blah:Dynamic = null;
			if (FunkinLua.curInstance.variables.exists(shit[0]))
			{
				var retVal:Dynamic = FunkinLua.curInstance.variables.get(shit[0]);
				if (retVal != null)
					blah = retVal;
			}
			else
				blah = Reflect.getProperty(instance, shit[0]);

			for (i in 1...shit.length)
			{
				var leNum:Dynamic = shit[i].substr(0, shit[i].length - 1);
				blah = blah[leNum];
			}
			return blah;
		}

		if (FunkinLua.curInstance.variables.exists(variable))
		{
			var retVal:Dynamic = FunkinLua.curInstance.variables.get(variable);
			if (retVal != null)
				return retVal;
		}

		return Reflect.getProperty(instance, variable);
	}

	inline static function getTextObject(name:String):FlxText
	{
		return FunkinLua.curInstance.modchartTexts.exists(name) ? FunkinLua.curInstance.modchartTexts.get(name) : Reflect.getProperty(FunkinLua.curInstance,
			name);
	}

	#if (!flash && sys)
	public function getShader(obj:String):FlxRuntimeShader
	{
		var killMe:Array<String> = obj.split('.');
		var leObj:FlxSprite = getObjectDirectly(killMe[0]);
		if (killMe.length > 1)
		{
			leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
		}

		if (leObj != null)
		{
			var shader:Dynamic = leObj.shader;
			var shader:FlxRuntimeShader = shader;
			return shader;
		}
		return null;
	}
	#end

	function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if (!ClientPrefs.shaders)
			return false;

		#if (!flash && sys)
		if (ShaderHandler.runtimeShaders.exists(name))
		{
			luaTrace('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [Paths.mods('shaders/'), Paths.getPreloadPath('shaders/')];
		if (Paths.currentModDirectory != null && Paths.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Paths.currentModDirectory + '/shaders/'));

		for (mod in Paths.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));

		for (folder in foldersToCheck)
		{
			if (FileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if (FileSystem.exists(frag))
				{
					frag = File.getContent(frag);
					found = true;
				}
				else
					frag = null;

				if (FileSystem.exists(vert))
				{
					vert = File.getContent(vert);
					found = true;
				}
				else
					vert = null;

				if (found)
				{
					ShaderHandler.runtimeShaders.set(name, [frag, vert]);
					// trace('Found shader $name!');
					return true;
				}
			}
		}
		luaTrace('Missing shader $name .frag AND .vert files!', false, false, FlxColor.RED);
		#else
		luaTrace('This platform doesn\'t support Runtime Shaders!', false, false, FlxColor.RED);
		#end
		return false;
	}

	function getGroupStuff(leArray:Dynamic, variable:String)
	{
		var killMe:Array<String> = variable.split('.');
		if (killMe.length > 1)
		{
			var coverMeInPiss:Dynamic = Reflect.getProperty(leArray, killMe[0]);
			for (i in 1...killMe.length - 1)
			{
				coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
			}
			switch (Type.typeof(coverMeInPiss))
			{
				case ValueType.TClass(haxe.ds.StringMap) | ValueType.TClass(haxe.ds.ObjectMap) | ValueType.TClass(haxe.ds.IntMap) | ValueType.TClass(haxe.ds.EnumValueMap):
					return coverMeInPiss.get(killMe[killMe.length - 1]);
				default:
					return Reflect.getProperty(coverMeInPiss, killMe[killMe.length - 1]);
			};
		}
		switch (Type.typeof(leArray))
		{
			case ValueType.TClass(haxe.ds.StringMap) | ValueType.TClass(haxe.ds.ObjectMap) | ValueType.TClass(haxe.ds.IntMap) | ValueType.TClass(haxe.ds.EnumValueMap):
				return leArray.get(variable);
			default:
				return Reflect.getProperty(leArray, variable);
		};
	}

	function loadFrames(spr:FlxSprite, image:String, spriteType:String)
	{
		switch (spriteType.toLowerCase().trim())
		{
			case "texture" | "textureatlas" | "tex":
				spr.frames = AtlasFrameMaker.construct(image);

			case "texture_noaa" | "textureatlas_noaa" | "tex_noaa":
				spr.frames = AtlasFrameMaker.construct(image, null, true);

			case "packer" | "packeratlas" | "pac":
				spr.frames = Paths.getPackerAtlas(image);

			default:
				spr.frames = Paths.getSparrowAtlas(image);
		}
	}

	function setGroupStuff(leArray:Dynamic, variable:String, value:Dynamic)
	{
		var killMe:Array<String> = variable.split('.');
		if (killMe.length > 1)
		{
			var coverMeInPiss:Dynamic = Reflect.getProperty(leArray, killMe[0]);
			for (i in 1...killMe.length - 1)
			{
				coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
			}
			Reflect.setProperty(coverMeInPiss, killMe[killMe.length - 1], value);
			return;
		}
		Reflect.setProperty(leArray, variable, value);
	}

	function resetTextTag(tag:String)
	{
		if (!FunkinLua.curInstance.modchartTexts.exists(tag))
		{
			return;
		}

		var pee:ModchartText = FunkinLua.curInstance.modchartTexts.get(tag);
		pee.kill();
		if (pee.wasAdded)
		{
			FunkinLua.curInstance.remove(pee, true);
		}
		pee.destroy();
		FunkinLua.curInstance.modchartTexts.remove(tag);
	}

	function resetSpriteTag(tag:String)
	{
		if (!FunkinLua.curInstance.modchartSprites.exists(tag))
		{
			return;
		}

		var pee:ModchartSprite = FunkinLua.curInstance.modchartSprites.get(tag);
		pee.kill();
		if (pee.wasAdded)
		{
			FunkinLua.curInstance.remove(pee, true);
		}
		pee.destroy();
		FunkinLua.curInstance.modchartSprites.remove(tag);
	}

	function cancelTween(tag:String)
	{
		if (FunkinLua.curInstance.modchartTweens.exists(tag))
		{
			FunkinLua.curInstance.modchartTweens.get(tag).cancel();
			FunkinLua.curInstance.modchartTweens.get(tag).destroy();
			FunkinLua.curInstance.modchartTweens.remove(tag);
		}
	}

	function tweenShit(tag:String, vars:String)
	{
		cancelTween(tag);
		var variables:Array<String> = vars.split('.');
		var sexyProp:Dynamic = getObjectDirectly(variables[0]);
		if (variables.length > 1)
		{
			sexyProp = getVarInArray(getPropertyLoopThingWhatever(variables), variables[variables.length - 1]);
		}
		return sexyProp;
	}

	function cancelTimer(tag:String)
	{
		if (FunkinLua.curInstance.modchartTimers.exists(tag))
		{
			var theTimer:FlxTimer = FunkinLua.curInstance.modchartTimers.get(tag);
			theTimer.cancel();
			theTimer.destroy();
			FunkinLua.curInstance.modchartTimers.remove(tag);
		}
	}

	// Better optimized than using some getProperty shit or idk
	function getFlxEaseByString(?ease:String = '')
	{
		switch (ease.toLowerCase().trim())
		{
			case 'backin':
				return FlxEase.backIn;
			case 'backinout':
				return FlxEase.backInOut;
			case 'backout':
				return FlxEase.backOut;
			case 'bouncein':
				return FlxEase.bounceIn;
			case 'bounceinout':
				return FlxEase.bounceInOut;
			case 'bounceout':
				return FlxEase.bounceOut;
			case 'circin':
				return FlxEase.circIn;
			case 'circinout':
				return FlxEase.circInOut;
			case 'circout':
				return FlxEase.circOut;
			case 'cubein':
				return FlxEase.cubeIn;
			case 'cubeinout':
				return FlxEase.cubeInOut;
			case 'cubeout':
				return FlxEase.cubeOut;
			case 'elasticin':
				return FlxEase.elasticIn;
			case 'elasticinout':
				return FlxEase.elasticInOut;
			case 'elasticout':
				return FlxEase.elasticOut;
			case 'expoin':
				return FlxEase.expoIn;
			case 'expoinout':
				return FlxEase.expoInOut;
			case 'expoout':
				return FlxEase.expoOut;
			case 'quadin':
				return FlxEase.quadIn;
			case 'quadinout':
				return FlxEase.quadInOut;
			case 'quadout':
				return FlxEase.quadOut;
			case 'quartin':
				return FlxEase.quartIn;
			case 'quartinout':
				return FlxEase.quartInOut;
			case 'quartout':
				return FlxEase.quartOut;
			case 'quintin':
				return FlxEase.quintIn;
			case 'quintinout':
				return FlxEase.quintInOut;
			case 'quintout':
				return FlxEase.quintOut;
			case 'sinein':
				return FlxEase.sineIn;
			case 'sineinout':
				return FlxEase.sineInOut;
			case 'sineout':
				return FlxEase.sineOut;
			case 'smoothstepin':
				return FlxEase.smoothStepIn;
			case 'smoothstepinout':
				return FlxEase.smoothStepInOut;
			case 'smoothstepout':
				return FlxEase.smoothStepInOut;
			case 'smootherstepin':
				return FlxEase.smootherStepIn;
			case 'smootherstepinout':
				return FlxEase.smootherStepInOut;
			case 'smootherstepout':
				return FlxEase.smootherStepOut;
		}
		return FlxEase.linear;
	}

	function blendModeFromString(blend:String):BlendMode
	{
		switch (blend.toLowerCase().trim())
		{
			case 'add':
				return ADD;
			case 'alpha':
				return ALPHA;
			case 'darken':
				return DARKEN;
			case 'difference':
				return DIFFERENCE;
			case 'erase':
				return ERASE;
			case 'hardlight':
				return HARDLIGHT;
			case 'invert':
				return INVERT;
			case 'layer':
				return LAYER;
			case 'lighten':
				return LIGHTEN;
			case 'multiply':
				return MULTIPLY;
			case 'overlay':
				return OVERLAY;
			case 'screen':
				return SCREEN;
			case 'shader':
				return SHADER;
			case 'subtract':
				return SUBTRACT;
		}
		return NORMAL;
	}

	function cameraFromString(cam:String):FlxCamera
	{
		switch (cam.toLowerCase())
		{
			case 'camhud' | 'hud':
				return PlayState.instance.camHUD;
			case 'camother' | 'other':
				return PlayState.instance.camOther;
		}
		return PlayState.instance.camGame;
	}

	function cameraToString(cam:String):String
	{ // formats camera to work with the filter function
		switch (cam.toLowerCase())
		{
			case 'camhud' | 'hud':
				return 'camHUD';
			case 'camother' | 'other':
				return 'camOther';
		}
		return 'camGame';
	}

	public function luaTrace(text:String, ignoreCheck:Bool = false, deprecated:Bool = false, color:FlxColor = FlxColor.WHITE)
	{
		#if LUA_ALLOWED
		if (ignoreCheck || getBool('luaDebugMode'))
		{
			if (deprecated && !getBool('luaDeprecatedWarnings'))
			{
				return;
			}
			FunkinLua.curInstance.addTextToDebug(text, color);
			trace(text);
		}
		#end
	}

	function getErrorMessage(status:Int):String
	{
		#if LUA_ALLOWED
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);

		if (v != null)
			v = v.trim();
		if (v == null || v == "")
		{
			switch (status)
			{
				case Lua.LUA_ERRRUN:
					return "Runtime Error";
				case Lua.LUA_ERRMEM:
					return "Memory Allocation Error";
				case Lua.LUA_ERRERR:
					return "Critical Error";
			}
			return "Unknown Error";
		}

		return v;
		#end
		return null;
	}

	var lastCalledFunction:String = '';

	public function call(func:String, args:Array<Dynamic>):Dynamic
	{
		#if LUA_ALLOWED
		if (closed)
			return Function_Continue;

		lastCalledFunction = func;
		try
		{
			if (lua == null)
				return Function_Continue;

			Lua.getglobal(lua, func);
			var type:Int = Lua.type(lua, -1);

			if (type != Lua.LUA_TFUNCTION)
			{
				if (type > Lua.LUA_TNIL)
					luaTrace("ERROR (" + func + "): attempt to call a " + typeToString(type) + " value", false, false, FlxColor.RED);

				Lua.pop(lua, 1);
				return Function_Continue;
			}

			for (arg in args)
				Convert.toLua(lua, arg);
			var status:Int = Lua.pcall(lua, args.length, 1, 0);

			// Checks if it's not successful, then show a error.
			if (status != Lua.LUA_OK)
			{
				var error:String = getErrorMessage(status);
				luaTrace("ERROR (" + func + "): " + error, false, false, FlxColor.RED);
				return Function_Continue;
			}

			// If successful, pass and then return the result.
			var result:Dynamic = cast Convert.fromLua(lua, -1);
			if (result == null)
				result = Function_Continue;

			Lua.pop(lua, 1);
			return result;
		}
		catch (e:Dynamic)
		{
			trace(e);
		}
		#end
		return Function_Continue;
	}

	static function addAnimByIndices(obj:String, name:String, prefix:String, indices:String, framerate:Int = 24, loop:Bool = false)
	{
		var strIndices:Array<String> = indices.trim().split(',');
		var die:Array<Int> = [];
		for (i in 0...strIndices.length)
		{
			die.push(Std.parseInt(strIndices[i]));
		}

		if (FunkinLua.curInstance.getLuaObject(obj, false) != null)
		{
			var pussy:FlxSprite = FunkinLua.curInstance.getLuaObject(obj, false);
			pussy.animation.addByIndices(name, prefix, die, '', framerate, loop);
			if (pussy.animation.curAnim == null)
			{
				pussy.animation.play(name, true);
			}
			return true;
		}

		var pussy:FlxSprite = Reflect.getProperty(getInstance(), obj);
		if (pussy != null)
		{
			pussy.animation.addByIndices(name, prefix, die, '', framerate, loop);
			if (pussy.animation.curAnim == null)
			{
				pussy.animation.play(name, true);
			}
			return true;
		}
		return false;
	}

	public static function getPropertyLoopThingWhatever(killMe:Array<String>, ?checkForTextsToo:Bool = true, ?getProperty:Bool = true):Dynamic
	{
		var coverMeInPiss:Dynamic = getObjectDirectly(killMe[0], checkForTextsToo);
		var end = killMe.length;
		if (getProperty)
			end = killMe.length - 1;

		for (i in 1...end)
		{
			coverMeInPiss = getVarInArray(coverMeInPiss, killMe[i]);
		}
		return coverMeInPiss;
	}

	public static function getObjectDirectly(objectName:String, ?checkForTextsToo:Bool = true):Dynamic
	{
		var coverMeInPiss:Dynamic = FunkinLua.curInstance.getLuaObject(objectName, checkForTextsToo);
		if (coverMeInPiss == null)
			coverMeInPiss = getVarInArray(getInstance(), objectName);

		return coverMeInPiss;
	}

	function typeToString(type:Int):String
	{
		#if LUA_ALLOWED
		switch (type)
		{
			case Lua.LUA_TBOOLEAN:
				return "boolean";
			case Lua.LUA_TNUMBER:
				return "number";
			case Lua.LUA_TSTRING:
				return "string";
			case Lua.LUA_TTABLE:
				return "table";
			case Lua.LUA_TFUNCTION:
				return "function";
		}
		if (type <= Lua.LUA_TNIL)
			return "nil";
		#end
		return "unknown";
	}

	public function set(variable:String, data:Dynamic)
	{
		#if LUA_ALLOWED
		if (lua == null)
		{
			return;
		}

		Convert.toLua(lua, data);
		Lua.setglobal(lua, variable);
		#end
	}

	#if LUA_ALLOWED
	public function getBool(variable:String)
	{
		var result:String = null;
		Lua.getglobal(lua, variable);
		result = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);

		if (result == null)
		{
			return false;
		}
		return (result == 'true');
	}
	#end

	public function stop()
	{
		#if LUA_ALLOWED
		if (lua == null)
		{
			return;
		}

		Lua.close(lua);
		lua = null;
		#end
	}

	public static function getInstance()
	{
		if (CoolUtil.curLuaState == 'playstate')
			return getPlayStateInstance();
		return FunkinLua.curInstance;
	}

	public static function getPlayStateInstance()
	{
		return PlayState.instance.isDead ? GameOverSubstate.instance : PlayState.instance;
	}

	public function addCallback(name:String, func:Dynamic)
	{
		// trace('adding callback', name, func, curLuaState);
		Lua_helper.add_callback(lua, name, func);
		LuaL.dostring(lua, '
		local _old = $name;
		function $name(...)
			if _psych.eventList.$name then
				for i,event in pairs(_psych.eventList.$name) do
					event(...)	
				end
			end
			return _old(...)
		end
		');
	}

	// END OF FUNKINLUA
}

class ModchartSprite extends FlxSprite
{
	public var wasAdded:Bool = false;
	public var animOffsets:Map<String, Array<Float>> = new Map<String, Array<Float>>();

	// public var isInFront:Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);
		antialiasing = ClientPrefs.globalAntialiasing;
	}
}

class ModchartText extends FlxText
{
	public var wasAdded:Bool = false;

	public function new(x:Float, y:Float, text:String, width:Float)
	{
		super(x, y, width, text, 16);
		setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		if (CoolUtil.curLuaState == 'playstate')
			cameras = [PlayState.instance.camHUD];
		scrollFactor.set();
		borderSize = 2;
	}
}

class DebugLuaText extends FlxText
{
	private var disableTime:Float = 6;

	public var parentGroup:FlxTypedGroup<DebugLuaText>;

	public function new(text:String, parentGroup:FlxTypedGroup<DebugLuaText>, color:FlxColor)
	{
		this.parentGroup = parentGroup;
		super(10, 10, 0, text, 16);
		setFormat(Paths.font("vcr.ttf"), 16, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scrollFactor.set();
		borderSize = 1;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		disableTime -= elapsed;
		if (disableTime < 0)
			disableTime = 0;
		if (disableTime < 1)
			alpha = disableTime;
	}
}

class CustomSubstate extends MusicBeatSubstate
{
	public static var name:String = 'unnamed';
	public static var instance:CustomSubstate;

	override function create()
	{
		instance = this;

		FunkinLua.curInstance.callOnLuas('onCustomSubstateCreate', [name]);
		super.create();
		FunkinLua.curInstance.callOnLuas('onCustomSubstateCreatePost', [name]);
	}

	public function new(name:String)
	{
		CustomSubstate.name = name;
		super();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
	}

	override function update(elapsed:Float)
	{
		FunkinLua.curInstance.callOnLuas('onCustomSubstateUpdate', [name, elapsed]);
		super.update(elapsed);
		FunkinLua.curInstance.callOnLuas('onCustomSubstateUpdatePost', [name, elapsed]);
	}

	override function destroy()
	{
		FunkinLua.curInstance.callOnLuas('onCustomSubstateDestroy', [name]);
		super.destroy();
	}
}
