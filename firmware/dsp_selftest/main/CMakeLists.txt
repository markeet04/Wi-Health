# Compile the self-test together with the validated dsp_port sources.
# The dsp_port .c files are pure C99 with no ESP-IDF deps, so they build
# unchanged for xtensa. Paths are relative to this main/ dir.
set(DSP_PORT "${CMAKE_CURRENT_LIST_DIR}/../../dsp_port/src")

idf_component_register(
    SRCS
        "app_main.c"
        "${DSP_PORT}/dsp_fft.c"
        "${DSP_PORT}/dsp_estimator.c"
        "${DSP_PORT}/dsp_nulldrop.c"
        "${DSP_PORT}/dsp_resample.c"
        "${DSP_PORT}/dsp_cscr.c"
        "${DSP_PORT}/dsp_waveform.c"
        "${DSP_PORT}/dsp_bandpass.c"
        "${DSP_PORT}/dsp_motion.c"
    INCLUDE_DIRS
        "."
        "${DSP_PORT}"
)
