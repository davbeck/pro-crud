-- Read the front ProPresenter window only. The complete main-window tree can be large.
tell application "System Events"
    if not (exists application process "ProPresenter") then error "ProPresenter is not running."
    tell application process "ProPresenter"
        if (count of windows) is 0 then error "ProPresenter has no accessible windows yet."
        return entire contents of window 1
    end tell
end tell
