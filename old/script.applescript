-- ============================================================
-- Mod registry
-- ============================================================

set modRegistry to {¬
	{modID:"AdofaiTweaks", modURL:"https://github.com/PizzaLovers007/AdofaiTweaks/releases/latest/download/AdofaiTweaks-2.8.1.zip"}, ¬
	{modID:"TUFHelper", modURL:"https://github.com/coyami-ke/TUFHelper/releases/latest/download/TUFHelper.OSX.zip"}, ¬
	{modID:"JipperResourcePack", modURL:"https://github.com/Jongye0l/JipperResourcePack/releases/latest/download/JipperResourcePack.zip"}, ¬
	{modID:"PACL2", modURL:"https://jalib.jongyeol.kr/downloadMod/PACL2/2.4.205"}, ¬
	{modID:"TogetherBootstrap", modURL:"https://github.com/fangshenghan/TogetherBootstrap-Mod/releases/latest/download/TogetherBootstrap.v1.5.5.zip"}, ¬
	{modID:"YouTubeStream", modURL:"https://fixcdn.hyonsu.com/attachments/886661471533162526/1343622558813130855/YouTubeStream-1.0.3.zip"}, ¬
	{modID:"KeyboardChatterBlocker", modURL:"https://github.com/fangshenghan/KeyboardChatterBlocker/releases/download/0.1.0/KeyboardChatterBlocker.v0.1.0.zip"}, ¬
	{modID:"EnhancedEffectRemover", modURL:"https://github.com/WsbiMango/EnhancedEffectRemover/releases/download/1.7.0/EnhancedEffectRemover_1.7.0.zip"}, ¬
	{modID:"XPerfect", modURL:"https://github.com/8100print/XPerfect/releases/latest/download/XPerfect.zip"}, ¬
	{modID:"DesyncFix", modURL:"https://fixcdn.hyonsu.com/attachments/886661471533162526/1045847555440910406/DesyncFix-0.0.6.zip"} ¬
}

-- ============================================================
-- Paths
-- ============================================================
set htmlPath to "/tmp/gui.html"
set jxaPath to "/tmp/gui.jxa"
set selResultPath to "/tmp/installer_result.txt"
set progressHTMLPath to "/tmp/progress.html"
set progressJXAPath to "/tmp/progress.jxa"
set progressLogPath to "/tmp/installer_progress.log"
set progressResultPath to "/tmp/installer_progress_result.txt"
set baseURL to "https://raw.githubusercontent.com/sbrothers7/scripts/main/UMMInstall/"
set curlUA to "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

-- Kill any leftover UI from a previous crashed run
do shell script "pkill -f 'osascript -l JavaScript /tmp/gui.jxa' 2>/dev/null; pkill -f 'osascript -l JavaScript /tmp/progress.jxa' 2>/dev/null; true"
do shell script "rm -f " & quoted form of progressLogPath & " " & quoted form of progressResultPath

-- Download icon
do shell script "curl -fsL -o /tmp/icon.png 'https://raw.githubusercontent.com/sbrothers7/scripts/main/UMMInstall/icon.png'"

-- ============================================================
-- Upfront confirmation
-- ============================================================
set gamePlistPath to (POSIX path of (path to home folder)) & "Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app/Contents/Info.plist"
try
	set gameVersion to do shell script "/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' " & quoted form of gamePlistPath
on error
	set gameVersion to ""
end try
if gameVersion starts with "2." then
	set confirmText to "Detected ADOFAI " & gameVersion & " (Unity 2022 build)." & return & return & "This script will install:" & return & "  - Homebrew (if not installed)" & return & "  - mono, expect, wget (if not installed)" & return & return & "On Apple Silicon, the arm64 slice of the game binary will be stripped so Steam launches under Rosetta (required for Harmony JIT patching on this build)." & return & return & "Do you still wish to proceed?"
else
	if gameVersion is "" then
		set versionLine to "ADOFAI version not detected — defaulting to native installer."
	else
		set versionLine to "Detected ADOFAI " & gameVersion & " — using the native installer."
	end if
	set confirmText to versionLine & return & return & "This script will install:" & return & "  - Homebrew (if not installed)" & return & "  - git, .NET SDK (if not installed)" & return & return & "The native MacTuiInstaller from kkorenn/unity-mod-manager will be fetched and built, then run to patch the game." & return & return & "Do you still wish to proceed?"
end if

tell application "System Events"
	activate
	set confirmResponse to display dialog confirmText buttons {"Cancel", "Proceed"} default button "Proceed" with icon file (POSIX file "/tmp/icon.png" as alias) with title "ADOFAI Mod Manager Installer"
