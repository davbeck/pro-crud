-- Contributor helper: English ProPresenter 21.4 (352583705), on a test guest.
-- Run through SSH as the same user who owns the logged-in graphical session.
on run argv
    set waitSeconds to 0
    if (count of argv) > 1 then error "Usage: dismiss-login.applescript [wait-seconds]"
    if (count of argv) is 1 then set waitSeconds to item 1 of argv as integer
    if waitSeconds < 0 or waitSeconds > 60 then error "wait-seconds must be between 0 and 60."
    set installedVersion to do shell script "/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' /Applications/ProPresenter.app/Contents/Info.plist"
    if installedVersion is not "352583705" then error "This activation-sheet selector is verified only for ProPresenter 21.4 build 352583705."
    tell application "System Events"
        if not (exists application process "ProPresenter") then error "ProPresenter is not running."
        tell application process "ProPresenter"
            if (count of windows) is 0 then error "ProPresenter has no accessible windows yet."
            set deadline to (current date) + waitSeconds
            repeat until exists sheet 1 of window 1
                if (current date) ≥ deadline then return "not-present"
                delay 0.25
            end repeat
            set activationGroup to group 1 of sheet 1 of window 1
            if not (exists static text "Activate ProPresenter" of activationGroup) then error "Unexpected sheet; no button was clicked."
            if not (exists static text "Sign into your Renewed Vision account to get started with ProPresenter and ProContent." of activationGroup) then error "Unexpected activation text; no button was clicked."
            if (count of buttons of activationGroup) is not 4 then error "Unexpected activation buttons; no button was clicked."
            -- This build leaves button titles empty in AX. Screenshot + AX geometry
            -- identify button 4 as Skip for Now, after Help, Sign Up, and Sign In.
            click button 4 of activationGroup
            repeat 60 times
                if not (exists sheet 1 of window 1) then return "dismissed"
                delay 0.25
            end repeat
            error "The activation sheet remained after clicking Skip for Now."
        end tell
    end tell
end run
