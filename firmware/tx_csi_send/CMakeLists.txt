# tx_csi_send — adapted from esp-csi/examples/get-started/csi_send
# Broadcasts 802.11 HT20 MCS0_LGI ESP-NOW frames on a fixed channel so a
# paired promiscuous RX (rx_csi_recv) can capture CSI. No router / no AP.
cmake_minimum_required(VERSION 3.16)
add_compile_options(-fdiagnostics-color=always)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

project(tx_csi_send)
