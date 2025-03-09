defmodule AddressWatcherWeb.AddressLive do
  use Phoenix.LiveView
  alias AddressWatcher.Api
  alias AddressWatcher.PriceService

  # Import the Chart component functions
  import AddressWatcherWeb.AddressLiveHelpers

  require Logger

  # Default values
  @default_address_refresh 60_000  # 1 minute
  @default_price_refresh 300_000   # 5 minutes
  @default_bitcoin_price 99_000.0   # Default BTC price for saved file data

  # Min and max values for sliders (in seconds)
  # Use them in a function to avoid the unused warning
  def min_refresh, do: 5  # 5 seconds
  def max_refresh, do: 3600  # 1 hour

  # Custom colors
  def gold_color, do: "#C5A063"  # RGB 197, 160, 99
  def dark_grey_color, do: "#323232"  # RGB 50, 50, 50
  def background_color, do: "#121212"  # Almost black
  def text_color, do: "#E5E5E5"  # Light grey

  @impl true
  def mount(_params, _session, socket) do
    Logger.info("Mount function called")

    socket = assign(socket,
      address: nil,
      address_info: nil,
      transactions: [],
      tx_chart_data: [],
      loading: false,
      error: nil,
      current_price: nil,
      price_last_updated: nil,
      debug_messages: [],
      address_refresh_rate: @default_address_refresh,
      price_refresh_rate: @default_price_refresh,
      address_refresh_seconds: div(@default_address_refresh, 1000),
      price_refresh_seconds: div(@default_price_refresh, 1000),
      balance_chart_tx_count: 7,  # Default number of transactions for balance chart
      value_chart_tx_count: 7,    # Default number of transactions for value chart
      address_timer_ref: nil,     # Timer reference for address refresh
      price_timer_ref: nil,       # Timer reference for price refresh
      data_source: :api,          # Default data source is API
      chart_update_timestamp: :os.system_time(:millisecond)  # For forcing chart re-renders
      )

    # Start price updates if connected and not using file data
    if connected?(socket) do
      Logger.info("Socket connected, sending fetch_price message")
      send(self(), :fetch_price)
    else
      Logger.info("Socket not yet connected")
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"address" => address}, socket) do
    Logger.info("Search event triggered for address: #{address}")

    # Start loading
    socket = assign(socket,
      loading: true,
      error: nil,
      tx_chart_data: [],
      data_source: :api,  # Reset data source to API when searching
      debug_messages: ["Search initiated for #{address}" | socket.assigns.debug_messages]
    )

    # Send ourselves a message to fetch the data
    Logger.info("Sending fetch_address message")
    send(self(), {:fetch_address, address})

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_address_refresh", %{"value" => value_str}, socket) do
    # Convert string value to integer seconds
    seconds = String.to_integer(value_str)
    # Convert seconds to milliseconds for timer
    milliseconds = seconds * 1000

    Logger.info("Updating address refresh rate to #{seconds} seconds (#{milliseconds}ms)")

    # Cancel any existing timer
    if Map.has_key?(socket.assigns, :address_timer_ref) and socket.assigns.address_timer_ref do
      Process.cancel_timer(socket.assigns.address_timer_ref)
    end

    # Set up new timer with the updated rate
    timer_ref = if socket.assigns.address do
      Process.send_after(self(), {:refresh, socket.assigns.address}, milliseconds)
    end

    socket = assign(socket,
      address_refresh_rate: milliseconds,
      address_refresh_seconds: seconds,
      address_timer_ref: timer_ref,
      debug_messages: ["Address refresh rate updated to #{seconds} seconds" | socket.assigns.debug_messages]
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_price_refresh", %{"value" => value_str}, socket) do
    # Convert string value to integer seconds
    seconds = String.to_integer(value_str)
    # Convert seconds to milliseconds for timer
    milliseconds = seconds * 1000

    Logger.info("Updating price refresh rate to #{seconds} seconds (#{milliseconds}ms)")

    # Cancel any existing timer
    if Map.has_key?(socket.assigns, :price_timer_ref) and socket.assigns.price_timer_ref do
      Process.cancel_timer(socket.assigns.price_timer_ref)
    end

    # Set up new timer with the updated rate
    timer_ref = Process.send_after(self(), :fetch_price, milliseconds)

    socket = assign(socket,
      price_refresh_rate: milliseconds,
      price_refresh_seconds: seconds,
      price_timer_ref: timer_ref,
      debug_messages: ["Price refresh rate updated to #{seconds} seconds" | socket.assigns.debug_messages]
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_from_db", _params, socket) do
    # Find the address with the most transactions in the database
    query = """
    SELECT address, COUNT(*) as tx_count
    FROM transactions
    GROUP BY address
    ORDER BY tx_count DESC
    LIMIT 1
    """

    case Ecto.Adapters.SQL.query(AddressWatcher.Repo, query) do
      {:ok, %{rows: [[address, count]]}} ->
        Logger.info("Loading top address from DB: #{address} with #{count} transactions")

        # Get complete transaction history with balance_after, sorted chronologically
        complete_query = """
        SELECT tx_hash, amount, balance_after, transaction_date
        FROM transactions
        WHERE address = $1
        ORDER BY transaction_date ASC
        """

        case Ecto.Adapters.SQL.query(AddressWatcher.Repo, complete_query, [address]) do
          {:ok, %{rows: transactions}} ->
            # Current balance from most recent transaction
            current_balance = case List.last(transactions) do
              [_, _, balance, _] -> balance
              _ -> 0
            end

            # Get visual transaction data for display
            db_transactions = fetch_historical_transactions(address, 1000)

            # Ensure transactions are unique by hash
            unique_transactions = Enum.uniq_by(db_transactions, fn tx -> tx["hash"] end)

            # Log the deduplication results
            Logger.info("Deduplication: #{length(db_transactions)} transactions reduced to #{length(unique_transactions)} unique transactions")

            # Cancel any existing price timer
            if Map.has_key?(socket.assigns, :price_timer_ref) and socket.assigns.price_timer_ref do
              Process.cancel_timer(socket.assigns.price_timer_ref)
            end

            # Use the default Bitcoin price
            default_price = @default_bitcoin_price
            now = DateTime.utc_now()

            # Create a basic address info structure
            address_info = %{
              "address" => address,
              "final_balance" => current_balance,
              "n_tx" => count,
              "total_received" => 0
            }

            # Create chart data directly from balance_after values in transactions
            raw_chart_data = Enum.map(transactions, fn [tx_hash, amount, balance, date] ->
              btc_balance = balance / 100_000_000
              btc_amount = amount / 100_000_000

              %{
                tx_id: tx_hash,
                balance: btc_balance,
                value: btc_balance * default_price,
                timestamp: date,
                tx_amount: btc_amount
              }
            end)

            # Remove transactions with identical balances - keep only the earliest one
            # This creates a more meaningful chart with only balance-changing points
            chart_data =
              raw_chart_data
              |> Enum.reduce([], fn point, acc ->
                # Only add this point if its balance differs from the last one
                case acc do
                  [] -> [point]  # Always include the first point
                  [prev | _] ->
                    if abs(point.balance - prev.balance) < 0.000001 do
                      # Skip this point as it has the same balance as the previous one
                      acc
                    else
                      [point | acc]
                    end
                end
              end)
              |> Enum.reverse()  # Reverse back to chronological order

            # Always add current balance point
            current_btc_balance = current_balance / 100_000_000
            chart_data = chart_data ++ [%{
              tx_id: "current",
              balance: current_btc_balance,
              value: current_btc_balance * default_price,
              timestamp: DateTime.utc_now() |> DateTime.to_string(),
              tx_amount: 0.0
            }]

            Logger.info("Generated #{length(chart_data)} chart data points from DB balance history")

            socket = socket
            |> assign(
              address: address,
              address_info: address_info,
              transactions: unique_transactions,  # Use deduplicated transactions
              tx_chart_data: chart_data,
              current_price: default_price,
              price_last_updated: now,
              price_timer_ref: nil,
              data_source: :db,
              loading: false,
              api_transaction_count: 0,
              db_transaction_count: length(unique_transactions), # Update count to match deduplicated list
              debug_messages: ["Loaded address #{address} from database with default BTC price: $#{default_price}" | socket.assigns.debug_messages]
            )

            {:noreply, socket}

          {:error, db_error} ->
            socket = assign(socket,
              error: "Failed to query transaction data: #{inspect(db_error)}",
              debug_messages: ["DB query error: #{inspect(db_error)}" | socket.assigns.debug_messages]
            )

            {:noreply, socket}
        end

      {:ok, %{rows: []}} ->
        # No transactions in the database
        socket = assign(socket,
          error: "No addresses found in the database",
          debug_messages: ["Database is empty - no addresses found" | socket.assigns.debug_messages]
        )

        {:noreply, socket}

      {:error, reason} ->
        socket = assign(socket,
          error: "Failed to query database: #{inspect(reason)}",
          debug_messages: ["Database query error: #{inspect(reason)}" | socket.assigns.debug_messages]
        )

        {:noreply, socket}
    end
  end
  @impl true
  def handle_event("update_chart_tx_count", %{"value" => value_str, "chart_id" => chart_id}, socket) do
    # Convert value to integer
    tx_count = String.to_integer(value_str)

    # Debug info
    IO.puts("\n==== CHART SLIDER CHANGED ====")
    IO.puts("Chart ID: #{chart_id}")
    IO.puts("New tx_count: #{tx_count}")
    IO.puts("Current data points: #{length(socket.assigns.tx_chart_data)}")

    # Update the appropriate chart's transaction count
    socket = case chart_id do
      "balance-chart" ->
        IO.puts("Updating balance chart transaction count")
        assign(socket, :balance_chart_tx_count, tx_count)
      "value-chart" ->
        IO.puts("Updating value chart transaction count")
        assign(socket, :value_chart_tx_count, tx_count)
      _ ->
        IO.puts("Unknown chart ID")
        socket
    end

    # Force template re-evaluation by adding a unique timestamp to the assigns
    socket = assign(socket, :chart_update_timestamp, :os.system_time(:millisecond))

    # Add debug message
    socket = assign(socket,
      debug_messages: ["Updated #{chart_id} to show #{tx_count} transactions at #{:os.system_time(:millisecond)}" | socket.assigns.debug_messages]
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:fetch_address, address}, socket) do
    Logger.info("Fetching data for address: #{address}")

    socket = assign(socket,
      debug_messages: ["Fetching data for #{address}" | socket.assigns.debug_messages]
    )

    Logger.info("Calling Api.fetch_address_with_transactions")

    result = Api.fetch_address_with_transactions(address)
    Logger.info("API call result: #{inspect(result |> elem(0))}")

    case result do
      {:ok, data} ->
        Logger.info("Successfully fetched data for #{address}")
        Logger.info("Address data: Final balance: #{inspect(data["final_balance"])}")
        Logger.info("Transactions count from API: #{length(Map.get(data, "txs", []))}")
        Logger.info("Successfully fetched data for #{address}")

        # Schedule refresh using the dynamic refresh rate
        timer_ref = if connected?(socket) do
          refresh_rate = socket.assigns.address_refresh_rate
          Logger.info("Scheduling refresh in #{refresh_rate}ms")
          Process.send_after(self(), {:refresh, address}, refresh_rate)
        end

        # Get the balance and transaction data from API
        balance = data["final_balance"] || 0
        api_transactions = Map.get(data, "txs", [])

        # Tag API transactions for display
        api_transactions = Enum.map(api_transactions, fn tx ->
          Map.put(tx, "source", "api")
        end)

        # Fetch historical data from database
        db_transactions = fetch_historical_transactions(address, 1000)

        # Store API transactions in the database
        Logger.info("Storing #{length(api_transactions)} API transactions in database")
        AddressWatcher.TransactionService.process_transactions(
          address,
          api_transactions,
          balance,
          socket.assigns.current_price
        )

        # Only include DB transactions that aren't in the API response
        # More flexible deduplication
        unique_db_transactions = Enum.filter(db_transactions, fn db_tx ->
          db_hash = db_tx["hash"]
          # Log this comparison for debugging
          Logger.debug("Checking DB tx hash: #{db_hash}")
          !Enum.any?(api_transactions, fn api_tx ->
            api_hash = api_tx["hash"]
            Logger.debug("Against API tx hash: #{api_hash}")
            db_hash == api_hash
          end)
        end)

        # Combine API and DB transactions, with API first (most recent)
        combined_transactions = api_transactions ++ unique_db_transactions

        Logger.info("API transactions: #{length(api_transactions)}")
        Logger.info("DB transactions: #{length(db_transactions)}")
        Logger.info("Unique DB transactions: #{length(unique_db_transactions)}")
        Logger.info("Combined transactions: #{length(combined_transactions)}")

        # Generate chart data with accurate balance history
        tx_chart_data = generate_chart_data(combined_transactions, address, balance, socket.assigns.current_price)

        Logger.info("Generated #{length(tx_chart_data)} data points for charts")
        Logger.info("Combined #{length(combined_transactions)} transactions for display")

        socket = socket
        |> assign(
          address: address,
          address_info: data,
          transactions: combined_transactions,
          api_transaction_count: length(api_transactions),
          db_transaction_count: length(unique_db_transactions),
          tx_chart_data: tx_chart_data,
          loading: false,
          address_timer_ref: timer_ref,
          chart_update_timestamp: :os.system_time(:millisecond),  # Force chart update
          debug_messages: ["Data fetched successfully. Balance: #{balance} satoshis" | socket.assigns.debug_messages]
        )

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to fetch address data: #{inspect(reason)}")

        socket = socket
        |> assign(
          loading: false,
          error: "Failed to load address: #{inspect(reason)}",
          debug_messages: ["Error fetching data: #{inspect(reason)}" | socket.assigns.debug_messages]
        )

        {:noreply, socket}
    end
  end

  # Don't schedule next price update if we loaded from file
  @impl true
  def handle_info(:fetch_price, %{assigns: %{data_source: :file}} = socket) do
    # If data was loaded from a file, don't fetch new prices
    {:noreply, socket}
  end

  @impl true
  def handle_info(:fetch_price, socket) do
    Logger.info("Fetching Bitcoin price")

    # Schedule next price update using the dynamic refresh rate
    timer_ref = if connected?(socket) do
      refresh_rate = socket.assigns.price_refresh_rate
      Process.send_after(self(), :fetch_price, refresh_rate)
    end

    case PriceService.fetch_bitcoin_price() do
      {:ok, price} ->
        Logger.info("Successfully fetched Bitcoin price: $#{price}")
        now = DateTime.utc_now()

        # Update transaction USD values if we have an address
        tx_chart_data = if socket.assigns.address do
          transactions = socket.assigns.transactions
          balance = socket.assigns.address_info["final_balance"] || 0

          # Regenerate chart data with new price
          generate_chart_data(transactions, socket.assigns.address, balance, price)

        else
          socket.assigns.tx_chart_data
        end

        IO.puts("New chart data after CoinGecko API call")
        IO.puts(tx_chart_data)

        socket = socket
        |> assign(
          current_price: price,
          price_last_updated: now,
          tx_chart_data: tx_chart_data,
          price_timer_ref: timer_ref,
          chart_update_timestamp: :os.system_time(:millisecond),  # Force chart update
          debug_messages: ["Price updated: $#{price}" | socket.assigns.debug_messages]
        )

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to fetch Bitcoin price: #{inspect(reason)}")

        socket = socket
        |> assign(
          price_timer_ref: timer_ref,
          debug_messages: ["Failed to fetch price: #{inspect(reason)}" | socket.assigns.debug_messages]
        )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:refresh, address}, socket) do
    Logger.info("Refresh triggered for address: #{address}")

    # Only refresh if we're still looking at the same address
    if socket.assigns.address == address do
      send(self(), {:fetch_address, address})

      socket = assign(socket,
        loading: true,
        debug_messages: ["Refreshing data for #{address}" | socket.assigns.debug_messages]
      )
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    AddressWatcherWeb.AddressLiveHTML.render(assigns)
  end

  # Helper functions
  defp generate_chart_data(transactions, address, current_balance, current_price) do
    # Convert current_balance from satoshis to BTC for display in charts
    current_btc_balance = current_balance / 100_000_000

    # Create a list of the recent transactions, ensuring exact match with transaction data
    # Sort by date (newest first)
    sorted_txs = transactions
      |> Enum.sort_by(fn tx ->
            date_str = tx["confirmed"] || tx["received"] || DateTime.utc_now() |> DateTime.to_string()
            # Sort in descending order (newest first)
            {date_str, tx["hash"]}
          end, :desc)

    # Take just the most recent transactions for the chart
    recent_txs = Enum.take(sorted_txs, 20)

    # First, add the current balance as the starting point
    # This ensures we show the most up-to-date balance from the API
    initial_data_point = %{
      tx_id: "current",
      balance: current_btc_balance,
      value: current_btc_balance * (current_price || 0),
      timestamp: DateTime.utc_now() |> DateTime.to_string(),
      tx_amount: 0.0
    }

    # Start with the current balance and work backwards through transactions
    {_, chart_data} = Enum.reduce(recent_txs, {current_btc_balance, [initial_data_point]}, fn tx, {running_balance, acc} ->
      # Get transaction amount based on its source
      tx_amount_btc = if tx["source"] == "db" do
        # For DB transactions, use the stored amount directly
        tx["db_amount"] / 100_000_000
      else
        # For API transactions, calculate impact from inputs/outputs
        impact_satoshis = calculate_transaction_impact(tx, address)
        impact_btc = impact_satoshis / 100_000_000

        # Add debug info
        Logger.info("API TX: #{String.slice(tx["hash"] || "", 0, 8)}..., Impact: #{impact_btc} BTC")

        impact_btc
      end

      # Calculate balance before this transaction (subtract the impact)
      prev_balance = running_balance - tx_amount_btc

      # Calculate USD value
      usd_value = if current_price do
        prev_balance * current_price  # Use previous balance for this point
      else
        0.0
      end

      # Create a data point for the balance BEFORE this transaction
      data_point = %{
        tx_id: tx["hash"],
        balance: prev_balance, # This is the balance BEFORE this transaction
        value: usd_value,
        timestamp: tx["confirmed"] || tx["received"],
        tx_amount: tx_amount_btc # Store the transaction amount for debugging
      }

      # Return updated running balance and accumulator with new data point
      {prev_balance, [data_point | acc]}
    end)

    # Return the chart data (newest first)
    chart_data
  end
end
