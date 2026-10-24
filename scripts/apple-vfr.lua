-- Apple Video Flashing Reduction
local mp = require 'mp'
local msg = require 'mp.msg'
local options = require 'mp.options'
local utils = require 'mp.utils'

local settings = {
    enabled = true,
    peak_nits = 500,
    area_deg2 = 1265.63,
    fps = 0,
    comparison = false,
    shader = '',
}
local rates = {24, 25, 30, 50, 60, 90, 120}
local epoch = 0
local installed = false
local selected_rate = 60
local source_rate = 60
local shader_path
local parameter_prefix

local function nearest_rate(value)
    local result = 1
    for i = 2, #rates do
        if math.abs(rates[i] - value) < math.abs(rates[result] - value) then
            result = i
        end
    end
    return result
end

local luminance_rows = {
    ['bt.709'] = {0.2126729, 0.7151522, 0.0721750},
    ['display-p3'] = {0.228974564069749, 0.691738521836506, 0.079286914093745},
    ['dci-p3'] = {0.209491677912731, 0.721595254161044, 0.068913067926226},
    ['bt.2020'] = {0.262700212011267, 0.677998071518871, 0.059301716469862},
    ['bt.601-525'] = {0.212376360705068, 0.701059856925723, 0.086563782369209},
    ['bt.601-625'] = {0.222004309998231, 0.706654765925283, 0.071340924076486},
}

local function update_parameters(reset)
    if not shader_path then return end
    if reset then epoch = epoch + 1 end
    local video = mp.get_property_native('video-out-params')
    if not video then return end -- Audio-only files and the interval between playlist entries
    local row = luminance_rows[video.primaries]
    if not row then
        msg.error('Unsupported RGB primaries: ' .. tostring(video.primaries))
        local values = mp.get_property_native('glsl-shader-opts', {})
        values[parameter_prefix .. 'enabled'] = '0'
        mp.set_property_native('glsl-shader-opts', values)
        return
    end
    local measured = mp.get_property_number('estimated-vf-fps')
    local container = mp.get_property_number('container-fps')
    source_rate = settings.fps > 0 and settings.fps or measured or container
    if not source_rate or source_rate <= 0 then
        return -- Decoder FPS becomes available on video-reconfig / estimated-vf-fps
    end
    local index = nearest_rate(source_rate * mp.get_property_number('speed', 1))
    selected_rate = rates[index]
    local values = mp.get_property_native('glsl-shader-opts', {})
    local params = {
        enabled = settings.enabled and 1 or 0,
        reset_epoch = epoch,
        rate_index = index - 1,
        peak_nits = settings.peak_nits,
        area_deg2 = settings.area_deg2,
        y_r = row[1], y_g = row[2], y_b = row[3],
        comparison = settings.comparison and 1 or 0,
    }
    for key, value in pairs(params) do
        values[parameter_prefix .. key] = string.format('%.12g', value)
    end
    mp.set_property_native('glsl-shader-opts', values)
end

local function validate_settings()
    if settings.peak_nits <= 0 or settings.area_deg2 <= 0 or settings.fps < 0 then
        msg.error('peak_nits and area_deg2 must be positive; fps must be nonnegative.')
        return false
    end
    return true
end

local function configure()
    if validate_settings() then update_parameters(true) end
end

options.read_options(settings, 'apple-vfr', configure)
if not validate_settings() then return end

if settings.shader ~= '' then
    shader_path = mp.command_native({'expand-path', settings.shader})
else
    local script_dir = utils.split_path(debug.getinfo(1, 'S').source:sub(2))
    shader_path = utils.join_path(script_dir, '../shaders/apple-vfr.glsl')
end
if not utils.file_info(shader_path) then
    msg.error('Shader file not found: ' .. shader_path)
    return
end
local _, filename = utils.split_path(shader_path)
parameter_prefix = filename:gsub('%.[^.]+$', '') .. '/'

local function install()
    if installed then return end
    local shaders = mp.get_property_native('glsl-shaders', {})
    for _, existing in ipairs(shaders) do
        if existing == shader_path then installed = true; return end
    end
    mp.commandv('change-list', 'glsl-shaders', 'append', shader_path)
    installed = true
end

local function status()
    local equivalent = math.sqrt(settings.area_deg2 * 1.6)
    local sizes = {6, 20, 45}
    local size = sizes[1]
    for i = 2, #sizes do
        if math.abs(equivalent - sizes[i]) < math.abs(equivalent - size) then size = sizes[i] end
    end
    local text = string.format('Apple VFR %s | U=%.1f nits | A=%.2f deg² | W=%d Hz | S=%d°',
        settings.enabled and 'ON' or 'OFF', settings.peak_nits, settings.area_deg2,
        selected_rate, size)
    msg.info(text)
    mp.osd_message(text, 4)
end

local function toggle()
    settings.enabled = not settings.enabled
    update_parameters(true)
    status()
end

mp.add_key_binding('Ctrl+Alt+f', 'toggle', toggle)
mp.add_key_binding('Ctrl+Alt+c', 'comparison', function()
    settings.comparison = not settings.comparison
    update_parameters(false)
    mp.osd_message(settings.comparison and 'Apple VFR: left original / right processed' or 'Apple VFR: full image', 3)
end)
mp.add_key_binding('Ctrl+Alt+i', 'status', status)
mp.register_script_message('apple-vfr-toggle', toggle)
mp.register_script_message('apple-vfr-status', status)
mp.register_script_message('apple-vfr-set', function(name, text)
    local value = tonumber(text)
    if (name ~= 'peak_nits' and name ~= 'area_deg2' and name ~= 'fps') or not value then
        msg.error('apple-vfr-set accepts peak_nits, area_deg2 or fps and a number.')
        return
    end
    if value < 0 or (name ~= 'fps' and value == 0) then
        msg.error('Invalid value for ' .. name)
        return
    end
    settings[name] = value
    update_parameters(true)
    status()
end)

mp.register_event('file-loaded', function()
    install()
    update_parameters(true)
end)
mp.register_event('video-reconfig', function() update_parameters(true) end)
mp.register_event('seek', function() update_parameters(true) end)
mp.observe_property('speed', 'number', function() update_parameters(true) end)
mp.observe_property('estimated-vf-fps', 'number', function(_, fps)
    if fps and settings.fps == 0 then
        local index = nearest_rate(fps * mp.get_property_number('speed', 1))
        if not source_rate or source_rate <= 0 or rates[index] ~= selected_rate then update_parameters(true) end
    end
end)
msg.info('Apple VFR ready. Renderer: gpu-next. Ctrl+Alt+f toggles processing.')
