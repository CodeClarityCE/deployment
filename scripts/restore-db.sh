docker compose -f ../docker-compose.yaml \
	exec db sh -c "pg_restore -l /dump/$1.dump > /dump/$1.list && pg_restore -U postgres -d $1 -L /dump/$1.list /dump/$1.dump"