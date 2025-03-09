defmodule AddressWatcherWeb.AddressLiveHelpers do

  require Logger

  # Convert satoshis to BTC and format as string with full precision
  def format_btc(satoshis) when is_integer(satoshis) do
    btc_value = satoshis / 100_000_000
    :erlang.float_to_binary(btc_value, [decimals: 2])
  end

  # Handle other types with a default value
  def format_btc(_), do: "0.00"

  def format_usd(satoshis, price) when is_integer(satoshis) do
    price_float = case price do
      p when is_float(p) -> p
      p when is_integer(p) -> p / 1.0
      _ -> 0.0
    end

    value = satoshis * price_float / 100_000_000

    formatted_value = value
      |> :erlang.float_to_binary([decimals: 2])
      |> format_number_with_commas()

    formatted_value
  end

  def format_usd(_, _), do: "0.00"

  # Format BTC with 8 decimal places for transaction displays
  def format_btc_detailed(satoshis) when is_integer(satoshis) do
    btc_value = satoshis / 100_000_000
    :erlang.float_to_binary(btc_value, [decimals: 8])
  end

  # Handle other types with a default value
  def format_btc_detailed(_), do: "0.00000000"

  # Update transaction formatting for detailed view
  def format_transaction_amount_detailed(tx, address) do
    impact = calculate_transaction_impact(tx, address)

    # Apply proper sign and formatting with 8 decimal places
    cond do
      impact > 0 -> "+#{format_btc_detailed(impact)}"
      impact < 0 -> "#{format_btc_detailed(impact)}"
      true -> "0.00000000"
    end
  end

  # For DB transactions, use this function
  def format_db_amount_detailed(amount) when is_number(amount) do
    cond do
      amount > 0 -> "+#{format_btc_detailed(trunc(amount))}"
      amount < 0 -> "#{format_btc_detailed(trunc(amount))}"
      true -> "0.00000000"
    end
  end

  # Helper function to add commas to number strings
  def format_number_with_commas(number_string) do
    # Split the string into integer and decimal parts
    [integer_part, decimal_part] = String.split(number_string, ".")

    # Format integer part with commas
    formatted_integer = integer_part
      |> String.to_charlist()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.reverse/1)
      |> Enum.reverse()
      |> Enum.join(",")

    # Join the parts back together
    "#{formatted_integer}.#{decimal_part}"
  end

  def format_price(price) do
    # Ensure price is a float for display
    price_float = case price do
      p when is_float(p) -> p
      p when is_integer(p) -> p / 1.0
      _ -> 0.0
    end

    :erlang.float_to_binary(price_float, [decimals: 2])
  end

  def format_date(nil), do: "-"
  def format_date(date_string) do
    date_string
  end

  def format_relative_time(nil), do: "never"
  def format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} minutes ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)} hours ago"
      true -> "#{div(diff_seconds, 86400)} days ago"
    end
  end

  # Format transaction amount for display in BTC
  def format_transaction_impact_btc(tx, address) do
    # Get impact in satoshis
    impact_satoshis = calculate_transaction_impact(tx, address)

    # Convert to BTC and format
    impact_btc = impact_satoshis / 100_000_000

    # Return formatted string with sign
    cond do
      impact_btc > 0 -> "+#{:erlang.float_to_binary(impact_btc, [decimals: 8])}"
      impact_btc < 0 -> "#{:erlang.float_to_binary(impact_btc, [decimals: 8])}"
      true -> "0.00000000"
    end
  end

  # Format transaction amount for display
  def format_transaction_amount(tx, address) do
    impact = calculate_transaction_impact(tx, address)

    # Apply proper sign and formatting consistently
    cond do
      impact > 0 -> "+#{format_btc(impact)}"
      impact < 0 -> "#{format_btc(impact)}"
      true -> "0.00000000"
    end
  end

  # Determine color based on transaction impact
  def tx_amount_color_style(tx, address) do
    impact = calculate_transaction_impact(tx, address)

    cond do
      impact > 0 -> "color: #4ADE80;"  # Green for incoming
      impact < 0 -> "color: #F87171;"  # Red for outgoing
      true -> "color: #9CA3AF;"  # Gray for no change
    end
  end

  # Calculate how a transaction affected the address balance
  # Returns the net change to the address (positive or negative) in satoshis
  def calculate_transaction_impact(tx, address) do
    inputs = tx["inputs"] || []
    outputs = tx["outputs"] || []

    # Log detailed transaction data for debugging
    Logger.debug("Transaction: #{tx["hash"] || "unknown"}")
    Logger.debug("Inputs: #{inspect(inputs)}")
    Logger.debug("Outputs: #{inspect(outputs)}")

    # Sum all inputs (outgoing) from this address
    outgoing = inputs
              |> Enum.filter(fn input ->
                   addresses = input["addresses"] || []
                   Enum.member?(addresses, address)
                 end)
              |> Enum.reduce(0, fn input, acc ->
                   amount = input["output_value"] || 0
                   Logger.debug("Input from #{address}: #{amount} satoshis")
                   acc + amount
                 end)

    # Sum all outputs (incoming) to this address
    incoming = outputs
              |> Enum.filter(fn output ->
                   addresses = output["addresses"] || []
                   Enum.member?(addresses, address)
                 end)
              |> Enum.reduce(0, fn output, acc ->
                   amount = output["value"] || 0
                   Logger.debug("Output to #{address}: #{amount} satoshis")
                   acc + amount
                 end)

    net_impact = incoming - outgoing
    Logger.debug("Net impact: #{net_impact} satoshis (#{net_impact / 100_000_000} BTC)")

    net_impact
  end

  def fetch_historical_transactions(address, limit \\ 1000) do
    require Logger
    Logger.info("Fetching historical transactions for #{address} (limit: #{limit})")

    case Ecto.Adapters.SQL.query(AddressWatcher.Repo, """
      SELECT tx_hash, amount, confirmations, transaction_date
      FROM transactions
      WHERE address = $1
      ORDER BY transaction_date DESC
      LIMIT $2
    """, [address, limit]) do
      {:ok, result} ->
        Logger.info("Retrieved #{length(result.rows)} historical transactions from database for #{address}")

        # Convert from database format to the same format as API transactions
        Enum.map(result.rows, fn [tx_hash, amount, confirmations, tx_date] ->
          %{
            "hash" => tx_hash,
            "confirmations" => confirmations || 0,
            "db_amount" => amount,
            "source" => "db",
            "confirmed" => tx_date
          }
        end)

      {:error, error} ->
        Logger.error("Failed to retrieve historical transactions: #{inspect(error)}")
        # Return an empty list instead of :ok
        []
    end
  end
end
