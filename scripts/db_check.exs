# scripts/db_check.exs
defmodule DBCheck do
  def run do
    # First, print database configuration
    db_config = Application.get_env(:bitcoin_address_watcher, AddressWatcher.Repo)
    IO.puts("Database config:")
    IO.inspect(db_config)

    # Start required applications
    Application.ensure_all_started(:ecto)
    Application.ensure_all_started(:postgrex)

    # Start Repo manually or use existing one
    IO.puts("\nTrying to start or connect to Repo...")
    repo_pid = case AddressWatcher.Repo.start_link(db_config) do
      {:ok, pid} ->
        IO.puts("Successfully started the Repo!")
        pid
      {:error, {:already_started, pid}} ->
        IO.puts("Repo is already started (PID: #{inspect(pid)}), which is good!")
        pid
      {:error, error} ->
        IO.puts("Failed to connect to database: #{inspect(error)}")
        nil
    end

    if repo_pid do
      # Try a simple query to verify everything works
      IO.puts("\nTrying a simple query...")
      case Ecto.Adapters.SQL.query(AddressWatcher.Repo, "SELECT 1") do
        {:ok, result} ->
          IO.puts("Query successful! Result: #{inspect(result)}")

          # Check if transactions table exists
          IO.puts("\nChecking for transactions table...")
          case Ecto.Adapters.SQL.query(AddressWatcher.Repo,
            "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'transactions')") do
            {:ok, %{rows: [[true]]}} ->
              IO.puts("Transactions table exists!")
              # Count transactions
              {:ok, %{rows: [[count]]}} = Ecto.Adapters.SQL.query(
                AddressWatcher.Repo, "SELECT COUNT(*) FROM transactions")
              IO.puts("Transaction count: #{count}")
            {:ok, %{rows: [[false]]}} ->
              IO.puts("Transactions table doesn't exist! Have you run migrations?")
            {:error, err} ->
              IO.puts("Error checking for table: #{inspect(err)}")
          end
          :ok
        {:error, error} ->
          IO.puts("Query failed: #{inspect(error)}")
          :error
      end
    end
  end
end

DBCheck.run()
