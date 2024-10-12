defmodule DaedalBeacon do
  @moduledoc """
  `DaedalBeacon` is a context that defines the automatic deployment discovery process that `Daedal`
  uses. This provides the primitives for `Daedal` to act as an EPMD based callback service for
  deployments to reach out to during launch. `Daedal` makes use of this to discover the nodes in
  distributed clusters to then interact with.

  `DaedalBeacon` provides the following components:
  - `DaedalBeacon`: the Daedal per node supervisor that manages the Beacon related Supervision
    tree.
  - `DaedalBeacon.Deployment`: the struct that holds the deployment details that are registered
    with the Beacon Registry.
  - `DaedalBeacon.Pinger`: the GenServer added to the deployment supervision tree that pings the
  Beacon server to register the deployment. It is responsible for establishing the connection from
  the initial hidden connection to publishing deployment details to the Beacon server. When it shuts
  down it will message the Beacon server to remove the deployment from the list of active
  deployments.
  - `DaedalBeacon.Registry`: the Registry that holds the list of active deployments that have
  pinged the Beacon server. This is used to keep track of the deployments that have registered with
  the Beacon server, managing these as multiple separate cluster representations.
  """
  use Daedal.Supervisor

  @impl Daedal.Supervisor
  def child_specs(opts) do
    [
      DaedalBeacon.Registry.child_spec(Keyword.get(opts, :registry_opts, []))
    ]
  end
end
