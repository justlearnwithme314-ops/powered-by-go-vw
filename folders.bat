@echo off
title GO.VW Project Structure Creator

echo Creating GO.VW project structure...

:: Root folders
mkdir GO.VW
cd GO.VW

mkdir govw_core
mkdir govw_server
mkdir govw_client
mkdir govw_modding
mkdir docs
mkdir tools
mkdir assets
mkdir tests

:: ==========================
:: govw_core
:: ==========================
mkdir govw_core\world
mkdir govw_core\voxels
mkdir govw_core\entities
mkdir govw_core\physics
mkdir govw_core\networking
mkdir govw_core\serialization
mkdir govw_core\terrain
mkdir govw_core\utilities
mkdir govw_core\game_rules

:: ==========================
:: govw_server
:: ==========================
mkdir govw_server\config
mkdir govw_server\networking
mkdir govw_server\save_system
mkdir govw_server\world
mkdir govw_server\plugins
mkdir govw_server\logs

:: ==========================
:: govw_client
:: ==========================
mkdir govw_client\scenes
mkdir govw_client\scripts
mkdir govw_client\ui
mkdir govw_client\audio
mkdir govw_client\materials
mkdir govw_client\shaders
mkdir govw_client\models
mkdir govw_client\textures
mkdir govw_client\particles
mkdir govw_client\camera

:: ==========================
:: govw_modding
:: ==========================
mkdir govw_modding\api
mkdir govw_modding\events
mkdir govw_modding\registries
mkdir govw_modding\examples
mkdir govw_modding\documentation

:: ==========================
:: Assets
:: ==========================
mkdir assets\textures
mkdir assets\models
mkdir assets\audio
mkdir assets\fonts
mkdir assets\icons
mkdir assets\shaders

:: ==========================
:: Documentation
:: ==========================
mkdir docs\architecture
mkdir docs\networking
mkdir docs\modding
mkdir docs\api
mkdir docs\guides

:: ==========================
:: Tests
:: ==========================
mkdir tests\unit
mkdir tests\integration
mkdir tests\performance

:: ==========================
:: Tools
:: ==========================
mkdir tools\chunk_viewer
mkdir tools\world_converter
mkdir tools\benchmark
mkdir tools\debug

echo.
echo ======================================
echo GO.VW project structure created!
echo ======================================
pause