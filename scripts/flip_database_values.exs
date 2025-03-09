# Save as flip_transaction_values.exs and run with: mix run flip_transaction_values.exs

defmodule TransactionFixer do
  def run do
    IO.puts("\n=== Transaction Sign Correction Script ===")
    IO.puts("This script will flip the sign of all transaction amounts in the database.")
    IO.puts("This corrects the interpretation of incoming/outgoing transactions.")
    IO.puts("\nWARNING: This is a one-time operation and should only be run once.")

    case IO.gets("Are you sure you want to proceed? (yes/no): ") |> String.trim() |> String.downcase() do
      "yes" ->
        flip_transaction_signs()
      _ ->
        IO.puts("Operation cancelled.")
    end
  end

  defp flip_transaction_signs do
    IO.puts("\nFlipping transaction signs...")

    # First, get a count of transactions to flip
    {:ok, count_result} = AddressWatcher.Repo.query("SELECT COUNT(*) FROM transactions")
    [[total]] = count_result.rows
    IO.puts("Found #{total} transactions to process.")

    # Execute the update query to flip all amounts
    case AddressWatcher.Repo.query("""
      UPDATE transactions
      SET amount = -amount,
          updated_at = NOW()
      RETURNING id, tx_hash, address, amount
    """) do
      {:ok, result} ->
        IO.puts("Successfully flipped #{length(result.rows)} transaction amounts.")

        # Show some examples of the changes
        IO.puts("\nExample updates:")
        result.rows
        |> Enum.take(5)
        |> Enum.each(fn [id, tx_hash, address, new_amount] ->
          IO.puts("ID: #{id}, TX: #{String.slice(tx_hash, 0, 10)}..., New amount: #{new_amount / 100_000_000} BTC")
        end)

        # Now we need to recalculate the balance_after values too
        IO.puts("\nRecalculating running balances...")
        recalculate_balances()

      {:error, error} ->
        IO.puts("Error updating transactions: #{inspect(error)}")
    end
  end

  defp recalculate_balances do
    # Get all unique addresses
    {:ok, addresses_result} = AddressWatcher.Repo.query("""
      SELECT DISTINCT address FROM transactions
    """)

    addresses = Enum.map(addresses_result.rows, fn [address] -> address end)
    IO.puts("Found #{length(addresses)} unique addresses to process.")

    # Process each address separately
    for address <- addresses do
      IO.puts("Processing address: #{String.slice(address, 0, 10)}...")

      # Get all transactions for this address ordered by date
      {:ok, tx_result} = AddressWatcher.Repo.query("""
        SELECT id, amount
        FROM transactions
        WHERE address = $1
        ORDER BY transaction_date ASC
      """, [address])

      # Calculate running balance for each transaction
      {final_balance, _} =
        Enum.reduce(tx_result.rows, {0, []}, fn [id, amount], {balance, ids} ->
          new_balance = balance + amount
          {new_balance, [{id, new_balance} | ids]}
        end)

      # Update each transaction with its new balance_after
      updated = Enum.reverse(elem(Enum.reduce(tx_result.rows, {0, []}, fn [id, amount], {balance, updates} ->
        new_balance = balance + amount

        # Update this transaction's balance_after
        {:ok, _} = AddressWatcher.Repo.query("""
          UPDATE transactions
          SET balance_after = $1
          WHERE id = $2
        """, [new_balance, id])

        {new_balance, [id | updates]}
      end), 1))

      IO.puts("Updated #{length(updated)} transactions for #{String.slice(address, 0, 10)}...")
      IO.puts("Final calculated balance: #{final_balance / 100_000_000} BTC")
    end

    IO.puts("\nAll transactions and balances have been updated successfully!")
  end
end

# Run the fixer
TransactionFixer.run()
