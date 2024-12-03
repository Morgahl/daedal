defmodule DaedalBeacon.Registry do
  @moduledoc """
  `#{inspect(__MODULE__)}` is the registry responsible for managing the active deployments
  that have pinged the Beacon server. Each Elixir node in the cluster has its own independent
  ETS table for deployments. This module allows for searching across all node-specific registries
  to resolve deployments across the cluster.
  """

  use Daedal.GenServer

  alias DaedalBeacon.Deployment
  alias Daedal.RPC

  defstruct []

  @default_opts []

  @topic "#{inspect(__MODULE__)}"

  # Public API
  def topic(), do: @topic

  def child_spec(opts),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def register(deployment = %Deployment{}), do: GenServer.call(__MODULE__, {:register, deployment})

  def unregister(node), do: GenServer.call(__MODULE__, {:unregister, node})

  def list(timeout \\ 5000), do: :ets.tab2list(__MODULE__) ++ list_across_cluster(timeout)

  def lookup(node, timeout \\ 5000) do
    case :ets.lookup(__MODULE__, node) do
      [] ->
        Logger.debug("#{inspect(__MODULE__)} could not find deployment, expanding search to cluster",
          node: Node.self(),
          dep_node: node
        )

        lookup_across_cluster(node, timeout)

      values ->
        values
    end
  end

  # GenServer Callbacks
  @impl GenServer
  def init(opts) do
    state =
      Keyword.validate!(opts, @default_opts)
      |> then(&struct!(__MODULE__, &1))

    :ets.new(__MODULE__, [:set, :protected, :named_table, read_concurrency: true])
    :ets.insert(__MODULE__, {Node.self(), Deployment.new()})

    Logger.metadata(
      application: :daedal_beacon,
      node: Node.self()
    )

    :net_kernel.monitor_nodes(true, node_type: :all)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register, deployment}, _from, state) do
    case register_internal(deployment) do
      :registered ->
        Logger.info("#{inspect(__MODULE__)} successfully registered deployment", name: deployment.name)
        {:reply, :registered, state}

      :updated ->
        Logger.info("#{inspect(__MODULE__)} successfully updated deployment", name: deployment.name)
        {:reply, :updated, state}

      :already_registered ->
        Logger.warning("#{inspect(__MODULE__)} deployment already registered", name: deployment.name)
        {:reply, :already_registered, state}

      {:error, reason} ->
        Logger.error("#{inspect(__MODULE__)} failed to register deployment", name: deployment.name, reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:unregister, node}, _from, state) do
    case unregister_internal(node) do
      :ok ->
        Logger.info("#{inspect(__MODULE__)} successfully unregistered deployment", dep_node: node)
        {:reply, :unregistered, state}

      {:error, reason} ->
        Logger.error("#{inspect(__MODULE__)} failed to unregister deployment", dep_node: node, reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:nodeup, node, _metadata}, state) do
    Logger.debug("#{inspect(__MODULE__)} node up, looking up deployments", nodeup: node)

    with [{^node, _}] <- lookup(node),
         :ok <- publish({:registered, node}) do
      {:noreply, state}
    else
      [] ->
        Logger.debug("#{inspect(__MODULE__)} node up, no deployments found", nodeup: node)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("#{inspect(__MODULE__)} failed to lookup node with reason: #{reason}", nodeup: node)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:nodedown, node, _metadata}, state) do
    Logger.debug("#{inspect(__MODULE__)} node down, removing deployments", nodedown: node)

    case unregister_internal(node) do
      :ok ->
        Logger.info("#{inspect(__MODULE__)} successfully unregistered deployments", nodedown: node)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("#{inspect(__MODULE__)} failed to unregister deployments with reason: #{reason}", nodedown: node)
        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, _state) do
    :net_kernel.monitor_nodes(false, node_type: :all)

    delete_all_local()
    |> send_handoff(Node.list())
  end

  defp register_internal(deployment) do
    dep_node = deployment.node

    case lookup(dep_node) do
      [{^dep_node, ^deployment}] ->
        :already_registered

      [] ->
        with true <- :ets.insert(__MODULE__, {dep_node, deployment}),
             :ok <- publish({:registered, dep_node}) do
          :registered
        end

      _ ->
        with true <- :ets.insert(__MODULE__, {dep_node, deployment}),
             :ok <- publish({:updated, dep_node}) do
          :updated
        end
    end
  end

  defp unregister_internal(node) do
    with true <- :ets.delete(__MODULE__, node) do
      publish({:unregistered, node})
    end
  end

  defp list_across_cluster(timeout) do
    Node.list()
    |> RPC.multicall(:ets, :tab2list, [__MODULE__], timeout)
    |> Enum.map(&elem(&1, 1))
    |> Enum.map(fn
      {:ok, values} -> values
      _ -> []
    end)
    |> List.flatten()
  end

  defp lookup_across_cluster(node, timeout) do
    Node.list()
    |> RPC.multicall(:ets, :lookup, [__MODULE__, node], timeout)
    |> Enum.map(&elem(&1, 1))
    |> Enum.map(fn
      {:ok, values} -> values
      _ -> []
    end)
    |> List.flatten()
  end

  @spec delete_all_local() :: [node()]
  defp delete_all_local() do
    for {node, _} <- :ets.tab2list(__MODULE__) do
      :ets.delete(__MODULE__, node)
      node
    end
  end

  defp send_handoff(nodes, beacon_nodes) do
    Logger.info("#{inspect(__MODULE__)} sending handoff messages to nodes",
      nodes: nodes,
      beacon_nodes: beacon_nodes
    )

    RPC.multicall(nodes, DaedalBeacon.Pinger, :handoff, [beacon_nodes])
  end

  defp publish(msg), do: Phoenix.PubSub.broadcast(Daedal.PubSub, @topic, msg)
end
