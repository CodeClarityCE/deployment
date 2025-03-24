#!/bin/bash

for img in $(docker compose config --images); do
  if [[ "$img" == *codeclarity* ]]; then
    echo "$img"
  fi
  images="$images $img"
done

docker save -o services.img $images