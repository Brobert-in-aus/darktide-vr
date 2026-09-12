@{
    # Each entry copies a repository file (Source, relative to the repository
    # root) to a path inside the release archive (Destination, relative to the
    # archive root). The archive is shaped like the game folder: extract it
    # over the Darktide installation so that mods\darktidevr_stereo_probe lands
    # beside the other mods, then run "Darktide VR Mode.bat" inside it. Every
    # file, the documents included, lives under that mod folder.
    Files = @(
        @{ Source = 'tools/release/package-README.txt'; Destination = 'mods/darktidevr_stereo_probe/README.txt' }
        @{ Source = 'LICENSE'; Destination = 'mods/darktidevr_stereo_probe/LICENSE' }
        @{ Source = 'THIRD_PARTY_NOTICES.md'; Destination = 'mods/darktidevr_stereo_probe/THIRD_PARTY_NOTICES.md' }
        @{ Source = 'CHANGELOG.md'; Destination = 'mods/darktidevr_stereo_probe/CHANGELOG.md' }
        @{ Source = 'docs/USER-GUIDE.md'; Destination = 'mods/darktidevr_stereo_probe/USER-GUIDE.md' }
        @{ Source = 'mods/darktidevr_stereo_probe/darktidevr_stereo_probe.mod'; Destination = 'mods/darktidevr_stereo_probe/darktidevr_stereo_probe.mod' }
        @{ Source = 'mods/darktidevr_stereo_probe/Darktide VR Mode.bat'; Destination = 'mods/darktidevr_stereo_probe/Darktide VR Mode.bat' }
        @{ Source = 'mods/darktidevr_stereo_probe/darktidevr-mode.ps1'; Destination = 'mods/darktidevr_stereo_probe/darktidevr-mode.ps1' }
        @{ Source = 'tools/stereo/set-skinner-assert-patch.ps1'; Destination = 'mods/darktidevr_stereo_probe/tools/set-skinner-assert-patch.ps1' }
        @{ Source = 'build/windows-vs2022/src/producer/Release/d3d12.dll'; Destination = 'mods/darktidevr_stereo_probe/bin/d3d12.dll' }
        @{ Source = 'build/windows-vs2022/src/producer/Release/darktidevr_native_capture.dll'; Destination = 'mods/darktidevr_stereo_probe/bin/darktidevr_native_capture.dll' }
        @{ Source = 'build/windows-vs2022/tests/xr_harness/Release/darktidevr-xr-harness.exe'; Destination = 'mods/darktidevr_stereo_probe/bin/darktidevr-xr-harness.exe' }
        @{ Source = 'build/windows-vs2022/tests/xr_harness/Release/openxr_loader.dll'; Destination = 'mods/darktidevr_stereo_probe/bin/openxr_loader.dll' }
        @{ Source = 'build/windows-vs2022/tests/xr_harness/Release/OPENXR-LICENSE.txt'; Destination = 'mods/darktidevr_stereo_probe/bin/OPENXR-LICENSE.txt' }
        @{ Source = 'build/dependencies/dxc-runtime/dxcompiler.dll'; Destination = 'mods/darktidevr_stereo_probe/bin/dxcompiler.dll' }
        @{ Source = 'build/dependencies/dxc-runtime/LICENSE-LLVM.txt'; Destination = 'mods/darktidevr_stereo_probe/bin/DXC-LICENSE-LLVM.txt' }
        @{ Source = 'build/dependencies/dxc-runtime/LICENSE-MIT.txt'; Destination = 'mods/darktidevr_stereo_probe/bin/DXC-LICENSE-MIT.txt' }
        @{ Source = 'build/dependencies/dxc-runtime/LICENSE-MS.txt'; Destination = 'mods/darktidevr_stereo_probe/bin/DXC-LICENSE-MS.txt' }
        @{ Source = 'build/generated/billboard_shaders/vs-42e436fb1ef1b392.dxil'; Destination = 'mods/darktidevr_stereo_probe/bin/billboard_shaders/vs-42e436fb1ef1b392.dxil' }
        # Presence-gated bootstrap options that are part of the play configuration.
        @{ Source = 'tools/release/package-files/bin/darktidevr_billboard_shader_substitution.flag'; Destination = 'mods/darktidevr_stereo_probe/bin/darktidevr_billboard_shader_substitution.flag' }
        @{ Source = 'tools/release/package-files/bin/darktidevr_cluster_light_visibility_fix.flag'; Destination = 'mods/darktidevr_stereo_probe/bin/darktidevr_cluster_light_visibility_fix.flag' }
    )
    # Every Lua module in this repository directory is copied to the
    # destination directory; the .mod descriptor lists the entry chunk.
    LuaDirectory = 'mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe'
    LuaDestination = 'mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe'
    # Project-built payloads that a component build record must cover.
    ProjectBinaries = @(
        'mods/darktidevr_stereo_probe/bin/d3d12.dll'
        'mods/darktidevr_stereo_probe/bin/darktidevr_native_capture.dll'
        'mods/darktidevr_stereo_probe/bin/darktidevr-xr-harness.exe'
    )
}
