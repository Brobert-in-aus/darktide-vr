return {
    run = function()
        fassert(
            rawget(_G, "new_mod"),
            "darktidevr requires the Darktide Mod Framework"
        )

        new_mod("darktidevr", {
            mod_localization =
                "darktidevr/scripts/mods/darktidevr/darktidevr_localization",
            mod_data =
                "darktidevr/scripts/mods/darktidevr/darktidevr_data",
            mod_script =
                "darktidevr/scripts/mods/darktidevr/darktidevr",
        })
    end,
    packages = {},
}
