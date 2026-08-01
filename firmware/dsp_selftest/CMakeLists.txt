# dsp_selftest — on-device proof that the ported C DSP runs correctly on the
# ESP32-S3 (xtensa) and matches the host/Python golden. Reuses the validated
# sources in ../dsp_port/src as an IDF component (see main/CMakeLists.txt).
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(dsp_selftest)
