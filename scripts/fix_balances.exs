# Save as fix_balances.exs and run with: mix run fix_balances.exs

defmodule BalanceRecalculator do
  require Logger

  @target_address "bc1qk7fy6qumtdkjy765ujxqxe0my55ake0zefa2dmt6sjx2sr098d8qf26ufn"
  @correct_final_balance 1937578498316  # Satoshis, not multiplied by 100_000_000

  def run do
    IO.puts("\n=== Bitcoin Address Balance Recalculation ===")
    IO.puts("This script will recalculate all balance_after values for address: #{@target_address}")
    IO.puts("Starting with a final balance of: #{@correct_final_balance / 100_000_000} BTC")

    case IO.gets("This will update your database. Continue? (yes/no): ") |> String.trim() |> String.downcase() do
      "yes" ->
        recalculate_balances()
      _ ->
        IO.puts("Operation cancelled.")
    end
  end

  defp recalculate_balances do
    # Get all transactions for the address in descending date order (newest first)
    query = """
    SELECT id, tx_hash, amount, transaction_date
    FROM transactions
    WHERE address = $1
    ORDER BY transaction_date DESC
    """

    case Ecto.Adapters.SQL.query(AddressWatcher.Repo, query, [@target_address]) do
      {:ok, %{rows: transactions}} ->
        IO.puts("Found #{length(transactions)} transactions to update.")

        # Start with the correct final balance and work backwards
        {updated_count, _} = Enum.reduce(transactions, {0, @correct_final_balance}, fn [id, tx_hash, amount, date], {count, running_balance} ->
          # For debugging, show the transaction being processed
          IO.puts("Processing transaction #{String.slice(tx_hash, 0, 8)}... | Amount: #{amount / 100_000_000} BTC | Date: #{date}")

          # Update this transaction's balance_after with current running_balance
          case Ecto.Adapters.SQL.query(
            AddressWatcher.Repo,
            "UPDATE transactions SET balance_after = $1 WHERE id = $2",
            [running_balance, id]
          ) do
            {:ok, %{num_rows: 1}} ->
              # Success, calculate previous balance by subtracting the transaction amount
              # Since we're going backward in time:
              # Previous balance = Current balance - Current transaction amount
              prev_balance = running_balance - amount

              IO.puts("  Updated balance_after to #{running_balance / 100_000_000} BTC | Next balance will be: #{prev_balance / 100_000_000} BTC")

              # Continue with updated count and previous balance
              {count + 1, prev_balance}

            {:error, error} ->
              IO.puts("  Error updating transaction #{id}: #{inspect(error)}")
              {count, running_balance}
          end
        end)

        IO.puts("\n=== Balance Recalculation Complete ===")
        IO.puts("Successfully updated #{updated_count} of #{length(transactions)} transactions.")

      {:error, error} ->
        IO.puts("Error querying transactions: #{inspect(error)}")
    end
  end
end

# Run the script
BalanceRecalculator.run()
