local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local screen = table.clone(UIWorkspaceSettings.screen)
screen.position[3] = 120

local function button_node(y)
    return {
        parent = "panel",
        horizontal_alignment = "left",
        vertical_alignment = "top",
        size = { 520, 54 },
        position = { 100, y, 4 },
    }
end

local scenegraph_definition = {
    screen = screen,
    panel = {
        parent = "screen",
        horizontal_alignment = "center",
        vertical_alignment = "center",
        size = { 1440, 900 },
        position = { 0, 0, 2 },
    },
    title = {
        parent = "panel",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 850, 70 },
        position = { 0, 50, 3 },
    },
    instruction = {
        parent = "panel",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 1240, 150 },
        position = { 0, 130, 3 },
    },
    status = {
        parent = "panel",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 1240, 90 },
        position = { 0, 285, 3 },
    },
    standing_bilateral = button_node(395),
    seated_bilateral = button_node(460),
    standing_left = button_node(525),
    standing_right = button_node(590),
    capture = button_node(675),
    retry = button_node(740),
    back = button_node(805),
    pose_preview = {
        parent = "panel",
        horizontal_alignment = "right",
        vertical_alignment = "top",
        size = { 600, 500 },
        position = { -100, 380, 3 },
    },
    pose_head = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 64, 64 },
        position = { 0, 80, 5 },
    },
    target_head = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 76, 76 },
        position = { 0, 74, 4 },
    },
    pose_torso = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 18, 240 },
        position = { 0, 155, 4 },
    },
    pose_shoulders = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 250, 14 },
        position = { 0, 175, 4 },
    },
    pose_left = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 50, 50 },
        position = { -170, 185, 5 },
    },
    pose_right = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 50, 50 },
        position = { 170, 185, 5 },
    },
    target_left = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 62, 62 },
        position = { -250, 175, 4 },
    },
    target_right = {
        parent = "pose_preview",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 62, 62 },
        position = { 250, 175, 4 },
    },
}

local title_style = table.clone(UIFontSettings.header_1)
title_style.text_horizontal_alignment = "center"
title_style.text_vertical_alignment = "center"

local body_style = table.clone(UIFontSettings.body)
body_style.text_horizontal_alignment = "center"
body_style.text_vertical_alignment = "center"

local function text_widget(node, value, style)
    return UIWidget.create_definition({
        {
            pass_type = "text",
            value_id = "text",
            value = value,
            style = style,
        },
    }, node)
end

local function button_widget(node, label)
    return UIWidget.create_definition(
        ButtonPassTemplates.terminal_button, node,
        { original_text = label })
end

local function pose_marker_widget(node, label, color)
    return UIWidget.create_definition({
        {
            pass_type = "rect",
            style = { color = color },
            visibility_function = function(content)
                return content.visible
            end,
        },
        {
            pass_type = "text",
            value = label,
            style = body_style,
            visibility_function = function(content)
                return content.visible
            end,
        },
    }, node, { visible = true })
end

local widget_definitions = {
    background = UIWidget.create_definition({
        {
            pass_type = "rect",
            style = { color = { 245, 5, 8, 10 } },
        },
        {
            pass_type = "texture",
            value = "content/ui/materials/frames/frame_tile_2px",
            style = { offset = { 0, 0, 2 } },
        },
    }, "panel"),
    title = text_widget("title", "DARKTIDE VR CALIBRATION", title_style),
    instruction = text_widget("instruction",
        "Choose a calibration mode. Measurements are kept in physical source space and retargeted separately for each operative.",
        body_style),
    status = text_widget("status", "Waiting for a mode selection.", body_style),
    standing_bilateral = button_widget(
        "standing_bilateral", "STANDING - BOTH ARMS"),
    seated_bilateral = button_widget(
        "seated_bilateral", "SEATED - BOTH ARMS"),
    standing_left = button_widget(
        "standing_left", "STANDING - LEFT ARM ONLY"),
    standing_right = button_widget(
        "standing_right", "STANDING - RIGHT ARM ONLY"),
    capture = text_widget("capture",
        "POSE CAPTURE USES THE CONTROLLER TRIGGER(S)", body_style),
    retry = button_widget("retry", "RETRY CURRENT STEP"),
    back = button_widget("back", "DONE"),
    target_head = pose_marker_widget(
        "target_head", "TARGET", { 110, 115, 125, 135 }),
    target_left = pose_marker_widget(
        "target_left", "L", { 110, 115, 125, 135 }),
    target_right = pose_marker_widget(
        "target_right", "R", { 110, 115, 125, 135 }),
    pose_head = pose_marker_widget(
        "pose_head", "H", { 165, 230, 230, 230 }),
    pose_torso = UIWidget.create_definition({
        { pass_type = "rect", style = { color = { 180, 90, 100, 110 } } },
    }, "pose_torso"),
    pose_shoulders = UIWidget.create_definition({
        { pass_type = "rect", style = { color = { 180, 90, 100, 110 } } },
    }, "pose_shoulders"),
    pose_left = pose_marker_widget(
        "pose_left", "L", { 165, 70, 190, 255 }),
    pose_right = pose_marker_widget(
        "pose_right", "R", { 165, 255, 150, 50 }),
}

return {
    scenegraph_definition = scenegraph_definition,
    widget_definitions = widget_definitions,
}
