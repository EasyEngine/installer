# Migration Script

This script helps us migrate all sites from EasyEngine v3 to EasyEngine v4.

### Usage

1. Run the migration script to migrate all the sites
```bash
ee migrate --all
```

2. Run the migration script in `dry-run` mode to display information about the
migration without actually executing the migrations.
```bash
ee migrate --dry-run --all
```

3. Migrate only selected sites.
```bash
ee migrate <site1> [<site2> ...]
```
