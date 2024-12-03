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
  def mount(params, _session, socket) do
    with search <- fix_params(params),
         deployments <- get_deployments(search),
         :ok <- subscribe() do
      {:ok, assign(socket, search: to_form(search), deployments: deployments)}
    else
      {:error, reason} -> {:error, reason}
    end
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
  def handle_info({msg, _node}, socket) when msg in [:registered, :unregistered, :updated] do
    deployments = get_deployments(socket.assigns.search.source)
    {:noreply, assign(socket, deployments: deployments)}
  end

  @impl true
  def terminate(reason, _socket) do
    with :ok <- unsubscribe() do
      reason
    end
  end

  defp subscribe, do: Phoenix.PubSub.subscribe(Daedal.PubSub, Registry.topic())
  defp unsubscribe, do: Phoenix.PubSub.unsubscribe(Daedal.PubSub, Registry.topic())

  defp get_deployments(%{"query" => query, "sort" => dir}) do
    Registry.list()
    |> Enum.filter(fn {_, d} -> String.contains?(Atom.to_string(d.name), query) end)
    |> Enum.sort_by(fn {node, _deployment} -> node end, String.to_existing_atom(dir))
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
end
