-- @description Digital Fingerprint
-- @author ALiXiA
-- @version 1.0
-- @about
--   Prepares a session for mixing by organizing tracks, 
--   color-coding, and resetting faders.
-- @changelog
--   - Initial release

-- ============================================================================
-- REAPER Digital Fingerprint Embedder (Lua)
-- ============================================================================

local reaper = reaper

-- Function to generate a unique fingerprint string
local function generateFingerprint(owner_name)
  local time_stamp = os.date("%Y-%m-%d %H:%M:%S")
  local random_hash = string.format("%08X%08X", math.random(0, 0x7FFFFFFF), math.random(0, 0x7FFFFFFF))
  return string.format("FINGERPRINT|Owner:%s|Date:%s|ID:%s", owner_name, time_stamp, random_hash)
end

local function embedFingerprint()
  -- Prompt user for owner/artist identifier
  local retval, owner_input = reaper.GetUserInputs("Embed Fingerprint", 1, "Owner/Artist Name or ID:", "Producer_ID_001")
  if not retval or owner_input == "" then return end

  local count_selected_tracks = reaper.CountSelectedTracks(0)
  if count_selected_tracks == 0 then
    reaper.ShowMessageBox("Please select at least one track.", "No Track Selected", 0)
    return
  end

  reaper.Undo_BeginBlock()

  local item_count = 0
  for t = 0, count_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, t)
    local num_items = reaper.CountTrackMediaItems(track)

    for i = 0, num_items - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local take = reaper.GetActiveTake(item)

      if take then
        local fingerprint = generateFingerprint(owner_input)

        -- 1. Embed fingerprint into Take Notes (viewable in REAPER item properties)
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NOTES", fingerprint, true)

        -- 2. Embed into Take User Metadata / BWF Description field
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "[" .. owner_input .. "] " .. reaper.GetTakeName(take), true)

        item_count = item_count + 1
      end
    end
  end

  reaper.Undo_EndBlock("Embed Digital Fingerprint", -1)
  reaper.UpdateArrange()

  reaper.ShowMessageBox(string.format("Embedded digital fingerprint across %d item(s).", item_count), "Success", 0)
end

embedFingerprint()
