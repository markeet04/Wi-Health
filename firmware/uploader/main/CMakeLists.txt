set(SHARED "${CMAKE_CURRENT_LIST_DIR}/../../shared")

idf_component_register(
    SRCS
        "app_main.c"
        "${SHARED}/wihealth_cloud_map.c"
    INCLUDE_DIRS
        "."
        "${SHARED}"
    REQUIRES
        nvs_flash esp_wifi esp_event esp_netif esp_timer
        esp_http_client esp_http_server esp-tls json lwip
)
