defmodule DaedalWeb.DaedalBeacon.RegistryLive do
  use DaedalWeb, :live_view

  import DaedalWeb.DaedalBeaconComponents

  alias DaedalBeacon.Registry

  attr :search, Phoenix.HTML.FormField
  attr :deployments, :list

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form for={@search} phx-change="search" phx-debounce="150">
        <.search_input field={@search[:query]} />
        <.sort_checkbox field={@search[:sort]} />
      </.form>
      <div>
        <%= for {_node, deployment} <- @deployments do %>
          <.deployment_minimal deployment={deployment} />
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    with :ok <- Phoenix.PubSub.subscribe(Daedal.PubSub, Registry.registered_topic()),
         :ok <- Phoenix.PubSub.subscribe(Daedal.PubSub, Registry.unregistered_topic()) do
      {:ok, assign(socket, deployments: [])}
    else
      {:error, reason} -> {:ok, return_to_home(socket, :error, reason)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search = fix_params(params)
    deployments = get_deployments(search)
    {:noreply, assign(socket, search: to_form(search), deployments: deployments)}
  end

  @impl true
  def handle_event("search", params, socket) do
    deployments =
      params
      |> fix_params()
      |> get_deployments()

    {:noreply, assign(socket, deployments: deployments)}
  end

  @impl true
  def handle_info({:registered, node}, socket) do
    case get_deployment(node) do
      {:ok, deployment} ->
        deployments =
          socket.assigns.deployments
          |> Enum.reject(fn {n, _} -> n == node end)
          |> then(&[{node, deployment} | &1])
          |> Enum.sort_by(fn {node, _deployment} -> node end, String.to_existing_atom(socket.assigns.search.params[:sort] || "asc"))

        {:noreply, assign(socket, deployments: deployments)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:unregistered, node}, socket) do
    deployments =
      socket.assigns.deployments
      |> Enum.reject(fn {n, _} -> n == node end)
      |> Enum.sort_by(fn {node, _deployment} -> node end, String.to_existing_atom(socket.assigns.search.params[:sort] || "asc"))

    {:noreply, assign(socket, deployments: deployments)}
  end

  @impl true
  def terminate(reason, _socket) do
    with :ok <- Phoenix.PubSub.unsubscribe(Daedal.PubSub, Registry.registered_topic()),
         :ok <- Phoenix.PubSub.unsubscribe(Daedal.PubSub, Registry.unregistered_topic()) do
      reason
    end
  end

  defp get_deployments(%{"query" => query, "sort" => dir}) do
    Registry.list()
    |> Enum.filter(fn {_, d} -> String.contains?(Atom.to_string(d.name), query) end)
    |> Enum.sort_by(fn {node, _deployment} -> node end, String.to_existing_atom(dir))
  end

  defp get_deployment(node) do
    node
    |> Registry.lookup()
    |> case do
      [] -> {:error, "Deployment not found for #{node}"}
      [{_node, deployment}] -> {:ok, deployment}
    end
  end

  defp fix_params(params) do
    params
    |> fix_query()
    |> fix_sort()
  end

  defp fix_query(%{"query" => _query} = params), do: params
  defp fix_query(%{} = params), do: Map.put_new(params, "query", "")

  defp fix_sort(%{"sort" => sort} = params) when sort in ["asc", "desc"], do: params
  defp fix_sort(%{} = params), do: Map.put_new(params, "sort", "asc")

  defp return_to_home(socket, level, msg) when level in [:ok, :info, :error] and is_binary(msg) do
    socket
    |> put_flash(level, msg)
    |> push_navigate(to: ~p"/")
  end
end
