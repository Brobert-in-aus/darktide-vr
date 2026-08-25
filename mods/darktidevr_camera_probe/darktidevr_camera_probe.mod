return {
    run = function()
        fassert(
            rawget(_G, "new_mod"),
            "darktidevr_camera_probe requires the Darktide Mod Framework"
        )

        new_mod("darktidevr_camera_probe", {
            mod_script =
                "darktidevr_camera_probe/scripts/mods/darktidevr_camera_probe/darktidevr_camera_probe",
        })
    end,
    packages = {},
}
