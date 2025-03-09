defmodule AddressWatcherWeb.AddressLiveHTML do

  import Phoenix.Component

  # Import helpers for formatting and styling
  import AddressWatcherWeb.AddressLiveHelpers
  import AddressWatcherWeb.Components.ChartHTML

  require Logger

  # Define the color functions that were previously in the main module
  def gold_color, do: "#C5A063"  # RGB 197, 160, 99
  def dark_grey_color, do: "#323232"  # RGB 50, 50, 50
  def background_color, do: "#121212"  # Almost black
  def text_color, do: "#E5E5E5"  # Light grey

  # Define the refresh rate functions
  def min_refresh, do: 5  # 5 seconds
  def max_refresh, do: 3600  # 1 hour

  def render(assigns) do
    # Debug output for chart data
    #if assigns[:tx_chart_data] && length(assigns.tx_chart_data) > 0 do
    #  IO.puts(assigns.tx_chart_data)
    #end

    ~H"""
    <!-- Google Fonts Import for Mulish -->
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Mulish:wght@300;400;500;600;700&display=swap">

    <div style={"background-color: #{background_color()}; color: #{text_color()}; min-height: 100vh; font-family: 'Mulish', sans-serif;"}>
      <div class="container mx-auto p-4">
        <h1 class="text-2xl font-bold mb-4" style={"color: #{gold_color()};"}>Bitcoin Address Watcher</h1>

        <form phx-submit="search" class="mb-6">
          <div class="flex gap-2">
            <input
              type="text"
              name="address"
              placeholder="Enter Bitcoin address"
              value={@address}
              class="flex-1 px-4 py-2 border rounded"
              style={"background-color: #{dark_grey_color()}; color: #{text_color()}; border-color: #444; font-family: 'Mulish', sans-serif;"}
            />
            <button
              type="submit"
              class="px-4 py-2 rounded"
              style={"background-color: #{gold_color()}; color: black; font-weight: 500; font-family: 'Mulish', sans-serif;"}
            >
              Search
            </button>
          </div>
        </form>

        <div class="mb-4">
          <button
            phx-click="load_from_db"
            class="px-4 py-2 rounded"
            style={"background-color: #{dark_grey_color()}; color: #{text_color()}; font-weight: 500; font-family: 'Mulish', sans-serif; border: 1px solid #444;"}
          >
            Load From Database
          </button>
        </div>

        <%= if @loading do %>
          <div class="my-4 text-center">
            <p>Loading...</p>
          </div>
        <% end %>

        <%= if @error do %>
          <div class="my-4 p-4 rounded" style="background-color: #3a1212; color: #f8b4b4;">
            <p><%= @error %></p>
          </div>
        <% end %>

        <%= if @address_info do %>
          <div class="p-4 rounded mb-6 border" style={"background-color: #{dark_grey_color()}; border-color: #444;"}>
            <h2 class="text-xl font-semibold mb-2" style={"color: #{gold_color()};"}>Address Info</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <p><strong style="color: #aaa;">Address:</strong> <%= @address_info["address"] %></p>
                <p><strong style="color: #aaa;">Final Balance:</strong> <%= format_btc(@address_info["final_balance"]) %> BTC</p>
                <%= if @current_price do %>
                  <p>
                    <strong style="color: #aaa;">Value (USD):</strong>
                    $<%= format_usd(@address_info["final_balance"], @current_price) %>
                  </p>
                <% end %>
              </div>
              <div>
                <p><strong style="color: #aaa;">Total Received:</strong> <%= format_btc(@address_info["total_received"]) %> BTC</p>
                <p><strong style="color: #aaa;">Total Transactions:</strong> <%= @address_info["n_tx"] %></p>
                <%= if @current_price do %>
                  <p>
                    <strong style="color: #aaa;">BTC Price:</strong>
                    $<%= format_price(@current_price) %>
                    <span style="color: #777; font-size: 0.75rem;">
                      (updated <%= format_relative_time(@price_last_updated) %>)
                    </span>
                  </p>
                <% end %>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            <!-- Balance History Chart - using our new component -->
            <div class="p-4 rounded border" style={"background-color: #{dark_grey_color()}; border-color: #444;"}>
              <.transaction_chart
                id="balance-chart"
                title={"Balance History - Transactions: #{@balance_chart_tx_count}"}
                data={
                  # Explicitly reverse to get newest first, then take
                  reversed_data = Enum.reverse(@tx_chart_data)
                  chart_data = reversed_data
                    |> Enum.take(@balance_chart_tx_count)
                    |> Enum.reverse()  # Put back in chronological order for chart
                    |> Enum.map(fn tx -> Map.take(tx, [:tx_id, :balance]) end)
                  chart_data
                }
                value_key={:balance}
                color={gold_color()}
                bg_color="#1A1A1A"
                text_color="#E5E5E5"
                y_format={:btc}
                tx_count={@balance_chart_tx_count}
                on_tx_count_change="update_chart_tx_count"
              />
            </div>

            <!-- Value History Chart - using our new component -->
            <div class="p-4 rounded border" style={"background-color: #{dark_grey_color()}; border-color: #444;"}>
              <.transaction_chart
                id="value-chart"
                title={"USD Value History - Transactions: #{@value_chart_tx_count}"}
                data={
                  # Explicitly reverse to get newest first, then take
                  reversed_data = Enum.reverse(@tx_chart_data)
                  chart_data = reversed_data
                    |> Enum.take(@value_chart_tx_count)
                    |> Enum.reverse()  # Put back in chronological order for chart
                    |> Enum.map(fn tx -> Map.take(tx, [:tx_id, :value]) end)
                  chart_data
                }
                value_key={:value}
                color={gold_color()}
                bg_color="#1A1A1A"
                text_color="#E5E5E5"
                y_format={:usd}
                tx_count={@value_chart_tx_count}
                on_tx_count_change="update_chart_tx_count"
              />
            </div>
          </div>

          <div class="mb-8">
            <h2 class="text-xl font-semibold mb-2" style={"color: #{gold_color()};"}>
              Transaction History
              <%= if assigns[:api_transaction_count] && assigns[:db_transaction_count] do %>
                <span class="text-sm font-normal" style="color: #aaa;">
                  (API: <%= @api_transaction_count %>, DB: <%= @db_transaction_count %>)
                </span>
              <% end %>
            </h2>
            <div class="overflow-x-auto">
              <table class="min-w-full border" style={"background-color: #{dark_grey_color()}; border-color: #444; font-family: 'Mulish', sans-serif;"}>
                <thead>
                  <tr style="background-color: #2A2A2A; color: #bbb;">
                    <th class="py-3 px-4 text-left text-sm uppercase" style="font-weight: 600;">Tx Hash</th>
                    <th class="py-3 px-4 text-right text-sm uppercase" style="font-weight: 600;">Amount (BTC)</th>
                    <th class="py-3 px-4 text-center text-sm uppercase" style="font-weight: 600;">Confirmations</th>
                    <th class="py-3 px-4 text-right text-sm uppercase" style="font-weight: 600;">Date</th>
                    <%= if assigns[:api_transaction_count] do %>
                      <th class="py-3 px-4 text-center text-sm uppercase" style="font-weight: 600;">Source</th>
                    <% end %>
                  </tr>
                </thead>
                <tbody style="color: #bbb;">
                  <%= for tx <- @transactions do %>
                    <tr class="border-b hover:bg-opacity-10" style={"border-color: #444; #{if tx["source"] == "db", do: "background-color: rgba(30,30,30,0.5);", else: ""}"}>
                      <td class="py-3 px-4 truncate max-w-[200px]">
                        <a
                          href={"https://www.blockchain.com/explorer/transactions/btc/#{tx["hash"]}"}
                          target="_blank"
                          style={"color: #{gold_color()}; text-decoration: none;"}
                          class="hover:underline"
                        >
                          <%= tx["hash"] %>
                        </a>
                      </td>
                      <td class="py-3 px-4 text-right">
                        <%= if tx["source"] == "db" do %>
                          <span style={if tx["db_amount"] > 0, do: "color: #4ADE80;", else: "color: #F87171;"}>
                            <%= format_btc_detailed(tx["db_amount"]) %>
                          </span>
                        <% else %>
                          <span style={tx_amount_color_style(tx, @address)}>
                            <%= format_transaction_amount_detailed(tx, @address) %>
                          </span>
                        <% end %>
                      </td>
                      <td class="py-3 px-4 text-center">
                        <%= tx["confirmations"] || 0 %>
                      </td>
                      <td class="py-3 px-4 text-right">
                        <%= format_date(tx["confirmed"] || tx["received"]) %>
                      </td>
                      <%= if assigns[:api_transaction_count] do %>
                        <td class="py-3 px-4 text-center">
                          <%= if tx["source"] == "api" do %>
                            <span class="px-2 py-1 rounded text-xs" style="background-color: rgba(197, 160, 99, 0.2); color: #C5A063;">
                              API
                            </span>
                          <% else %>
                            <span class="px-2 py-1 rounded text-xs" style="background-color: rgba(100, 149, 237, 0.2); color: #6495ED;">
                              DB
                            </span>
                          <% end %>
                        </td>
                      <% end %>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>

          <!-- API Rate Control Sliders at bottom -->
          <div class="mt-10 p-4 rounded border" style={"background-color: #{dark_grey_color()}; border-color: #444;"}>
            <h3 class="text-lg font-semibold mb-4" style={"color: #{gold_color()};"}>API Rate Controls</h3>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <!-- Address Refresh Rate Slider -->
              <div>
                <label class="block mb-2 text-sm font-medium" style="color: #aaa;">
                  Address Refresh Rate: <span style={"color: #{gold_color()}"}><%= @address_refresh_seconds %> seconds</span>
                </label>
                <input
                  type="range"
                  min={min_refresh()}
                  max={max_refresh()}
                  value={@address_refresh_seconds}
                  phx-change="update_address_refresh"
                  class="w-full h-2 rounded-lg appearance-none cursor-pointer"
                  style="background-color: #444;"
                />
                <div class="flex justify-between text-xs mt-1" style="color: #777;">
                  <span><%= min_refresh() %>s</span>
                  <span><%= div(max_refresh(), 60) %>m</span>
                  <span><%= max_refresh() %>s</span>
                </div>
              </div>

              <!-- Price Refresh Rate Slider -->
              <div>
                <label class="block mb-2 text-sm font-medium" style="color: #aaa;">
                  Price Refresh Rate: <span style={"color: #{gold_color()}"}><%= @price_refresh_seconds %> seconds</span>
                </label>
                <input
                  type="range"
                  min={min_refresh()}
                  max={max_refresh()}
                  value={@price_refresh_seconds}
                  phx-change="update_price_refresh"
                  class="w-full h-2 rounded-lg appearance-none cursor-pointer"
                  style="background-color: #444;"
                />
                <div class="flex justify-between text-xs mt-1" style="color: #777;">
                  <span><%= min_refresh() %>s</span>
                  <span><%= div(max_refresh(), 60) %>m</span>
                  <span><%= max_refresh() %>s</span>
                </div>
              </div>
            </div>

            <div class="mt-4 text-xs" style="color: #777;">
              <p>Adjust sliders to control API request frequency and avoid rate limits. Faster updates increase API usage.</p>
              <ul class="mt-1 list-disc list-inside">
                <li>BlockCypher API (address data): 3 req/sec, 200 req/hour, 2,000 req/day</li>
                <li>CoinGecko API (price data): 10-30 req/min depending on usage</li>
              </ul>
            </div>
          </div>

          <!-- Debug Panel at bottom -->
          <div class="mt-6 p-4 rounded border" style={"background-color: #{dark_grey_color()}; border-color: #444;"}>
            <h3 class="text-lg font-semibold mb-2" style={"color: #{gold_color()};"}>Debug Information</h3>
            <div class="text-xs font-mono p-2 rounded h-32 overflow-y-auto" style="background-color: #1a1a1a;">
              <%= for message <- @debug_messages do %>
                <div class="mb-1 text-gray-400"><%= message %></div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
