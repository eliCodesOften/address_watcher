defmodule AddressWatcher.PriceService do
  require Logger

  @coingecko_api "https://api.coingecko.com/api/v3"

  def fetch_bitcoin_price do
    url = "#{@coingecko_api}/simple/price?ids=bitcoin&vs_currencies=usd"

    Logger.info("Fetching Bitcoin price from CoinGecko")

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
      timeout: 15000
    ]

    case :httpc.request(:get, {url_charlist, []}, http_options, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, %{"bitcoin" => %{"usd" => price}}} ->
            # Convert to float if it's not already
            price_float =
              case price do
                p when is_float(p) ->
                  p

                # Convert integer to float
                p when is_integer(p) ->
                  p / 1.0

                _ ->
                  Logger.error("Unexpected price format: #{inspect(price)}")
                  # Fallback price
                  50000.0
              end

            {:ok, price_float}

          {:ok, other} ->
            Logger.error("Unexpected response format: #{inspect(other)}")
            {:error, :invalid_response_format}

          error ->
            Logger.error("Error parsing JSON: #{inspect(error)}")
            {:error, :json_parse_error}
        end

      {:ok, {{_, status_code, _}, _headers, body}} ->
        Logger.error("API error: HTTP #{status_code}, #{body}")
        {:error, "HTTP error #{status_code}"}

      {:error, reason} ->
        Logger.error("Request error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
