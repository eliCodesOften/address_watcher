defmodule AddressWatcher.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AddressWatcherWeb.Telemetry,
      AddressWatcher.Repo,
      {DNSCluster, query: Application.get_env(:address_watcher, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AddressWatcher.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: AddressWatcher.Finch},
      # Start a worker by calling: AddressWatcher.Worker.start_link(arg)
      # {AddressWatcher.Worker, arg},
      # Start to serve requests, typically the last entry
      AddressWatcherWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AddressWatcher.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AddressWatcherWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
