defmodule AddressWatcher.Api do
  require Logger

  @base_url "https://api.blockcypher.com/v1/btc/main"

  def fetch_address(address) do
    url = "#{@base_url}/addrs/#{address}"
    Logger.info("Fetching basic address info from: #{url}")

    case make_request(url) do
      {:ok, response} ->
        Logger.info("Successfully fetched basic address info")
        {:ok, response}

      {:error, reason} ->
        Logger.error("Error fetching address info: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def fetch_address_with_transactions(address) do
    url = "#{@base_url}/addrs/#{address}/full"
    Logger.info("Fetching detailed address info from: #{url}")

    case make_request(url) do
      {:ok, response} ->
        Logger.info("Successfully fetched address with transactions")
        {:ok, response}

      {:error, reason} ->
        Logger.error("Error fetching address with transactions: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Use the Erlang HTTP client which works on your system
  defp make_request(url) do
    Logger.info("Making request to: #{url}")

    # Convert string URL to charlist for Erlang
    url_charlist = String.to_charlist(url)

    # Ensure apps are started
    :ssl.start()
    :inets.start()

    ssl_options = [
      verify: :verify_none,
      versions: [:"tlsv1.2"]
    ]

    http_options = [
      ssl: ssl_options,
      timeout: 30000
    ]

    Logger.info("Sending HTTP request with options: #{inspect(http_options)}")

    case :httpc.request(:get, {url_charlist, []}, http_options, body_format: :binary) do
      {:ok, {{_, 200, _}, headers, body}} ->
        Logger.info("Request successful, received #{byte_size(body)} bytes")
        Logger.debug("Response headers: #{inspect(headers)}")

        case Jason.decode(body) do
          {:ok, decoded} ->
            Logger.info("Successfully decoded JSON response")
            {:ok, decoded}

          {:error, error} ->
            Logger.error("Error decoding JSON: #{inspect(error)}")
            {:error, "JSON decode error: #{inspect(error)}"}
        end

      {:ok, {{_, status_code, reason}, headers, body}} ->
        Logger.error("HTTP error: #{status_code} #{reason}, Headers: #{inspect(headers)}")
        Logger.error("Response body: #{inspect(body)}")
        {:error, "HTTP error #{status_code}: #{body}"}

      {:error, reason} ->
        Logger.error("Request error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
