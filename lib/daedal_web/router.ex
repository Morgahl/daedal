defmodule DaedalWeb.Router do
  use DaedalWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DaedalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admins_only do
    plug :admin_basic_auth
  end

  scope "/", DaedalWeb do
    pipe_through :browser

    get "/", PageController, :home

    pipe_through :admins_only

    scope "/beacon" do
      live "/deployments", DaedalBeacon.RegistryLive, :index
      live "/deployments/:node", DaedalBeacon.DeploymentLive, :show
    end
  end

  scope "/" do
    pipe_through [:browser, :admins_only]

    import OrionWeb.Router
    import Phoenix.LiveDashboard.Router

    live_dashboard "/dashboard", metrics: DaedalWeb.Telemetry
    live_orion "/orion", live_socket_path: "/live"
  end

  defp admin_basic_auth(conn, _opts) do
    username = System.fetch_env!("AUTH_USERNAME")
    password = System.fetch_env!("AUTH_PASSWORD")
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
