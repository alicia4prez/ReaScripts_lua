-- @description Digital Audio PCM Fingerprint (SHA-256 / MD5)
-- @version 1.2.0
-- @author Rea & ALiXiA
-- @about
--   Generates cryptographic SHA-256 and MD5 signatures from raw PCM audio,
--   writes the hash to item notes, and drops a take marker at position 0:00.

-- 1. Validate selection
local item = reaper.GetSelectedMediaItem(0, 0)
if not item then 
    reaper.ShowMessageBox("Please select an audio item first.", "PCM Fingerprint", 0) 
    return 
end

local take = reaper.GetActiveTake(item)
if not take or reaper.TakeIsMIDI(take) then 
    reaper.ShowMessageBox("Selected item does not contain a valid audio take.", "PCM Fingerprint", 0)
    return 
end

local source = reaper.GetMediaItemTake_Source(take)
local file_path = reaper.GetMediaSourceFileName(source, "")
if file_path == "" then
    reaper.ShowMessageBox("Could not resolve source audio path.", "PCM Fingerprint", 0)
    return
end

-- 2. Build shell command
local python_bin = "python"
local script_path = reaper.GetResourcePath() .. "/Scripts/dsp_worker.py"
local cmd = string.format('"%s" "%s" "%s"', python_bin, script_path, file_path)

-- 3. Execute external worker
local output = reaper.ExecProcess(cmd, 5000)
if not output or output == "" then
    reaper.ShowConsoleMsg("Error: Python worker timed out or produced no output.\n")
    return
end

-- 4. Parse hash
local sha256 = output:match('"pcm_sha256":%s*"([%x]+)"')
local md5 = output:match('"pcm_md5":%s*"([%x]+)"')

if not sha256 then
    reaper.ShowConsoleMsg("Failed to parse fingerprint from Python output:\n" .. output .. "\n")
    return
end

-- 5. Write to Item Notes & Take Marker
reaper.Undo_BeginBlock()

-- Write Item Notes
local _, current_notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
local timestamp = os.date("%Y-%m-%d %H:%M:%S")
local entry = string.format("[PCM Fingerprint | %s]\nSHA-256: %s\nMD5:     %s", timestamp, sha256, md5 or "N/A")

local updated_notes
if current_notes and current_notes:gsub("%s+", "") ~= "" then
    updated_notes = current_notes .. "\n\n" .. entry
else
    updated_notes = entry
end
reaper.GetSetMediaItemInfo_String(item, "P_NOTES", updated_notes, true)

-- Add Take Marker at 0:00 (source time 0.0)
local marker_name = "SHA-256: " .. sha256:sub(1, 12) .. "..." -- Compact 12-char label for timeline readability
reaper.SetTakeMarker(take, -1, marker_name, 0.0)

-- Redraw arrange view
reaper.UpdateItemInProject(item)
reaper.Undo_EndBlock("Add PCM Fingerprint Note and Take Marker", -1)

reaper.ShowConsoleMsg(string.format("Fingerprint complete.\nSHA-256: %s\nTake marker placed at 0:00.\n", sha256))
