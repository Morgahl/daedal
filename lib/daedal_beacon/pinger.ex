defmodule DaedalBeacon.Pinger do
  @moduledoc """
  `#{inspect(__MODULE__)}` is the GenServer added to the deployment's supervision tree that gathers
  metadata and gracefully connects to the Beacon server to register the deployment. It is
  responsible for establishing the connection from the initial hidden connection to publishing
  deployment details to the Beacon server. When it shuts down it will message the Beacon server to
  remove the deployment from the list of active deployments.
  """

  use Daedal.GenServer

  alias DaedalBeacon.Deployment
  alias DaedalBeacon.Registry
  alias Daedal.RPC

  defstruct [
    :beacon_cookie,
    :beacon_node,
    :connection_state,
    :interval,
    :timer_ref,
    :deployment
  ]

  @type connection_state :: :connecting | :connected | :registered

  @type t :: %__MODULE__{
          beacon_cookie: RPC.cookie(),
          beacon_node: node(),
          connection_state: connection_state(),
          interval: pos_integer(),
          timer_ref: reference(),
          deployment: Deployment.t()
        }

  @default_interval 5 * 1000

  def child_spec(opts) do
    opts = Keyword.take(opts, [:beacon_cookie, :beacon_node, :interval])

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def handoff(new_beacon_nodes), do: GenServer.call(__MODULE__, {:handoff, new_beacon_nodes})

  @impl GenServer
  def init(opts) do
    beacon_cookie = Keyword.fetch!(opts, :beacon_cookie)
    beacon_node = Keyword.fetch!(opts, :beacon_node)
    interval = Keyword.get(opts, :interval, @default_interval)
    metadata = Keyword.get(opts, :metadata, [])
    deployment = Deployment.new(metadata)

    state = %__MODULE__{
      beacon_cookie: beacon_cookie,
      beacon_node: beacon_node,
      connection_state: :connecting,
      deployment: deployment,
      interval: interval
    }

    :net_kernel.monitor_nodes(true, node_type: :all)

    {:ok, loop(state)}
  end

  @impl GenServer
  def handle_call({:handoff, new_beacon_nodes}, _from, state = %__MODULE__{}) do
    Logger.debug("#{inspect(__MODULE__)} received handoff message",
      self: Node.self(),
      new_beacon_nodes: new_beacon_nodes
    )

    state =
      state
      |> cancel_next_loop()
      |> disconnect()
      |> merge_nodes(new_beacon_nodes)
      |> loop()

    {:reply, {:ok, state.beacon_node}, state}
  end

  @impl GenServer
  def handle_info(:loop, state) do
    {:noreply, loop(state)}
  end

  @impl GenServer
  def handle_info({:nodeup, _node, _metadata}, state), do: {:noreply, loop(state)}

  def handle_info({:nodedown, node, _metadata}, state = %__MODULE__{beacon_node: node}), do: {:noreply, loop(disconnect(state))}
  def handle_info({:nodedown, _node, _metadata}, state), do: {:noreply, loop(state)}

  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("#{inspect(__MODULE__)} received unhandled message", self: Node.self(), message: msg)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    :net_kernel.monitor_nodes(false, node_type: :all)

    state
    |> cancel_next_loop()
    |> disconnect()
  end

  defp loop(state = %__MODULE__{}) do
    Logger.debug("#{inspect(__MODULE__)} connection loop", self: Node.self(), state: state)

    state
    |> cancel_next_loop()
    |> maybe_connect()
    |> setup_next_loop()
  end

  defp maybe_connect(state = %__MODULE__{connection_state: :connecting, beacon_node: [h | t]}) do
    [h | Enum.shuffle(t)]
    |> Enum.reduce(state, fn
      beacon_node, state = %__MODULE__{connection_state: :connecting} -> connect(state, beacon_node)
      _beacon_node, state = %__MODULE__{connection_state: :connected} -> register(state)
      _beacon_node, state = %__MODULE__{connection_state: :registered} -> state
    end)
  end

  defp maybe_connect(state = %__MODULE__{connection_state: :connecting, beacon_node: beacon_node}), do: connect(state, beacon_node)

  defp maybe_connect(state = %__MODULE__{connection_state: :connected}) do
    if state.beacon_node in Node.list(:hidden) do
      register(state)
    else
      maybe_connect(%__MODULE__{state | connection_state: :connecting})
    end
  end

  defp maybe_connect(state = %__MODULE__{connection_state: :registered}) do
    new_dep = Deployment.new()

    old_visible = state.deployment.neighbors[:visible] |> Enum.sort()
    old_hidden = state.deployment.neighbors[:hidden] |> Enum.sort()
    new_visible = new_dep.neighbors[:visible] |> Enum.sort()
    new_hidden = new_dep.neighbors[:hidden] |> Enum.sort()

    cond do
      not (length(old_visible) === length(new_visible) and Enum.all?(Enum.zip(old_visible, new_visible), &same/1)) -> register(state)
      not (length(old_hidden) === length(new_hidden) and Enum.all?(Enum.zip(old_hidden, new_hidden), &same/1)) -> register(state)
      state.beacon_node in Node.list(:hidden) -> state
      true -> maybe_connect(%__MODULE__{state | connection_state: :connecting})
    end
  end

  defp same({n, n}), do: true
  defp same(_), do: false

  defp connect(state = %__MODULE__{connection_state: :connecting}, beacon_node) do
    case RPC.connect_hidden(beacon_node, state.beacon_cookie) do
      true -> register(%__MODULE__{state | connection_state: :connected, beacon_node: beacon_node})
      false -> state
      :ignored -> state
    end
  end

  defp register(state = %__MODULE__{connection_state: conn_state}) when conn_state in [:connected, :registered] do
    Logger.debug("#{inspect(__MODULE__)} registering with Beacon server", self: Node.self(), beacon_node: state.beacon_node)
    state = %__MODULE__{state | deployment: Deployment.new()}

    case RPC.call(state.beacon_node, state.beacon_cookie, Registry, :register, [state.deployment]) do
      {:ok, :already_registered} ->
        %__MODULE__{state | connection_state: :registered}

      {:ok, :updated} ->
        Logger.debug("#{inspect(__MODULE__)} updated deployment with Beacon server",
          self: Node.self(),
          beacon_node: state.beacon_node
        )

        %__MODULE__{state | connection_state: :registered}

      {:ok, conn_state} ->
        Logger.info("#{inspect(__MODULE__)} registered deployment with Beacon server",
          self: Node.self(),
          beacon_node: state.beacon_node
        )

        %__MODULE__{state | connection_state: conn_state}

      {:error, reason} ->
        Logger.error("#{inspect(__MODULE__)} failed to register deployment with Beacon server",
          self: Node.self(),
          beacon_node: state.beacon_node,
          reason: inspect(reason)
        )

        %__MODULE__{state | connection_state: :connecting}

      {:exit, reason} ->
        Logger.error("#{inspect(__MODULE__)} failed to register deployment with Beacon server",
          self: Node.self(),
          beacon_node: state.beacon_node,
          reason: inspect(reason)
        )

        %__MODULE__{state | connection_state: :connecting}
    end
  end

  defp disconnect(state = %__MODULE__{connection_state: :connecting}), do: state

  defp disconnect(state = %__MODULE__{connection_state: conn_state}) when conn_state in [:connected, :registered] do
    Logger.info("#{inspect(__MODULE__)} disconnecting from Beacon server",
      self: Node.self(),
      beacon_node: state.beacon_node
    )

    RPC.call(state.beacon_node, state.beacon_cookie, DaedalBeacon.Registry, :unregister, [Node.self()])
    Node.disconnect(state.beacon_node)
    %__MODULE__{state | connection_state: :connecting}
  end

  defp merge_nodes(state = %__MODULE__{beacon_node: beacon_node}, new_beacon_nodes) do
    beacon_nodes =
      new_beacon_nodes
      |> Enum.shuffle()
      |> Enum.concat(List.wrap(beacon_node))
      |> Enum.uniq()

    %__MODULE__{state | beacon_node: beacon_nodes}
  end

  defp setup_next_loop(state = %__MODULE__{connection_state: :connecting}) do
    %__MODULE__{state | timer_ref: Process.send_after(self(), :loop, state.interval)}
  end

  defp setup_next_loop(state = %__MODULE__{connection_state: :connected}) do
    %__MODULE__{state | timer_ref: Process.send_after(self(), :loop, state.interval)}
  end

  defp setup_next_loop(state), do: state

  defp cancel_next_loop(state = %__MODULE__{timer_ref: timer_ref}) when is_reference(timer_ref) do
    Process.cancel_timer(timer_ref)
    %__MODULE__{state | timer_ref: nil}
  end

  defp cancel_next_loop(state), do: state
end
