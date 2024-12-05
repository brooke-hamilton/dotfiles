#!/bin/bash

# Cleans all cached docker content from a docker desktop installation
# Usage: curl -sL https://aka.ms/cleandocker | bash

docker rm -f "$(docker ps -aq)"
docker system prune -af
docker volume prune -af
