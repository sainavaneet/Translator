#!/bin/bash

# Script to copy the built Translator.app to Applications folder

# Get the build products directory
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$TARGET_BUILD_DIR}"
APP_NAME="Translator.app"
APP_PATH="${BUILT_PRODUCTS_DIR}/${APP_NAME}"
APPLICATIONS_DIR="/Applications"

# Check if the app was built successfully
if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_NAME} not found at ${APP_PATH}"
    exit 1
fi

# Remove existing app in Applications if it exists
if [ -d "${APPLICATIONS_DIR}/${APP_NAME}" ]; then
    echo "Removing existing ${APP_NAME} from Applications..."
    rm -rf "${APPLICATIONS_DIR}/${APP_NAME}"
fi

# Copy the app to Applications
echo "Copying ${APP_NAME} to ${APPLICATIONS_DIR}..."
cp -R "$APP_PATH" "$APPLICATIONS_DIR/"

# Set proper permissions
chmod -R 755 "${APPLICATIONS_DIR}/${APP_NAME}"

echo "Successfully copied ${APP_NAME} to Applications folder!"
