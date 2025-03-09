defmodule AddressWatcherWeb.Components.Chart do
  use Phoenix.Component

  # Safe value formatting
  def format_value(value, _) when is_nil(value), do: "nil"
  def format_value(value, _) when not is_number(value), do: "#{inspect(value)}"

  def format_value(value, :btc) do
    "#{:erlang.float_to_binary(value, [decimals: 0])} ₿"
  end

  def format_value(value, :usd) do
    cond do
      value >= 1_000_000_000 -> "$#{:erlang.float_to_binary(value / 1_000_000_000, [decimals: 3])} B"
      value >= 1_000_000 -> "$#{:erlang.float_to_binary(value / 1_000_000, [decimals: 3])} M"
      value >= 1_000 -> "$#{:erlang.float_to_binary(value / 1_000, [decimals: 3])} K"
      true -> "$#{:erlang.float_to_binary(value, [decimals: 2])}"
    end
  end

  def format_value(value, _) do
    "#{:erlang.float_to_binary(value, [decimals: 2])}"
  end

  # Prepare data for rendering
  def prepare_chart_data(assigns) do
    # Set default tx_count if not provided
    assigns = Map.put_new(assigns, :tx_count, 7)

    if Enum.empty?(assigns.data) do
      assigns |> Map.put(:debug_message, nil)
    else
      # Take the first tx_count items without reversing
      recent_data = assigns.data |> Enum.take(assigns.tx_count)

      # Extract all values for min/max calculation
      values =
        recent_data
        |> Enum.map(fn point -> Map.get(point, assigns.value_key) end)
        |> Enum.filter(&(is_number(&1) and not is_nil(&1)))

      if Enum.empty?(values) do
        assigns |> Map.put(:debug_message, "No valid values found")
      else
        min_value = Enum.min(values)
        max_value = Enum.max(values)
        value_range = max(max_value - min_value, 0.000001) # Prevent division by zero

        # Calculate bar heights
        bar_data =
          recent_data
          |> Enum.with_index()
          |> Enum.map(fn {point, index} ->
            value = Map.get(point, assigns.value_key)

            # Calculate percentage height
            height_pct =
              cond do
                is_nil(value) -> 5  # Minimal height for nil
                not is_number(value) -> 5  # Minimal height for non-numbers
                value_range <= 0.000001 -> 50  # Medium height when all values are the same
                true ->
                  # Exaggerate differences for better visibility
                  percent_of_range = (value - min_value) / value_range
                  5 + (percent_of_range * 85)  # Scale between 5% and 90%
              end

            point
            |> Map.put(:height_pct, height_pct)
            |> Map.put(:index, index)
            |> Map.put(:raw_value, value)
            |> Map.put(:formatted_value, format_value(value, assigns.y_format))
          end)

        assigns
        |> Map.put(:bar_data, bar_data)
        |> Map.put(:min_value, min_value)
        |> Map.put(:max_value, max_value)
        |> Map.put(:debug_message, nil)
      end
    end
  end
end
