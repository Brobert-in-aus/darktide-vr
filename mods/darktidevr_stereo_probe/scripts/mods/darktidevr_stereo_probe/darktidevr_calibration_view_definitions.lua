local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local screen = table.clone(UIWorkspaceSettings.screen)
screen.position[3] = 120

local function button_node(y)
    return {
        parent = "panel",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 520, 54 },
        position = { 0, y, 4 },
    }
end

local scenegraph_definition = {
    screen = screen,
    panel = {
        parent = "screen",
        horizontal_alignment = "center",
        vertical_alignment = "center",
        size = { 980, 900 },
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
        size = { 820, 150 },
        position = { 0, 130, 3 },
    },
    status = {
        parent = "panel",
        horizontal_alignment = "center",
        vertical_alignment = "top",
        size = { 820, 90 },
        position = { 0, 285, 3 },
    },
    standing_bilateral = button_node(395),
    seated_bilateral = button_node(460),
    standing_left = button_node(525),
    standing_right = button_node(590),
    capture = button_node(675),
    retry = button_node(740),
    back = button_node(805),
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
    capture = button_widget("capture", "CAPTURE POSE"),
    retry = button_widget("retry", "RETRY CURRENT STEP"),
    back = button_widget("back", "BACK"),
}

return {
    scenegraph_definition = scenegraph_definition,
    widget_definitions = widget_definitions,
}
