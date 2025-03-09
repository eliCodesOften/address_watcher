defmodule AddressWatcher.Repo do
  use Ecto.Repo,
    otp_app: :address_watcher,
    adapter: Ecto.Adapters.Postgres
end
