defmodule Zeph.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      ZephWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Zeph.PubSub},
      # Start Finch
      {Finch, name: Zeph.Finch},
      # Start the Endpoint (http/https)
      ZephWeb.Endpoint,
      # Start the Zephyr Bumblebee model
      {Nx.Serving, name: ZephyrModel, serving: Zeph.Zephyr.serving()}
      # Start a worker by calling: Zeph.Worker.start_link(arg)
      # {Zeph.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Zeph.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ZephWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
