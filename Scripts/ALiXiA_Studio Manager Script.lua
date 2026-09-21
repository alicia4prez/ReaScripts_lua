-- @description REA Studio Manager (Project, Track, & Time Tracker) v2.7 FIXED
-- @author REA the Reaper Queen
-- @version 2.7
-- Requires: ReaImGui extension

local r = reaper

if not r.ImGui_GetVersion then
    r.MB("This script requires the ReaImGui extension. Please install it via ReaPack.", "Missing Dependency", 0)
    return
end

local ctx = r.ImGui_CreateContext('REA Studio Manager v2.7')

-- PROJECT FIELDS
local proj_fields = {
    { id = "client", label = "Client / Artist", val = "" },
    { id = "track", label = "Track Title", val = "" },
    { id = "key_bpm", label = "Key & BPM", val = "" },
    { id = "mix_status", label = "Mix Status", val = "" },
    { id = "deliverables", label = "Deliverables", val = "" },
    { id = "revision_notes", label = "Revision Notes", val = "" },
    { id = "contact_info", label = "Client Contact", val = "" },
    { id = "notes", label = "Project Notes", val = "" }
}

for _, f in ipairs(proj_fields) do
    local rv, saved_val = r.GetProjExtState(0, "REA_TRACKER", f.id)
    if rv == 1 then f.val = saved_val end
end

-- TRACK FIELDS
local track_fields = {
    { id = "role", label = "Track Role", val = "" },
    { id = "fx_notes", label = "Processing Notes", val = "" },
    { id = "routing", label = "Routing Info", val = "" }
}

local current_track = nil
local current_track_guid = ""
local current_track_media = ""

local function load_track_data(tr)
    for _, f in ipairs(track_fields) do
        local rv, saved_val = r.GetSetMediaTrackInfo_String(tr, "P_EXT:REA_TRACKER:"..f.id, "", false)
        f.val = rv and saved_val or ""
    end
end

local function save_track_data(tr, id, val)
    r.GetSetMediaTrackInfo_String(tr, "P_EXT:REA_TRACKER:"..id, val, true)
    r.MarkProjectDirty(0)
end

local function get_track_media_files(tr)
    local unique_files = {}
    local files = {}
    local num_items = r.CountTrackMediaItems(tr)
    
    for i = 0, num_items - 1 do
        local item = r.GetTrackMediaItem(tr, i)
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then
            local source = r.GetMediaItemTake_Source(take)
            if source then
                local filename = r.GetMediaSourceFileName(source)
                if filename and type(filename) == "string" and filename ~= "" then
                    local name_only = filename:match("([^/\\]+)$") or filename
                    if not unique_files[name_only] then
                        unique_files[name_only] = true
                        table.insert(files, name_only)
                    end
                end
            end
        end
    end
    
    if #files == 0 then return "No audio files detected on this track." end
    return table.concat(files, "\n")
end

-- TIME LOG
local time_log = {}
local timer_running = false
local timer_session_start = 0
local timer_display = "00:00:00"

local function time_string_to_minutes(time_str)
    local h, m, s = time_str:match("(%d+):(%d+):(%d+)")
    if h and m and s then
        return tonumber(h) * 60 + tonumber(m) + tonumber(s) / 60
    end
    return 0
end

