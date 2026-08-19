#!/bin/sh

# Récupérons le chemin absolu vers notre fichier docker compose.yml
export COMPOSE_FILE_PATH="${PWD}/docker-compose.yml"

# Permet de lancer notre application
start() {
    sudo docker compose -f "$COMPOSE_FILE_PATH" up --build -d
}

# Permet d'arrêter notre application
down() {
    sudo docker compose -f "$COMPOSE_FILE_PATH" down
}

# Permet de visualiser les logs de notre application en cours d'exécution
tail() {
    sudo docker compose -f "$COMPOSE_FILE_PATH" logs -f
}

# Permet de supprimer nos volumes
delete() {
    sudo docker volume rm -f data
    sudo docker volume rm -f db
}

# Permet de mettre a jour notre code a partir de notre repository
pull() {
    sudo git pull origin main
}

# Permet de choisir l'action à faire
case "$1" in
  build_start)
    pull
    start
    tail
    ;;
  start)
    start
    tail
    ;;
  stop)
    down
    ;;
  purge)
    down
    delete
    ;;
  *)
    echo "Usage: $0 {buil_start|start|stop|purge}"
esac
