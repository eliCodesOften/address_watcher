# Save as fetch_address_paginated.exs and run with: mix run fetch_address_paginated.exs

defmodule PaginatedAddressFetcher do
  @max_pages 20  # Safety limit to prevent excessive API calls

  def run do
    # Prompt for address input
    IO.puts("\n=== Bitcoin Address Transaction Fetcher (Paginated) ===")
    address = IO.gets("Enter a Bitcoin address: ") |> String.trim()

    if String.length(address) < 26 do
      IO.puts("Invalid Bitcoin address. Addresses should be at least 26 characters.")
      run()
    else
      # Start with first page
      fetch_pages(address, 0, 0)

      # Ask if user wants to fetch another address
      case IO.gets("Fetch another address? (y/n): ") |> String.trim() |> String.downcase() do
        "y" -> run()
        _ ->
          # Show summary
          {:ok, count} = AddressWatcher.Repo.query("SELECT COUNT(*) FROM transactions")
          [[total]] = count.rows

          {:ok, address_count} = AddressWatcher.Repo.query(
            "SELECT COUNT(DISTINCT address) FROM transactions"
          )
          [[total_addresses]] = address_count.rows

          IO.puts("\n=== Database Summary ===")
          IO.puts("Total transactions: #{total}")
          IO.puts("Total unique addresses: #{total_addresses}")
          IO.puts("Thanks for using the Bitcoin Address Fetcher!")
      end
    end
  end

  defp fetch_pages(address, page, total_processed) when page < @max_pages do
    IO.puts("\nFetching page #{page + 1} for #{address}...")

    # Build URL with paging parameters
    # BlockCypher API uses 'before' parameter for tx_hash-based pagination
    # But we're using a simpler numeric offset-based approach here
    url = "https://api.blockcypher.com/v1/btc/main/addrs/#{address}/full?limit=50&offset=#{page * 50}"

    url_charlist = String.to_charlist(url)
    :ssl.start()
    :inets.start()

    case :httpc.request(:get, {url_charlist, []}, [ssl: [verify: :verify_none], timeout: 30000], body_format: :binary) do
      {:ok, {{_, 200, _}, _, body}} ->
        {:ok, data} = Jason.decode(body)

        balance = data["final_balance"] || 0
        transactions = Map.get(data, "txs", [])

        # Get current Bitcoin price for USD value calculation
        price_result = AddressWatcher.PriceService.fetch_bitcoin_price()

        price = case price_result do
          {:ok, p} -> p
          _ -> 50000.0  # Default fallback price if fetching fails
        end

        # Store transactions in database
        AddressWatcher.TransactionService.process_transactions(
          address,
          transactions,
          balance,
          price
        )

        new_total = total_processed + length(transactions)
        IO.puts("Processed #{length(transactions)} transactions for page #{page + 1}")
        IO.puts("Total transactions processed so far: #{new_total}")

        # Only continue if we got some transactions
        if length(transactions) > 0 do
          # Ask user if they want to fetch the next page
          case IO.gets("Press ENTER to fetch next page or type 'exit' to stop: ") |> String.trim() do
            "exit" ->
              IO.puts("Pagination stopped at user request.")
              display_results(address)
            _ ->
              # Wait a bit to avoid rate limits
              :timer.sleep(1000)
              fetch_pages(address, page + 1, new_total)
          end
        else
          IO.puts("No more transactions found.")
          display_results(address)
        end

      {:ok, {{_, status_code, _}, _, body}} ->
        IO.puts("API error: HTTP #{status_code}")
        IO.puts("Response: #{body}")
        display_results(address)

      {:error, reason} ->
        IO.puts("Error fetching data: #{inspect(reason)}")
        display_results(address)
    end
  end

  defp fetch_pages(address, page, total_processed) do
    IO.puts("Reached maximum page limit (#{@max_pages}). Stopping pagination.")
    display_results(address)
  end

  defp display_results(address) do
    # Get total count for this address
    {:ok, count_result} = AddressWatcher.Repo.query(
      "SELECT COUNT(*) FROM transactions WHERE address = $1",
      [address]
    )
    [[addr_tx_count]] = count_result.rows

    IO.puts("\n=== Summary for #{address} ===")
    IO.puts("Total transactions in database for this address: #{addr_tx_count}")
  end
end

# Start the interactive process
PaginatedAddressFetcher.run()
