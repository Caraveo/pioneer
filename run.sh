#!/bin/bash
# Run script for Pioneer macOS app

echo "Building Pioneer..."
swift build

if [ $? -eq 0 ]; then
    echo "Build successful! Running Pioneer..."
    swift run Pioneer
else
    echo "Build failed!"
    exit 1
fi


