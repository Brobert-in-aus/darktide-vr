-- Compile only: no game chunk is executed and no bytecode artifact is emitted.
for _, path in ipairs(arg) do
    local chunk, message = loadfile(path)
    if not chunk then
        io.stderr:write(path, ": ", message, "\n")
        os.exit(1)
    end
end
