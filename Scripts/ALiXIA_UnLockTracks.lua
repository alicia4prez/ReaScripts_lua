-- @description Unlock Track Hierarchy and Order
-- @author ALiXiA
-- @version 1.0.0
-- @donation https://www.paypal.com/donate/?hosted_button_id=GXEUXZN7GD7W4
-- @about
--   Companion to Track Lock script. This one unloacks the folders. 

local ext_section = "Rea_TrackHierarchyLock"
reaper.SetExtState(ext_section, "running", "0", false)

-- Refresh all toolbars so active toggle buttons turn off
for section = 0, 16 do
    reaper.RefreshToolbar2(section, 0)
end
