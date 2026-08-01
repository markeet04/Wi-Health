# uploader — the plain ESP32 (ESP32-D0WD-V3) that receives breathing results
# from the RX/S3 over ESP-NOW and writes them to Firebase RTDB
# (/devices/$id/live, and /alerts/$id for Module 5 alerts). RX can't do this
# itself (it is locked in promiscuous mode on the CSI channel).
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(uploader)
