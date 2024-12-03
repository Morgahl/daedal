defmodule DaedalWeb.DaedalBeacon.DeploymentLive do
  use DaedalWeb, :live_view

  import DaedalWeb.DaedalBeaconComponents

  alias DaedalBeacon.Registry

  @impl true
  def render(assigns) do
    ~H"""
    <.deployment_full deployment={@deployment} />
    """
  end

  @impl true
  def mount(%{"node" => node}, _session, socket) do
    case get_deployment(node) do
      {:ok, deployment} -> {:ok, assign(socket, deployment: deployment)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_deployment(node) do
    node
    |> URI.decode()
    |> String.to_existing_atom()
    |> Registry.lookup()
    |> case do
      [] -> {:error, "Deployment not found"}
      [{_node, deployment}] -> {:ok, deployment}
    end
  end
end
