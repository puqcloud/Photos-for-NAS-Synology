cmake_minimum_required(VERSION 3.10)
project(photos-for-nas-synology.puqsoftware LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt5 COMPONENTS Core Qml Quick Gui Network REQUIRED)

set(APP_NAME "photos-for-nas-synology")
set(DESKTOP_FILE "photos-for-nas-synology.desktop")
set(APPARMOR_FILE "apparmor.json")
set(MANIFEST_FILE "manifest.json")
set(ICON_FILE "photos-for-nas-synology.png")

add_executable(${APP_NAME} src/main.cpp src/SynoImageProvider.cpp src/BackupEngine.cpp)
target_link_libraries(${APP_NAME} Qt5::Core Qt5::Qml Qt5::Quick Qt5::Gui Qt5::Network)

# Set install directory for click packaging
if(DEFINED CMAKE_INSTALL_PREFIX)
    set(DATA_DIR "${CMAKE_INSTALL_PREFIX}")
else()
    set(DATA_DIR ".")
endif()

# Install files
install(TARGETS ${APP_NAME} DESTINATION ${DATA_DIR})
install(FILES ${MANIFEST_FILE} DESTINATION ${DATA_DIR})
install(FILES ${APPARMOR_FILE} DESTINATION ${DATA_DIR})
install(FILES ${DESKTOP_FILE} DESTINATION ${DATA_DIR})
install(FILES ${ICON_FILE} DESTINATION ${DATA_DIR})

install(DIRECTORY qml DESTINATION ${DATA_DIR})

