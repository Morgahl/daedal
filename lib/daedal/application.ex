defmodule Daedal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = [
      daedal: [
        strategy: Cluster.Strategy.Epmd,
        timeout: 30_000,
        config: [hosts: [:"daedal1@127.0.0.1", :"daedal2@127.0.0.1", :"daedal3@127.0.0.1"]]
      ]
    ]

    children = [
      DaedalWeb.Telemetry,
      # TODO: Start this when we are ready to look at persisting data
      # Daedal.Repo,
      # TODO: Start this when we are in a DNS addressable environment
      # {DNSCluster, query: Application.get_env(:daedal, :dns_cluster_query) || :ignore},
      {Cluster.Supervisor, [topologies, [name: Daedal.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Daedal.PubSub},
      DaedalBeacon,
      DaedalWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Daedal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DaedalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
