defmodule AddressWatcher.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transactions" do
    field :tx_hash, :string
    field :address, :string
    field :amount, :integer
    field :confirmations, :integer
    field :balance_after, :integer
    field :value_usd, :float
    field :transaction_date, :utc_datetime
    field :tx_data, :map

    timestamps()
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :tx_hash,
      :address,
      :amount,
      :confirmations,
      :balance_after,
      :value_usd,
      :transaction_date,
      :tx_data
    ])
    |> validate_required([:tx_hash, :address, :amount, :balance_after])
    |> unique_constraint([:tx_hash, :address])
  end
end
