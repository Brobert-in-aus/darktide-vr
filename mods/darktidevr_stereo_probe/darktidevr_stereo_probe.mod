return {
    run = function()
        fassert(
            rawget(_G, "new_mod"),
            "darktidevr_stereo_probe requires the Darktide Mod Framework"
        )

        new_mod("darktidevr_stereo_probe", {
            mod_localization =
                "darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_localization",
            mod_data =
                "darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_data",
            mod_script =
                "darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe",
        })
    end,
    packages = {},
}
