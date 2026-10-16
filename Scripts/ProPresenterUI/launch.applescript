-- Launch the pinned guest app and wait for an accessible window. Then run dismiss-login.
set installedBuild to do shell script "/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' /Applications/ProPresenter.app/Contents/Info.plist"
if installedBuild is not "352583705" then error "Expected guest ProPresenter 21.4 build 352583705."
do shell script "/usr/bin/open /Applications/ProPresenter.app"
tell application "System Events"
    repeat 120 times
        if exists application process "ProPresenter" then
            tell application process "ProPresenter"
                if (count of windows) > 0 and (exists menu bar 1) then return "window-ready"
            end tell
        end if
        delay 0.5
    end repeat
end tell
error "ProPresenter did not expose a window within 60 seconds."
