# Save this as debug_migrations.exs in your project root
# Run with: mix run debug_migrations.exs

# Get the repo and migration modules
repo = AddressWatcher.Repo
migrator = Ecto.Migrator

IO.puts("\n=== MIGRATION DEBUG INFO ===")

# Check what migrations the repo thinks are pending
IO.puts("\nChecking migrations status:")
{status, migrations} = migrator.migrations(repo)
IO.puts("Migration status: #{status}")
IO.inspect(migrations, label: "Migrations")

# Check database migration records
IO.puts("\nChecking schema_migrations table:")
try do
  query = "SELECT * FROM schema_migrations ORDER BY version"
  result = repo.query!(query)
  IO.inspect(result.rows, label: "Database migration records")
rescue
  e -> IO.puts("Error querying schema_migrations: #{inspect(e)}")
end

# Check migration source files
IO.puts("\nChecking migration files:")
migration_dir = Path.join(["priv", "repo", "migrations"])
migration_files = case File.ls(migration_dir) do
  {:ok, files} -> files
  {:error, reason} ->
    IO.puts("Could not list migration files: #{inspect(reason)}")
    []
end
IO.inspect(migration_files, label: "Migration files found")

# Find any mismatch
IO.puts("\nAnalyzing for mismatches:")
if status == :ok do
  IO.puts("No pending migrations detected by Ecto")
else
  IO.puts("Ecto thinks there are pending migrations!")

  # Find which migrations are considered pending
  pending = Enum.filter(migrations, fn {status, _, _} -> status == :down end)
  IO.inspect(pending, label: "Pending migrations")
end

# Try to pinpoint the issue
IO.puts("\nDetailed migrator state:")
try do
  # Check if we have access to internal state
  migration_source = migrator.__migration_source__()
  IO.puts("Migration source: #{inspect(migration_source)}")
rescue
  _ -> IO.puts("Could not access migrator internal state")
end

IO.puts("\n=== MIGRATION DEBUG COMPLETE ===\n")