end tell
if button returned of confirmResponse is "Cancel" then return

set modNames to {}
repeat with m in modRegistry
	set end of modNames to modID of m
end repeat

set modNamesCSV to ""
repeat with i from 1 to count of modNames
	set modNamesCSV to modNamesCSV & item i of modNames
	if i < (count of modNames) then set modNamesCSV to modNamesCSV & ","
end repeat

-- ============================================================
-- Download UI assets
-- ============================================================
try
	do shell script "curl -sfL -A " & quoted form of curlUA & " " & quoted form of (baseURL & "gui.html") & " -o " & quoted form of htmlPath
	do shell script "curl -sfL -A " & quoted form of curlUA & " " & quoted form of (baseURL & "gui.jxa") & " -o " & quoted form of jxaPath
	do shell script "curl -sfL -A " & quoted form of curlUA & " " & quoted form of (baseURL & "progress.html") & " -o " & quoted form of progressHTMLPath
	do shell script "curl -sfL -A " & quoted form of curlUA & " " & quoted form of (baseURL & "progress.jxa") & " -o " & quoted form of progressJXAPath
on error errMsg
	display dialog "❌ Failed to download UI files." & return & return & errMsg buttons {"OK"} with icon stop with title "ADOFAI Mod Manager Installer"
	return
end try

-- Inject the mod list into the HTML template
do shell script "MODS=" & quoted form of modNamesCSV & " /usr/bin/python3 -c \"" & ¬
	"import os, pathlib; " & ¬
	"mods = os.environ['MODS'].split(','); " & ¬
	"js = ','.join([repr(m) for m in mods]); " & ¬
	"p = pathlib.Path('/tmp/gui.html'); " & ¬
	"p.write_text(p.read_text().replace('%%MOD_LIST%%', js))\""

do shell script "rm -f " & quoted form of selResultPath

-- ============================================================
-- Mod selection UI
-- ============================================================
do shell script "osascript -l JavaScript " & quoted form of jxaPath
set userResult to do shell script "cat " & quoted form of selResultPath & " 2>/dev/null || echo 'CANCEL'"
do shell script "rm -f " & quoted form of htmlPath & " " & quoted form of jxaPath & " " & quoted form of selResultPath

if userResult is "CANCEL" then return

if userResult is "SKIP" then
	set selectedMods to {}
else if userResult starts with "INSTALL:" then
	set AppleScript's text item delimiters to ":"
	set afterPrefix to text item 2 of userResult
	set AppleScript's text item delimiters to ","
	set selectedMods to text items of afterPrefix
	set AppleScript's text item delimiters to ""
else
	return
end if

-- ============================================================
-- Launch progress window in the background
-- ============================================================
do shell script ": > " & quoted form of progressLogPath
do shell script "rm -f " & quoted form of progressResultPath
do shell script "nohup osascript -l JavaScript " & quoted form of progressJXAPath & " >/dev/null 2>&1 &"

-- ============================================================
-- Run installer
-- ============================================================
set scriptPath to (POSIX path of (path to home folder)) & ".adofai-umm.sh"

my plog("info", "Downloading installer…")
try
	do shell script "curl -sfL -A " & quoted form of curlUA & " " & quoted form of (baseURL & "adofai-umm.sh") & " -o " & quoted form of scriptPath
on error errMsg
	my plog("error", "Failed to download installer script.")
	my plogDetail(errMsg)
	my pfail("Installation failed.")
	my waitForClose()
	return
end try

my plog("info", "Installing Unity Mod Manager (this may take a few minutes)…")
try
	do shell script "script -q /dev/null /bin/zsh " & quoted form of scriptPath & " >> " & quoted form of progressLogPath & " 2>&1"
on error errMsg
	my plog("error", "Unity Mod Manager installation failed.")
	my plogDetail(errMsg)
	my pfail("Installation failed.")
	my waitForClose()
	return
end try
my plog("ok", "Unity Mod Manager installed.")

try
	do shell script "rm -f " & quoted form of scriptPath
end try

-- ============================================================
-- Download mods
-- ============================================================
set modsPath to (POSIX path of (path to home folder)) & "Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/Mods"
do shell script "mkdir -p " & quoted form of modsPath

set installedMods to {}
set failedMods to {}

