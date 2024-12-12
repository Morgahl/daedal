defmodule DaedalWeb.HomeLive do
  use DaedalWeb, :live_view

  alias Phoenix.Router

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= for route <- @routes do %>
        <.link navigate={route.path}>
          <p>{inspect(elem(route.metadata.mfa, 0))}</p>
          <pre>{route.path}</pre>
        </.link>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, routes: get_live_views())}
  end

  defp get_live_views() do
    DaedalWeb.Router
    |> Router.routes()
    |> Enum.filter(&filter_live_views/1)
    |> Enum.sort_by(& &1.metadata.phoenix_live_view)
  end

  defp filter_live_views(%{path: "/"}), do: false
  defp filter_live_views(%{metadata: %{phoenix_live_view: _}, path: path}), do: ?: not in to_charlist(path)
  defp filter_live_views(_), do: false
end
