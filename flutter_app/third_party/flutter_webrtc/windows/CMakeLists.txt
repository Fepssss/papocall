cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "flutter_webrtc")
project(${PROJECT_NAME} LANGUAGES CXX)

if (CMAKE_VERSION VERSION_GREATER_EQUAL "3.24.0")
  cmake_policy(SET CMP0135 NEW)
endif()

# Add the libwebrtc dependency
include("${CMAKE_CURRENT_SOURCE_DIR}/../third_party/CMakeLists.txt")

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "flutter_webrtc_plugin")

add_definitions(-DLIB_WEBRTC_API_DLL)
add_definitions(-DRTC_DESKTOP_DEVICE)

add_library(${PLUGIN_NAME} SHARED
  "../common/cpp/src/flutter_common.cc"
  "../common/cpp/src/flutter_data_channel.cc"
  "../common/cpp/src/flutter_data_packet_cryptor.cc"
  "../common/cpp/src/flutter_frame_cryptor.cc"
  "../common/cpp/src/flutter_media_stream.cc"
  "../common/cpp/src/flutter_utf8_sanitize.cc"
  "../common/cpp/src/flutter_peerconnection.cc"
  "../common/cpp/src/flutter_frame_capturer.cc"
  "../common/cpp/src/flutter_video_renderer.cc"
  "../common/cpp/src/flutter_screen_capture.cc"
  "../common/cpp/src/flutter_webrtc.cc"
  "../common/cpp/src/flutter_webrtc_base.cc"
  "../common/cpp/src/flutter_audio_probe.cc"
  "../common/cpp/src/flutter_rnnoise.cc"
  "application_loopback_capturer.cc"
  "loopback_capturer_factory.cc"
  "flutter_webrtc_plugin.cc"
  "task_runner_windows.cc"
)

include_directories(
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/svpng"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/include"
)

# RNNoise (Xiph, BSD-3) compilado junto, como biblioteca estática de C. Vem como
# fonte e não como DLL porque o modelo vai dentro do fonte (src/rnn_data.c): a
# build não depende de baixar nada e o instalador não carrega DLL solta. Os
# avisos estão desligados porque as conversões são do código do autor, e o
# /WX deste alvo as trataria como erro nosso.
enable_language(C)
set(RNNOISE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/rnnoise")
add_library(papocall_rnnoise STATIC
  "${RNNOISE_DIR}/src/denoise.c"
  "${RNNOISE_DIR}/src/rnn.c"
  "${RNNOISE_DIR}/src/celt_lpc.c"
  "${RNNOISE_DIR}/src/kiss_fft.c"
  "${RNNOISE_DIR}/src/pitch.c"
  "${RNNOISE_DIR}/src/rnn_data.c"
)
target_include_directories(papocall_rnnoise PUBLIC
  "${RNNOISE_DIR}/include"
  "${RNNOISE_DIR}/src"
)
if(MSVC)
  target_compile_options(papocall_rnnoise PRIVATE /W0)
  # O config.h gerado pelo autotools é que define isto no build original; sem
  # aqui, <math.h> do MSVC não expõe M_PI e denoise.c não compila.
  target_compile_definitions(papocall_rnnoise PRIVATE _USE_MATH_DEFINES)
endif()

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE 
  flutter
  flutter_wrapper_plugin
  papocall_rnnoise
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/libwebrtc.dll.lib"
  avrt.lib
  ksuser.lib
  mmdevapi.lib
  ole32.lib
  runtimeobject.lib
  uuid.lib
  winmm.lib
)

# List of absolute paths to libraries that should be bundled with the plugin
set(flutter_webrtc_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/libwebrtc.dll"
  PARENT_SCOPE
)
