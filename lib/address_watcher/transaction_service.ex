defmodule AddressWatcher.TransactionService do
  alias AddressWatcher.Repo
  alias AddressWatcher.Transaction
  import Ecto.Query
  require Logger

  @doc """
  Process new transactions for an address.
  Returns a tuple with :ok and the list of transaction data points.
  """
  def process_transactions(address, transactions, current_balance, current_price) do
    # First, get existing transactions for this address
    existing_tx_hashes = get_existing_tx_hashes(address)
    Logger.info("Found #{length(existing_tx_hashes)} existing transactions for #{address}")

    # Filter out transactions we've already processed
    new_txs =
      Enum.filter(transactions, fn tx ->
        tx_hash = tx["hash"]
        !Enum.member?(existing_tx_hashes, tx_hash)
      end)

    Logger.info("Processing #{length(new_txs)} new transactions for #{address}")

    # Process any new transactions
    if length(new_txs) > 0 do
      # Sort transactions by date if available
      sorted_txs =
        Enum.sort_by(new_txs, fn tx ->
          date_str =
            tx["confirmed"] || tx["received"] || DateTime.utc_now() |> DateTime.to_string()

          date_str
        end)

      # Process each transaction and store in DB
      _result =
        Enum.reduce(sorted_txs, current_balance, fn tx, balance_acc ->
          # Calculate the amount for this specific transaction
          amount = calculate_transaction_amount(tx, address)

          # Update the running balance for this transaction
          new_balance = balance_acc - amount

          # Calculate USD value if price is available
          value_usd =
            if current_price do
              new_balance * current_price / 100_000_000
            else
              nil
            end

          # Get confirmation count
          confirmations = tx["confirmations"] || 0

          # Get transaction date
          date_str =
            tx["confirmed"] || tx["received"] || DateTime.utc_now() |> DateTime.to_string()

          {:ok, tx_date, _} = DateTime.from_iso8601(date_str)

          # Store in database
          tx_params = %{
            tx_hash: tx["hash"],
            address: address,
            amount: amount,
            confirmations: confirmations,
            balance_after: new_balance,
            value_usd: value_usd,
            transaction_date: tx_date,
            tx_data: tx
          }

          case Repo.insert(Transaction.changeset(%Transaction{}, tx_params)) do
            {:ok, _} ->
              Logger.info("Saved transaction #{tx["hash"]} for #{address}")

            {:error, changeset} ->
              Logger.error("Failed to save transaction: #{inspect(changeset.errors)}")
          end

          # Return the new balance for the next iteration
          new_balance
        end)
    end

    # Get all transactions for the address (including newly added ones)
    # Limited to most recent 10 for the chart
    get_transaction_chart_data(address)
  end

  @doc """
  Gets the most recent transactions for the chart.
  Returns list of transaction data suitable for charting.
  """
  def get_transaction_chart_data(address) do
    Logger.info("Getting chart data for address #{address}")

    query =
      from t in Transaction,
        where: t.address == ^address,
        order_by: [desc: t.transaction_date],
        limit: 10

    transactions = Repo.all(query)

    # Map to the format needed by charts
    Enum.map(transactions, fn tx ->
      %{
        tx_id: tx.tx_hash,
        amount: tx.amount,
        balance: tx.balance_after,
        value: tx.value_usd,
        confirmations: tx.confirmations,
        date: tx.transaction_date
      }
    end)
  end

  # Get existing transaction hashes to avoid duplicates
  defp get_existing_tx_hashes(address) do
    query =
      from t in Transaction,
        where: t.address == ^address,
        select: t.tx_hash

    Repo.all(query)
  end

  # Calculate the net amount of a transaction from the address perspective
  defp calculate_transaction_amount(tx, address) do
    inputs = tx["inputs"] || []
    outputs = tx["outputs"] || []

    input_amount =
      inputs
      |> Enum.filter(fn input ->
        (input["addresses"] || []) |> Enum.member?(address)
      end)
      |> Enum.reduce(0, fn input, acc ->
        acc + (input["output_value"] || 0)
      end)

    output_amount =
      outputs
      |> Enum.filter(fn output ->
        (output["addresses"] || []) |> Enum.member?(address)
      end)
      |> Enum.reduce(0, fn output, acc ->
        acc + (output["value"] || 0)
      end)

    output_amount - input_amount
  end
end