if (count of selectedMods) > 0 then
	set totalMods to count of selectedMods

	repeat with i from 1 to totalMods
		set modName to item i of selectedMods
		set modURL to ""

		repeat with m in modRegistry
			if modID of m is modName then
				set modURL to modURL of m
				exit repeat
			end if
		end repeat

		if modURL is not "" then
			if modURL starts with "GITHUB_API:" then
				set repoSlug to text 12 thru -1 of modURL
				try
					set modURL to do shell script "curl -sfL -A " & quoted form of curlUA & " 'https://api.github.com/repos/" & repoSlug & "/releases/latest' | /usr/bin/python3 -c \"import sys,json; assets=json.load(sys.stdin).get('assets',[]); zips=[a['browser_download_url'] for a in assets if a['name'].endswith('.zip')]; print(zips[0]) if zips else sys.exit(1)\""
				on error
					set modURL to ""
				end try
			end if

			if modURL is "" then
				my plog("error", "Could not resolve URL for " & modName)
				set end of failedMods to modName
			else
				my plog("info", "Downloading " & modName & " (" & i & "/" & totalMods & ")…")

				set tmpZip to "/tmp/adofai_mod_" & modName & ".zip"
				set tmpExtract to "/tmp/adofai_extract_" & modName
				try
					if modURL contains "fixcdn.hyonsu.com" then
						do shell script "wget --user-agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' -O " & quoted form of tmpZip & " " & quoted form of modURL
					else
						do shell script "curl -sfL " & quoted form of modURL & " -o " & quoted form of tmpZip
					end if
					do shell script "rm -rf " & quoted form of tmpExtract & " && mkdir -p " & quoted form of tmpExtract
					do shell script "unzip -q -o " & quoted form of tmpZip & " -d " & quoted form of tmpExtract
					do shell script "cd " & quoted form of tmpExtract & " && " & ¬
						"items=$(ls -1) && count=$(echo \"$items\" | wc -l | tr -d ' ') && " & ¬
						"first=$(echo \"$items\" | head -1) && " & ¬
						"if [ \"$count\" -eq 1 ] && [ -d \"$first\" ]; then " & ¬
						"  rm -rf " & quoted form of modsPath & "/\"$first\" && " & ¬
						"  mv \"$first\" " & quoted form of modsPath & "/; " & ¬
						"else " & ¬
						"  rm -rf " & quoted form of modsPath & "/" & quoted form of modName & " && " & ¬
						"  mkdir -p " & quoted form of modsPath & "/" & quoted form of modName & " && " & ¬
						"  mv * " & quoted form of modsPath & "/" & quoted form of modName & "/; " & ¬
						"fi"

					do shell script "rm -rf " & quoted form of tmpExtract & " " & quoted form of tmpZip
					my plog("ok", modName & " installed.")
					set end of installedMods to modName
				on error errMsg
					do shell script "rm -rf " & quoted form of tmpExtract & " " & quoted form of tmpZip
					my plog("error", modName & " failed to install.")
					my plogDetail(errMsg)
					set end of failedMods to modName
				end try
			end if
		end if
	end repeat
end if

-- ============================================================
-- Summary
-- ============================================================
if (count of failedMods) > 0 then
	my pcomplete("Installation finished with errors.")
else
	my pcomplete("Installation complete.")
end if

display notification "Installation complete!" with title "ADOFAI Mod Manager"
my waitForClose()


-- ============================================================
-- Helpers
-- ============================================================
on plog(level, message)
	set logPath to "/tmp/installer_progress.log"
	do shell script "printf '%s\\n' " & quoted form of (level & ":" & message) & " >> " & quoted form of logPath
end plog

on plogDetail(detailText)
	set logPath to "/tmp/installer_progress.log"
	set AppleScript's text item delimiters to {return, linefeed}
	set lines to text items of detailText
	set AppleScript's text item delimiters to ""
	repeat with ln in lines
		set s to contents of ln
		if s is not "" then
			do shell script "printf '%s\\n' " & quoted form of ("detail:" & s) & " >> " & quoted form of logPath
		end if
	end repeat
end plogDetail

on pcomplete(msg)
	set logPath to "/tmp/installer_progress.log"
	do shell script "printf '%s\\n' " & quoted form of ("complete:" & msg) & " >> " & quoted form of logPath
end pcomplete

on pfail(msg)
	set logPath to "/tmp/installer_progress.log"
	do shell script "printf '%s\\n' " & quoted form of ("failed:" & msg) & " >> " & quoted form of logPath
end pfail

on waitForClose()
	set resultPath to "/tmp/installer_progress_result.txt"
	do shell script "while [ ! -f " & quoted form of resultPath & " ]; do sleep 0.3; done"
	do shell script "rm -f /tmp/progress.html /tmp/progress.jxa " & quoted form of resultPath & " /tmp/installer_progress.log"
end waitForClose
