defmodule AddressWatcherWeb.Components.ChartHTML do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :data, :list, required: true
  attr :value_key, :atom, required: true
  attr :color, :string, default: "#3b82f6"
  attr :bg_color, :string, default: "#1e293b"
  attr :text_color, :string, default: "#e2e8f0"
  attr :height, :string, default: "300px"
  attr :y_format, :any, default: nil
  attr :tx_count, :integer, default: 7
  attr :on_tx_count_change, :string, default: nil

  def transaction_chart(assigns) do
    # Process the data before rendering
    assigns = AddressWatcherWeb.Components.Chart.prepare_chart_data(assigns)

    ~H"""
    <div id={@id <> "-container"} class="flex flex-col">
      <h3 class="text-xl font-semibold mb-2" style={"color: #{@color};"}>
        <%= @title %>
      </h3>

      <div class="relative rounded" style={"height: #{@height}; background-color: #{@bg_color}; border-radius: 0.375rem; border: 1px solid #444;"}>
        <%= if @debug_message do %>
          <div class="absolute inset-0 flex items-center justify-center">
            <p style={"color: #{@text_color}; opacity: 0.5;"}>
              <%= @debug_message %>
            </p>
          </div>
        <% else %>
          <%= if Enum.empty?(@data) do %>
            <div class="absolute inset-0 flex items-center justify-center">
              <p style={"color: #{@text_color}; opacity: 0.5;"}>
                Waiting for transaction data...
              </p>
            </div>
          <% else %>
            <!-- Bar chart content - reduced padding at bottom -->
            <div class="absolute inset-0 px-4 pt-8 pb-2">
              <!-- Graph container with fixed spacing -->
              <div class="w-full h-full flex items-end">
                <%= for item <- @bar_data do %>
                  <!-- Bar column - fixed width, uniform spacing -->
                  <div class="flex flex-col items-center h-full" style={"width: #{100 / max(length(@bar_data), 1)}%;"}>
                    <div class="w-full px-1 flex flex-col items-center h-full relative">
                      <!-- The actual bar - with fixed width -->
                      <div
                        class="rounded-t mt-auto"
                        style={"height: #{item.height_pct}%; background-color: #{@color}; min-height: 4px; width: 80%;"}
                      ></div>

                      <!-- Value tooltip positioned absolutely on top of the bar with increased margin -->
                      <div
                        class="text-xs font-bold absolute text-center"
                        style={"color: #{@text_color}; bottom: #{item.height_pct}%; width: 80%; margin-bottom: 5px; transform: translateY(-100%);"}
                      >
                        <%= item.formatted_value |> String.slice(0..15) %>
                      </div>

                      <!-- Transaction number (starts with 1 for newest) -->
                      <div class="text-xs mt-1 w-full text-center truncate" style={"color: #{@text_color}; opacity: 0.7;"}>
                        <%= item.index + 1 %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- Transaction count slider -->
      <div class="mt-2 px-1">
        <div class="flex justify-between items-center">
          <span class="text-xs" style={"color: #{@text_color}; opacity: 0.7;"}>
            Transactions: <%= @tx_count %>
          </span>

          <input
            type="range"
            min="2"
            max="20"
            value={@tx_count}
            phx-click={@on_tx_count_change}
            phx-change={@on_tx_count_change}
            phx-value-chart_id={@id}
            class="mx-2 flex-1 h-1 rounded-lg appearance-none cursor-pointer"
            style="background-color: #444;"
          />

          <span class="text-xs" style={"color: #{@text_color}; opacity: 0.7;"}>
            2-20
          </span>
        </div>
      </div>
    </div>
    """
  end
end
