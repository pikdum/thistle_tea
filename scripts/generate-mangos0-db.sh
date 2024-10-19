#!/usr/bin/env bash
set -eu

DB_CONTAINER="mangos0-mariadb"
DB_PASSWORD="mangos"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
OUTPUT_DIR="$(realpath "$SCRIPT_DIR/../db/")"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf $TEMP_DIR' EXIT

echo "Creating mangos0.sqlite from mangoszero/database"

echo "Starting mariadb container..."
docker run \
    --rm \
    -d \
    --name "$DB_CONTAINER" \
    -e MARIADB_ROOT_PASSWORD="$DB_PASSWORD" \
    --net=host \
    -t mariadb:latest

trap 'docker stop "$DB_CONTAINER" > /dev/null' EXIT

echo "Waiting for mariadb..."
until docker exec "$DB_CONTAINER" mariadb -uroot -p"$DB_PASSWORD" -e "SELECT 1" &>/dev/null; do
    sleep 1
done

docker run \
    --rm \
    -v "$SCRIPT_DIR:/scripts:ro" \
    -v "$TEMP_DIR:/output" \
    -e DB_PASSWORD="$DB_PASSWORD" \
    --net=host \
    -i ubuntu:24.04 bash <<'EOF'
echo "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git expect mariadb-client sqlite3

echo "Installing latest mangoszero/database..."
git clone https://github.com/mangoszero/database.git
cd database/
cp /scripts/install-databases.exp .
./install-databases.exp

echo "Converting mangos0 to sqlite..."
cd ../
git clone https://github.com/vdechef/mysql2sqlite.git
cd mysql2sqlite/
mariadb-dump -h 127.0.0.1 --skip-extended-insert --compact mangos0 -p"$DB_PASSWORD" >dump.sql
./mysql2sqlite dump.sql | sqlite3 /output/mangos0.sqlite
EOF

rm -f "$OUTPUT_DIR"/mangos0.sqlite*
mv "$TEMP_DIR/mangos0.sqlite" "$OUTPUT_DIR"

echo ""
echo "Generated $OUTPUT_DIR/mangos0.sqlite"
