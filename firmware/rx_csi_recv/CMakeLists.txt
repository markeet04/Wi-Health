# rx_csi_recv — adapted from esp-csi/examples/get-started/csi_recv
# Promiscuous CSI receiver on a fixed channel. NO router / no STA join.
# Streams one CSV row per CSI packet over USB serial at 921600 baud.
cmake_minimum_required(VERSION 3.16)
add_compile_options(-fdiagnostics-color=always)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

project(rx_csi_recv)
