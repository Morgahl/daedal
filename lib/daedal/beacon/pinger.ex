defmodule Daedal.Beacon.Pinger do
  @moduledoc """
  `#{inspect(__MODULE__)}` is the GenServer added to the deployment's supervision tree that gathers
  metadata and gracefully connects to the Beacon server to register the deployment. It is
  responsible for establishing the connection from the initial hidden connection to publishing
  deployment details to the Beacon server. When it shuts down it will message the Beacon server to
  remove the deployment from the list of active deployments.
  """

  use GenServer
  require Logger

  alias Daedal.Beacon.Deployment
  alias Daedal.Beacon.Registry
  alias Daedal.RPC

  defstruct [
    :beacon_cookie,
    :beacon_node,
    :connection_state,
    :timer_ref,
    :deployment,
    :connected_interval,
    :connecting_interval
  ]

  @type connection_state :: :connecting | :connected

  @type t :: %__MODULE__{
          beacon_cookie: RPC.cookie(),
          beacon_node: node(),
          connection_state: connection_state(),
          deployment: Deployment.t(),
          connected_interval: pos_integer(),
          connecting_interval: pos_integer()
        }

  @default_connected_interval 60 * 1000
  @default_connecting_interval 5 * 1000

  def child_spec(opts) do
    opts = Keyword.take(opts, [:beacon_cookie, :beacon_node, :connected_interval, :connecting_interval])

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def handoff(new_beacon_nodes) do
    GenServer.call(__MODULE__, {:handoff, new_beacon_nodes})
  end

  @impl GenServer
  def init(opts) do
    Logger.info("#{inspect(__MODULE__)} starting #{inspect(__MODULE__)}", self: Node.self())
    Process.flag(:trap_exit, true)
    beacon_cookie = Keyword.fetch!(opts, :beacon_cookie)
    beacon_node = Keyword.fetch!(opts, :beacon_node)
    connected_interval = Keyword.get(opts, :connected_interval, @default_connected_interval)
    connecting_interval = Keyword.get(opts, :connecting_interval, @default_connecting_interval)
    metadata = Keyword.get(opts, :metadata, [])
    deployment = Deployment.new(metadata)

    {:ok,
     %__MODULE__{
       beacon_cookie: beacon_cookie,
       beacon_node: beacon_node,
       connection_state: :connecting,
       deployment: deployment,
       connected_interval: connected_interval,
       connecting_interval: connecting_interval
     }, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    Logger.debug("#{inspect(__MODULE__)} beginning connection to Beacon server", self: Node.self())
    {:noreply, loop(state)}
  end

  @impl GenServer
  def handle_call({:handoff, new_beacon_nodes}, _from, state) do
    Logger.debug("#{inspect(__MODULE__)} received handoff message",
      self: Node.self(),
      new_beacon_nodes: new_beacon_nodes
    )

    {:noreply,
     state
     |> cancel_next_loop()
     |> disconnect()
     |> merge_nodes(new_beacon_nodes), {:continue, :connect}}
  end

  @impl GenServer
  def handle_info(:loop, state) do
    {:noreply, loop(state)}
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.debug("#{inspect(__MODULE__)} received exit message", self: Node.self(), reason: reason)
    {:stop, reason, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("#{inspect(__MODULE__)} received unhandled message", self: Node.self(), message: msg)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("#{inspect(__MODULE__)} is terminating", reason: inspect(reason), state: inspect(state))

    state
    |> cancel_next_loop()
    |> disconnect()
  end

  defp loop(state = %__MODULE__{}) do
    Logger.debug("#{inspect(__MODULE__)} looping Beacon server", self: Node.self(), beacon_node: state.beacon_node)

    state
    |> maybe_connect()
    |> setup_next_loop()
  end

  defp maybe_connect(state = %__MODULE__{beacon_node: beacon_nodes}) when is_list(beacon_nodes) do
    Enum.shuffle(beacon_nodes)
    |> Enum.reduce(state, fn
      _beacon_node, state = %__MODULE__{connection_state: :connected} -> state
      beacon_node, state -> connect(state, beacon_node)
    end)
  end

  defp maybe_connect(state = %__MODULE__{connection_state: :connected}) do
    cond do
      state.beacon_node in Node.list(:hidden) -> state
      true -> connect(state, state.beacon_node)
    end
  end

  defp maybe_connect(state = %__MODULE__{beacon_node: beacon_node}), do: connect(state, beacon_node)

  defp connect(state = %__MODULE__{beacon_cookie: beacon_cookie, deployment: deployment}, beacon_node) do
    Logger.debug("#{inspect(__MODULE__)} connecting to Beacon server", self: Node.self(), beacon_node: beacon_node)

    if beacon_node in Node.list(:hidden) do
      state
    else
      case RPC.call(beacon_node, beacon_cookie, Registry, :register, [deployment]) do
        {:ok, :registered} ->
          Logger.info("#{inspect(__MODULE__)} registered deployment with Beacon server",
            self: Node.self(),
            beacon_node: beacon_node
          )

          %__MODULE__{state | connection_state: :connected, beacon_node: beacon_node}

        {:ok, :already_registered} ->
          Logger.warning("#{inspect(__MODULE__)} already registered deployment with Beacon server",
            self: Node.self(),
            beacon_node: beacon_node
          )

          %__MODULE__{state | connection_state: :connected, beacon_node: beacon_node}

        {:error, reason} ->
          Logger.error("#{inspect(__MODULE__)} failed to register deployment with Beacon server",
            self: Node.self(),
            beacon_node: beacon_node,
            reason: inspect(reason)
          )

          %__MODULE__{state | connection_state: :connecting}

        {:exit, reason} ->
          Logger.error("#{inspect(__MODULE__)} failed to register deployment with Beacon server",
            self: Node.self(),
            beacon_node: beacon_node,
            reason: inspect(reason)
          )

          %__MODULE__{state | connection_state: :connecting}
      end
    end
  end

  defp disconnect(state = %__MODULE__{connection_state: :connected}) do
    Logger.info("#{inspect(__MODULE__)} disconnecting from Beacon server",
      self: Node.self(),
      beacon_node: state.beacon_node
    )

    RPC.call(state.beacon_node, state.beacon_cookie, Daedal.Beacon.Registry, :unregister, [Node.self()])
    Node.disconnect(state.beacon_node)
    %__MODULE__{state | connection_state: :connecting}
  end

  defp disconnect(state = %__MODULE__{connection_state: :connecting}) do
    Logger.info("#{inspect(__MODULE__)} already disconnected from Beacon server",
      self: Node.self(),
      beacon_node: state.beacon_node
    )
  end

  defp merge_nodes(state = %__MODULE__{beacon_node: beacon_node}, new_beacon_nodes) do
    beacon_nodes =
      beacon_node
      |> List.wrap()
      |> Enum.concat(new_beacon_nodes)
      |> Enum.uniq()

    %__MODULE__{state | beacon_node: beacon_nodes}
  end

  defp setup_next_loop(state = %__MODULE__{connection_state: :connected}) do
    %__MODULE__{state | timer_ref: Process.send_after(self(), :loop, state.connected_interval)}
  end

  defp setup_next_loop(state = %__MODULE__{connection_state: :connecting}) do
    %__MODULE__{state | timer_ref: Process.send_after(self(), :loop, state.connecting_interval)}
  end

  defp cancel_next_loop(state = %__MODULE__{timer_ref: timer_ref}) do
    Process.cancel_timer(timer_ref)
    %__MODULE__{state | timer_ref: nil}
  end
end
