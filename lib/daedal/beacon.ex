defmodule Daedal.Beacon do
  @moduledoc """
  `Daedal.Beacon` is a context that defines the automatic deployment discovery process that `Daedal`
  uses. This provides the primitives for `Daedal` to act as an EPMD based callback service for
  deployments to reach out to during launch. `Daedal` makes use of this to discover the nodes in
  distributed clusters to then interact with.

  `Daedal.Beacon` provides the following components:
  - `Daedal.Beacon`: the Daedal per node supervisor that manages the Beacon related Supervision
    tree.
  - `Daedal.Beacon.Deployment`: the struct that holds the deployment details that are registered
    with the Beacon Registry.
  - `Daedal.Beacon.Pinger`: the GenServer added to the deployment supervision tree that pings the
  Beacon server to register the deployment. It is responsible for establishing the connection from
  the initial hidden connection to publishing deployment details to the Beacon server. When it shuts
  down it will message the Beacon server to remove the deployment from the list of active
  deployments.
  - `Daedal.Beacon.Registry`: the Registry that holds the list of active deployments that have
  pinged the Beacon server. This is used to keep track of the deployments that have registered with
  the Beacon server, managing these as multiple separate cluster representations.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    child_specs(opts)
    |> Supervisor.init(
      auto_shutdown: :never,
      strategy: :one_for_one
    )
  end

  defp child_specs(opts) do
    [
      Daedal.Beacon.Registry.child_spec(Keyword.get(opts, :registry_opts, [])),
      Daedal.Beacon.Pinger.child_spec(
        beacon_cookie: Node.get_cookie(),
        beacon_node: Node.self()
      )
    ]
  end
end
