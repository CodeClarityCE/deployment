#!/bin/bash

for img in $(docker compose config --images); do
  if [[ "$img" == *codeclarity* ]]; then
    echo "$img"
  fi
  images="$images $img"
done

# shellcheck disable=SC2086 # splits the image list into arguments
docker save -o services.img $images