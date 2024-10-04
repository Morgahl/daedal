defmodule Daedal.Beacon.Registry do
  @moduledoc """
  `#{inspect(__MODULE__)}` is the registry responsible for managing the active deployments
  that have pinged the Beacon server. Each Elixir node in the cluster has its own independent
  ETS table for deployments. This module allows for searching across all node-specific registries
  to resolve deployments across the cluster.
  """

  use GenServer

  require Logger

  alias Daedal.Beacon.Deployment
  alias Daedal.RPC

  # Public API
  def child_spec(opts) do
    opts = Keyword.take(opts, [])

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def register(deployment = %Deployment{}) do
    GenServer.call(__MODULE__, {:register, deployment})
  end

  def unregister(node) do
    GenServer.call(__MODULE__, {:unregister, node})
  end

  def lookup(node, timeout \\ 5000) do
    case :ets.lookup(__MODULE__, node) do
      [] ->
        Logger.debug("#{inspect(__MODULE__)} could not find deployment, expanding search to cluster",
          self: Node.self(),
          node: node
        )

        lookup_across_cluster(node, timeout)

      values ->
        values
    end
  end

  # GenServer Callbacks
  @impl GenServer
  def init(:ok) do
    Process.flag(:trap_exit, true)
    :ets.new(__MODULE__, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:register, deployment}, _from, state) do
    case lookup(deployment.node) do
      [] ->
        :ets.insert(__MODULE__, {deployment.node, deployment})

        Logger.debug("#{inspect(__MODULE__)} successfully registered deployment",
          self: Node.self(),
          deployment: deployment
        )

        {:reply, :registered, state}

      _ ->
        Logger.debug("#{inspect(__MODULE__)} deployment already registered", self: Node.self(), deployment: deployment)
        {:reply, :already_registered, state}
    end
  end

  @impl GenServer
  def handle_call({:unregister, node}, _from, state) do
    :ets.delete(__MODULE__, node)
    Logger.debug("#{inspect(__MODULE__)} successfully unregistered deployment", self: Node.self(), node: node)
    {:reply, :unregistered, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.error("#{inspect(__MODULE__)} received exit signal", self: Node.self(), reason: inspect(reason))
    {:stop, reason, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("#{inspect(__MODULE__)} is terminating", reason: inspect(reason), state: inspect(state))

    delete_all_local()
    |> send_handoff(Node.list())
  end

  defp lookup_across_cluster(node, timeout) do
    Node.list()
    |> RPC.multicall(:ets, :lookup, [__MODULE__, node], timeout)
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
    Logger.debug("#{inspect(__MODULE__)} sending handoff message",
      self: Node.self(),
      nodes: nodes,
      beacon_nodes: beacon_nodes
    )

    RPC.multicast(nodes, Daedal.Beacon.Pinger, :handoff, [beacon_nodes])
  end
end
