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
    with {:ok, deployment} <- get_deployment(node),
         :ok <- Phoenix.PubSub.subscribe(Daedal.PubSub, Registry.updated_topic()),
         :ok <- Phoenix.PubSub.subscribe(Daedal.PubSub, Registry.unregistered_topic()) do
      {:ok, assign(socket, deployment: deployment, registered: true)}
    else
      {:error, reason} -> {:ok, return_to_deployments(socket, :error, reason)}
    end
  end

  @impl true
  def handle_info({msg, node}, socket) when msg in [:unregistered, :updated] do
    cond do
      node == socket.assigns.deployment.node ->
        case msg do
          :unregistered ->
            {:noreply, return_to_deployments(socket, :info, "Deployment unregistered")}

          :updated ->
            case get_atom_deployment(node) do
              {:ok, deployment} -> {:noreply, assign(socket, deployment: deployment)}
              {:error, reason} -> {:noreply, return_to_deployments(socket, :error, reason)}
            end
        end

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def terminate(reason, _socket) do
    with :ok <- Phoenix.PubSub.unsubscribe(Daedal.PubSub, Registry.updated_topic()),
         :ok <- Phoenix.PubSub.unsubscribe(Daedal.PubSub, Registry.unregistered_topic()) do
      reason
    end
  end

  defp get_deployment(node) do
    node
    |> URI.decode()
    |> String.to_existing_atom()
    |> get_atom_deployment()
  rescue
    _ -> {:error, "Deployment not found for #{node}"}
  end

  defp get_atom_deployment(node) do
    node
    |> Registry.lookup()
    |> case do
      [] -> {:error, "Deployment not found for #{node}"}
      [{_node, deployment}] -> {:ok, deployment}
    end
  end

  defp return_to_deployments(socket, level, msg) when level in [:ok, :info, :error] and is_binary(msg) do
    socket
    |> put_flash(level, msg)
    |> push_navigate(to: ~p"/beacon/deployments")
  end
end
