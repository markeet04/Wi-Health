set(DSP_PORT "${CMAKE_CURRENT_LIST_DIR}/../../dsp_port/src")

idf_component_register(
    SRCS
        "app_main.c"
        "${DSP_PORT}/dsp_fft.c"
        "${DSP_PORT}/dsp_estimator.c"
        "${DSP_PORT}/dsp_nulldrop.c"
        "${DSP_PORT}/dsp_resample.c"
        "${DSP_PORT}/dsp_frontend.c"
        "${DSP_PORT}/dsp_pairs.c"
        "${DSP_PORT}/dsp_cscr.c"
        "${DSP_PORT}/dsp_waveform.c"
        "${DSP_PORT}/dsp_bandpass.c"
        "${DSP_PORT}/dsp_motion.c"
        "${DSP_PORT}/dsp_smooth.c"
        "${DSP_PORT}/dsp_anomaly.c"
    INCLUDE_DIRS
        "."
        "${DSP_PORT}"
        "${CMAKE_CURRENT_LIST_DIR}/../../shared"
    REQUIRES
        nvs_flash esp_wifi esp_timer esp_psram
        esp_csi_gain_ctrl
)
