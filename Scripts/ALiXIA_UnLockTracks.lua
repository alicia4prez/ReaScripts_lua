-- @description ALiXiA Unlock Tracks (companion to ALiXiA Lock Tracks)
-- @author ALiXiA & Rea - The Reaper Queens of EDM
-- @version 1.0.2
-- @donation https://www.paypal.com/donate/?hosted_button_id=GXEUXZN7GD7W4
-- @link Repository https://github.com/alicia4prez/ReaScripts_lua
-- @about
--   Companion to Track Lock script. This one unloacks the folders. 

local ext_section = "Rea_TrackHierarchyLock"
reaper.SetExtState(ext_section, "running", "0", false)

-- Refresh all toolbars so active toggle buttons turn off
for section = 0, 16 do
    reaper.RefreshToolbar2(section, 0)
end