local function minutes_to_time_string(minutes)
    local h = math.floor(minutes / 60)
    local m = math.floor(minutes % 60)
    local s = math.floor((minutes % 1) * 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function calculate_duration(start_str, end_str)
    local start_m = time_string_to_minutes(start_str)
    local end_m = time_string_to_minutes(end_str)
    if end_m >= start_m then
        return end_m - start_m
    end
    return 0
end

local function calculate_session_totals()
    local total_minutes = 0
    local session_count = 0
    
    for _, entry in ipairs(time_log) do
        if entry.start_t ~= "" and entry.end_t ~= "" then
            total_minutes = total_minutes + calculate_duration(entry.start_t, entry.end_t)
            session_count = session_count + 1
        end
    end
    
    local avg_minutes = session_count > 0 and (total_minutes / session_count) or 0
    
    return {
        total_hours = total_minutes / 60,
        total_minutes = total_minutes,
        session_count = session_count,
        avg_minutes = avg_minutes
    }
end

local function save_time_log()
    local str = ""
    for _, entry in ipairs(time_log) do
        str = str .. (entry.date or "") .. "|" .. (entry.start_t or "") .. "|" .. (entry.end_t or "") .. ";"
    end
    r.SetProjExtState(0, "REA_TRACKER", "time_log", str)
    r.MarkProjectDirty(0)
end

local function load_time_log()
    local rv, str = r.GetProjExtState(0, "REA_TRACKER", "time_log")
    if rv == 1 and str ~= "" then
        for entry_str in str:gmatch("([^;]+)") do
            local d, s, e = entry_str:match("([^|]*)|([^|]*)|([^|]*)")
            table.insert(time_log, {date = d or "", start_t = s or "", end_t = e or ""})
        end
    end
    if #time_log == 0 then table.insert(time_log, {date = "", start_t = "", end_t = ""}) end
end

load_time_log()

-- QUICK NOTE TEMPLATES
local note_templates = {
    "Mixed drums - EQ and compression",
    "Processed vocals - reverb and delay",
    "Balanced bass and kick - sidechain ducking",
    "Added parallel compression to drums",
    "Automated volume rides on lead vocal",
    "Grouped instruments - applied glue",
    "Reference checked on multiple speakers",
    "Made revisions per client feedback",
    "Prepared stems for mastering",
    "Final mix export - ready for mastering"
}

-- CSV EXPORT
local function export_time_log_csv()
    local client = proj_fields[1].val or "Unknown"
    local track = proj_fields[2].val or "Unknown"
    
    local csv_content = "Date,Start Time,End Time,Duration (Hours),Notes\n"
    
    for _, entry in ipairs(time_log) do
        if entry.start_t ~= "" and entry.end_t ~= "" then
            local duration_min = calculate_duration(entry.start_t, entry.end_t)
            local duration_h = duration_min / 60
            csv_content = csv_content .. string.format(
                "%s,%s,%s,%.2f,Session\n",
                entry.date or "",
                entry.start_t or "",
                entry.end_t or "",
                duration_h
            )
        end
    end
    
    local totals = calculate_session_totals()
    csv_content = csv_content .. "\nSUMMARY\n"
    csv_content = csv_content .. string.format("Total Hours,%.2f\n", totals.total_hours)
    csv_content = csv_content .. string.format("Total Sessions,%d\n", totals.session_count)
    csv_content = csv_content .. string.format("Average Session,%.2f hours\n", totals.avg_minutes / 60)
    
    local _, proj_name = r.GetProjName(0, "")
    local filename = proj_name:gsub(".rpp", "") .. " - Time Log.csv"
    local filepath = r.GetProjectPath(0) .. "/" .. filename
    
    local f = io.open(filepath, "w")
    if f then
        f:write(csv_content)
        f:close()
        r.MB("Time log exported to:\n" .. filepath, "Export Successful", 0)
    else
        r.MB("Failed to export. Check write permissions.", "Export Error", 0)
    end
end

-- MAIN UI LOOP
local function frame()
    local visible, open = r.ImGui_Begin(ctx, 'REA Studio Manager v2.7', true)
    
    if visible then
        -- PROJECT METADATA
        if r.ImGui_CollapsingHeader(ctx, "Project Metadata", r.ImGui_TreeNodeFlags_DefaultOpen()) then
            if r.ImGui_BeginTable(ctx, 'proj_table', 2, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
                r.ImGui_TableSetupColumn(ctx, 'Field', r.ImGui_TableColumnFlags_WidthFixed(), 120)
                r.ImGui_TableSetupColumn(ctx, 'Data', r.ImGui_TableColumnFlags_WidthStretch())
                
                for _, f in ipairs(proj_fields) do
                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableSetColumnIndex(ctx, 0)
                    r.ImGui_AlignTextToFramePadding(ctx)
                    r.ImGui_Text(ctx, f.label)
                    
                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    local changed, new_val = r.ImGui_InputText(ctx, '##proj'..f.id, f.val)
                    if changed then
                        f.val = new_val
                        r.SetProjExtState(0, "REA_TRACKER", f.id, new_val)
                        r.MarkProjectDirty(0)
                    end
                end
                r.ImGui_EndTable(ctx)
            end
        end
        
        r.ImGui_Spacing(ctx)
        
        -- TRACK DATA
        if r.ImGui_CollapsingHeader(ctx, "Selected Track Data", r.ImGui_TreeNodeFlags_DefaultOpen()) then
            local sel_tr = r.GetSelectedTrack(0, 0)
            
            if sel_tr then
                local guid = r.GetTrackGUID(sel_tr)
                if guid ~= current_track_guid then
                    current_track = sel_tr
                    current_track_guid = guid
                    load_track_data(sel_tr)
                    current_track_media = get_track_media_files(sel_tr)
                end
                
                local _, tr_name = r.GetSetMediaTrackInfo_String(sel_tr, "P_NAME", "", false)
                if tr_name == "" then 
                    tr_name = "Track " .. tostring(r.GetMediaTrackInfo_Value(sel_tr, "IP_TRACKNUMBER")) 
                end
                r.ImGui_TextDisabled(ctx, "Editing: " .. tr_name)
                
                if r.ImGui_BeginTable(ctx, 'track_table', 2, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
                    r.ImGui_TableSetupColumn(ctx, 'Field', r.ImGui_TableColumnFlags_WidthFixed(), 120)
                    r.ImGui_TableSetupColumn(ctx, 'Data', r.ImGui_TableColumnFlags_WidthStretch())
                    
                    for _, f in ipairs(track_fields) do
                        r.ImGui_TableNextRow(ctx)
                        r.ImGui_TableSetColumnIndex(ctx, 0)
                        r.ImGui_AlignTextToFramePadding(ctx)
                        r.ImGui_Text(ctx, f.label)
                        
                        r.ImGui_TableSetColumnIndex(ctx, 1)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local changed, new_val = r.ImGui_InputText(ctx, '##trk'..f.id, f.val)
                        if changed then
                            f.val = new_val
                            save_track_data(sel_tr, f.id, new_val)
                        end
                    end
                    r.ImGui_EndTable(ctx)
                end
                
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, "Auto-Detected Media Files:")
                r.ImGui_InputTextMultiline(ctx, '##trk_media', current_track_media, -1, 80, r.ImGui_InputTextFlags_ReadOnly())
            else
                r.ImGui_Text(ctx, "No track selected.")
                current_track = nil
                current_track_guid = ""
                current_track_media = ""
            end
        end
        
        r.ImGui_Spacing(ctx)
        
        -- QUICK NOTES
        if r.ImGui_CollapsingHeader(ctx, "Quick Note Templates", r.ImGui_TreeNodeFlags_DefaultOpen()) then
            r.ImGui_TextDisabled(ctx, "Click to add to Project Notes:")
            for _, template in ipairs(note_templates) do
                if r.ImGui_SmallButton(ctx, template) then
                    proj_fields[8].val = (proj_fields[8].val ~= "" and proj_fields[8].val .. "\n" or "") .. os.date("%H:%M") .. " - " .. template
                    r.SetProjExtState(0, "REA_TRACKER", "notes", proj_fields[8].val)
                    r.MarkProjectDirty(0)
                end
            end
        end
        
        r.ImGui_Spacing(ctx)
        
        -- TIME LOG
        if r.ImGui_CollapsingHeader(ctx, "Time & Billing Log", r.ImGui_TreeNodeFlags_DefaultOpen()) then
            
            r.ImGui_Text(ctx, "Quick Session Timer:")
            r.ImGui_SameLine(ctx)
            r.ImGui_TextColored(ctx, 0xFF00FF00, timer_display)
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, timer_running and "Stop Timer" or "Start Timer") then
                timer_running = not timer_running
                if timer_running then
                    timer_session_start = os.time()
                end
            end
            
            if timer_running then
                local elapsed = os.difftime(os.time(), timer_session_start)
                timer_display = minutes_to_time_string(elapsed / 60)
            end
            
            r.ImGui_Spacing(ctx)
            
            if r.ImGui_BeginTable(ctx, 'time_table', 5, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
                r.ImGui_TableSetupColumn(ctx, 'Date', r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, 'Start', r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, 'End', r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, 'Duration', r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, 'X', r.ImGui_TableColumnFlags_WidthFixed(), 25)
                r.ImGui_TableHeadersRow(ctx)
                
                local row_to_remove = nil
                
                for i, entry in ipairs(time_log) do
                    r.ImGui_TableNextRow(ctx)
                    
                    r.ImGui_TableSetColumnIndex(ctx, 0)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    local c1, d_val = r.ImGui_InputText(ctx, '##d'..i, entry.date)
                    
                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    local c2, s_val = r.ImGui_InputText(ctx, '##s'..i, entry.start_t)
                    
                    r.ImGui_TableSetColumnIndex(ctx, 2)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    local c3, e_val = r.ImGui_InputText(ctx, '##e'..i, entry.end_t)
                    
                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    local duration_str = ""
                    if s_val ~= "" and e_val ~= "" then
                        local dur_min = calculate_duration(s_val, e_val)
                        duration_str = string.format("%.2f h", dur_min / 60)
                    end
                    r.ImGui_AlignTextToFramePadding(ctx)
                    r.ImGui_Text(ctx, duration_str)
                    
                    if c1 or c2 or c3 then
                        entry.date = d_val
                        entry.start_t = s_val
                        entry.end_t = e_val
                        save_time_log()
                    end
                    
                    r.ImGui_TableSetColumnIndex(ctx, 4)
                    if r.ImGui_Button(ctx, 'X##'..i) then
                        row_to_remove = i
                    end
                end
                
                if row_to_remove then
                    table.remove(time_log, row_to_remove)
                    if #time_log == 0 then table.insert(time_log, {date = "", start_t = "", end_t = ""}) end
                    save_time_log()
                end
                
                r.ImGui_EndTable(ctx)
            end
            
            r.ImGui_Spacing(ctx)
            
            if r.ImGui_Button(ctx, "Add Session Row") then
                table.insert(time_log, {date = os.date("%Y-%m-%d"), start_t = "", end_t = ""})
                save_time_log()
            end
        end
        
        r.ImGui_Spacing(ctx)
        
        -- SESSION SUMMARY & BILLING
        if r.ImGui_CollapsingHeader(ctx, "Session Summary & Billing", r.ImGui_TreeNodeFlags_DefaultOpen()) then
            local totals = calculate_session_totals()
            
            r.ImGui_Text(ctx, "Session Statistics:")
            r.ImGui_BulletText(ctx, string.format("Total Hours: %.2f", totals.total_hours))
            r.ImGui_BulletText(ctx, string.format("Total Sessions: %d", totals.session_count))
            r.ImGui_BulletText(ctx, string.format("Average Session: %.2f hours", totals.avg_minutes / 60))
            
            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)
            
            r.ImGui_Text(ctx, "Billing (at rate per hour):")
            
            local billing_rate_str = r.GetProjExtState(0, "REA_TRACKER", "billing_rate") or "50"
            r.ImGui_SetNextItemWidth(ctx, 100)
            local changed_rate, new_rate_str = r.ImGui_InputText(ctx, "Rate ($/hr)##billing", billing_rate_str)
            
            local new_rate = tonumber(new_rate_str) or 50
            
            if changed_rate then
                r.SetProjExtState(0, "REA_TRACKER", "billing_rate", tostring(new_rate))
            end
            
            local total_cost = totals.total_hours * new_rate
            r.ImGui_TextColored(ctx, 0xFF00FFFF, string.format("Total Cost: $%.2f", total_cost))
            
            r.ImGui_Spacing(ctx)
            
            if r.ImGui_Button(ctx, "Export to CSV") then
                export_time_log_csv()
            end
        end
        
        r.ImGui_End(ctx)
    end
    
    if open then r.defer(frame) end
end

r.defer(frame)
