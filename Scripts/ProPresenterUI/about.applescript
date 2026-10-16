-- Open/read About; pass "close" to close the verified About window instead.
on findAboutWindow()
    tell application "System Events"
        tell application process "ProPresenter"
            repeat with windowIndex from 1 to count of windows
                if exists checkbox "Acknowledgments" of window windowIndex then return window windowIndex
            end repeat
        end tell
    end tell
    return missing value
end findAboutWindow

on run argv
    set shouldClose to argv is {"close"}
    if argv is not {} and not shouldClose then error "Usage: about.applescript [close]"
    tell application "System Events"
        if not (exists application process "ProPresenter") then error "ProPresenter is not running."
        tell application process "ProPresenter"
            if not shouldClose and my findAboutWindow() is missing value then
                set frontmost to true
                click menu item "About ProPresenter" of menu 1 of menu bar item "ProPresenter" of menu bar 1
            end if
        end tell
    end tell
    repeat 60 times
        set aboutWindow to my findAboutWindow()
        if aboutWindow is not missing value then
            tell application "System Events"
                set versionText to value of static text 2 of aboutWindow
                if versionText does not start with "Version " then error "Unexpected About window."
                if shouldClose then click (first button of aboutWindow whose subrole is "AXCloseButton")
            end tell
            if not shouldClose then return versionText
            repeat 60 times
                if my findAboutWindow() is missing value then return "closed " & versionText
                delay 0.25
            end repeat
            error "About window did not close."
        end if
        delay 0.25
    end repeat
    error "No verified About window appeared."
end run
