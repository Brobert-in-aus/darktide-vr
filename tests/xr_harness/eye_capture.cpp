#include "window_capture.h"

#include <Windows.h>

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void write_bgra_bmp(const std::filesystem::path& path,
                    const darktidevr::harness::CapturedWindowFrame& frame,
                    std::uint32_t source_x, std::uint32_t source_y,
                    std::uint32_t width, std::uint32_t height) {
  const auto pixel_bytes = static_cast<std::uint32_t>(width * height * 4);
  BITMAPFILEHEADER file_header{};
  file_header.bfType = 0x4D42;
  file_header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  file_header.bfSize = file_header.bfOffBits + pixel_bytes;

  BITMAPINFOHEADER info_header{};
  info_header.biSize = sizeof(BITMAPINFOHEADER);
  info_header.biWidth = static_cast<LONG>(width);
  info_header.biHeight = -static_cast<LONG>(height);
  info_header.biPlanes = 1;
  info_header.biBitCount = 32;
  info_header.biCompression = BI_RGB;
  info_header.biSizeImage = pixel_bytes;

  std::ofstream output(path, std::ios::binary);
  if (!output) {
    throw std::runtime_error("Could not create eye capture BMP");
  }
  output.write(reinterpret_cast<const char*>(&file_header), sizeof(file_header));
  output.write(reinterpret_cast<const char*>(&info_header), sizeof(info_header));
  for (std::uint32_t y = 0; y < height; ++y) {
    const auto* row = frame.bgra_pixels +
                      static_cast<std::size_t>(source_y + y) * frame.row_pitch +
                      static_cast<std::size_t>(source_x) * 4;
    output.write(reinterpret_cast<const char*>(row),
                 static_cast<std::streamsize>(width) * 4);
  }
  if (!output) {
    throw std::runtime_error("Could not finish eye capture BMP");
  }
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc < 2 || argc > 3) {
      std::wcerr << L"Usage: darktidevr-eye-capture OUTPUT_DIRECTORY "
                    L"[--top-bottom]\n";
      return 2;
    }
    const bool top_bottom = argc == 3 &&
                            std::wstring(argv[2]) == L"--top-bottom";
    if (argc == 3 && !top_bottom) {
      throw std::invalid_argument("Unknown eye capture layout");
    }
    const std::uint32_t capture_width = top_bottom ? 2160U : 1920U;
    const std::uint32_t capture_height = top_bottom ? 4320U : 1080U;
    const std::uint32_t eye_width = top_bottom ? capture_width
                                               : capture_width / 2;
    const std::uint32_t eye_height = top_bottom ? capture_height / 2
                                                : capture_height;
    const std::filesystem::path output_directory(argv[1]);
    std::filesystem::create_directories(output_directory);

    darktidevr::harness::WindowCapture capture(
        L"Warhammer 40,000: Darktide", capture_width, capture_height);
    const auto frame = capture.capture();
    const auto left_path = output_directory / L"left-eye.bmp";
    const auto right_path = output_directory / L"right-eye.bmp";
    write_bgra_bmp(left_path, frame, 0, 0, eye_width, eye_height);
    write_bgra_bmp(right_path, frame, top_bottom ? 0 : eye_width,
                   top_bottom ? eye_height : 0, eye_width, eye_height);
    std::wcout << L"left_eye=" << left_path.wstring() << L'\n'
               << L"right_eye=" << right_path.wstring() << L'\n'
               << L"capture_size=" << capture_width << L'x' << capture_height
               << L'\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "eye_capture: " << error.what() << '\n';
    return 1;
  }
}
