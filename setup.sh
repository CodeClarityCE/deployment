#!/bin/bash

# Verify the presence of required commands

if ! command -v curl &> /dev/null; then
  echo "Error: curl is not installed."
  exit 1
fi

if ! command -v openssl &> /dev/null; then
  echo "Error: openssl is not installed."
  exit 1
fi

if ! command -v make &> /dev/null; then
  echo "Error: make is not installed."
  exit 1
fi

if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
  echo "Error: docker or docker-compose is not installed."
  exit 1
fi

echo "All required commands are installed."