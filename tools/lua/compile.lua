-- Compile only: no game chunk is executed and no bytecode artifact is emitted.
for _, path in ipairs(arg) do
    local native_path = path
    if package.config:sub(1, 1) == "\\" then
        -- LuaJIT's CRT file open needs the extended Windows spelling for
        -- absolute paths beyond MAX_PATH. Keep the original name in errors.
        native_path = path:gsub("/", "\\")
        if native_path:match("^%a:\\") then
            native_path = "\\\\?\\" .. native_path
        elseif native_path:sub(1, 2) == "\\\\" and
                native_path:sub(1, 4) ~= "\\\\?\\" then
            native_path = "\\\\?\\UNC\\" .. native_path:sub(3)
        end
    end
    local chunk, message = loadfile(native_path)
    if not chunk then
        io.stderr:write(path, ": ", message, "\n")
        os.exit(1)
    end
end
