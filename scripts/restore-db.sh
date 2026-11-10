# Verifies the dumps against their manifest, or restores one of them, inside the db container.
# Usage (from scripts/): sh restore-db.sh verify | sh restore-db.sh <database>

script=$(cat restore-dump.sh) || exit 1

if [ "$1" = verify ]; then
	docker compose -f ../docker-compose.yaml exec -T db sh -c "$script" restore-dump verify
else
	docker compose -f ../docker-compose.yaml exec -T db sh -c "$script" restore-dump restore "$1" "$1" --no-acl --no-owner
fi
