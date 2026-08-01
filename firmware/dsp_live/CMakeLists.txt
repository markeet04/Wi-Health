# dsp_live — live on-device breathing monitor. Captures CSI from the paired
# TX (reusing the validated rx_csi_recv WiFi/CSI setup), buffers 30 s windows,
# and runs the ported C DSP chain to print a live breathing rate over serial.
# No Firebase yet — that is Module 4.
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(dsp_live)
