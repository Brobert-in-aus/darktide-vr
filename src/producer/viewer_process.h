#pragma once

// The OpenXR viewer runs as a child process of the game so that a plain Steam
// launch reaches the headset without a launcher script. The executable lives
// beside the native module; its output goes to %LOCALAPPDATA%\DarktideVR.
namespace darktidevr::producer::viewer {

// Starts (enabled) or stops the viewer. Starting while it runs and stopping
// while it does not are successful no-ops. Returns 0 on success, otherwise a
// small positive code; the Win32 error is available through state().
int control(bool enabled);

// values[0] = 1 while the viewer process is alive, values[1] = last exit code
// or -1, values[2] = number of starts, values[3] = last Win32 error,
// values[4] = 1 when the executable exists beside the module.
int state(int* values, unsigned int count);

}  // namespace darktidevr::producer::viewer
