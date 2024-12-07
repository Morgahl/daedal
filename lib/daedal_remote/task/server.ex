defmodule DaedalRemote.Task.Server do
  @moduledoc """
  This module is a GenServer that runs as a monitoring wrapper around a task module that implements the DaedalRemote.Task behaviour.
  """
  use GenServer

  require Logger

  alias DaedalRemote.Task, as: DaedalTask

  defstruct task_pid: nil,
            monitor_ref: nil,
            module: nil,
            progress: 0,
            shutdown: 30_000,
            status: nil,
            torn_down: false,
            teardown_result: nil,
            result: nil,
            logs: [],
            log_count: 0,
            max_logs: 10

  @type t :: %__MODULE__{
          task_pid: pid() | nil,
          monitor_ref: reference() | nil,
          module: module(),
          progress: DaedalTask.progress(),
          status: DaedalTask.status(),
          torn_down: boolean(),
          teardown_result: DaedalTask.teardown_result(),
          result: DaedalTask.run_result(),
          logs: [log()],
          log_count: non_neg_integer(),
          max_logs: non_neg_integer()
        }

  @type log :: {Logger.level(), DateTime.t(), String.t(), Keyword.t()}

  @type opt :: {:module, module()} | {:shutdown, non_neg_integer()}
  @type opts :: [opt()]

  @default_opts [:extra_args, :module, shutdown: 30_000]

  @spec status(module(), non_neg_integer(), timeout()) :: {DaedalTask.status(), DaedalTask.progress(), [log()]}
  def status(module, log_n \\ 10, timeout \\ :timer.seconds(5)), do: GenServer.call(module, {:status, log_n}, timeout)

  @spec result(module(), timeout()) :: DaedalTask.run_result() | {:status, DaedalTask.status()} | {:failed, any()}
  def result(module, timeout \\ :timer.seconds(5)), do: GenServer.call(module, :get_result, timeout)

  @spec log(module(), Logger.level(), String.t(), Keyword.t()) :: :ok
  def log(module, level, msg, md), do: send(module, {:log, level, msg, md})

  @spec progress(module(), DaedalTask.progress()) :: :ok
  def progress(module, progress), do: send(module, {:progress, progress})

  def child_spec(opts) do
    opts = Keyword.validate!(opts, @default_opts)

    %{
      id: opts[:module],
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: opts[:shutdown],
      type: :worker
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:module])
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    module = opts[:module]
    Logger.metadata(node: Node.self(), module: module)
    Logger.debug("#{inspect(__MODULE__)} starting")

    if DaedalTask.implements_behaviour?(module) do
      {:ok, %__MODULE__{module: module, status: :starting}, {:continue, {:start, opts[:extra_args]}}}
    else
      {:stop, {:behaviour_not_implemented, DaedalTask, module}}
    end
  end

  @impl GenServer
  def handle_continue({:start, args}, %__MODULE__{module: module} = state) do
    Logger.debug("#{inspect(__MODULE__)} setting up")

    with {:ok, setup_result} <- run_task_setup(module, args),
         {:ok, task_pid} <- run_task_run(setup_result, state) do
      Logger.debug("#{inspect(module)} task started")
      ref = Process.monitor(task_pid)
      {:noreply, %__MODULE__{state | task_pid: task_pid, monitor_ref: ref, status: :running}}
    else
      {:error, reason} ->
        Logger.error("#{inspect(module)} failed with reason #{inspect(reason)}")
        {:noreply, %__MODULE__{state | module: module, status: {:failed, {:error, reason}}, torn_down: true}}
    end
  end

  @impl GenServer
  def handle_continue({:teardown, _reason}, %__MODULE__{torn_down: true} = state), do: {:noreply, state}

  @impl GenServer
  def handle_continue({:teardown, reason}, %__MODULE__{torn_down: false} = state) do
    {:noreply, maybe_run_task_teardown(state, reason)}
  end

  @impl GenServer
  def handle_continue(:flush, %__MODULE__{log_count: count, max_logs: max} = state) when count < max * 2, do: {:noreply, state}

  def handle_continue(:flush, %__MODULE__{} = state) do
    if state.log_count < state.max_logs * 2 do
      {:noreply, state}
    else
      # TODO: Implement a way to flush the logs to the calling process
      # TODO: We also need a debounced way to run this, taking both a max number of logs and a max
      # TODO: time since last flush into account, for now we can do the max count and clear the logs
      {retain, _send} = Enum.split(state.logs, state.max_logs)
      {:noreply, %__MODULE__{state | logs: retain, log_count: state.max_logs}}
    end
  end

  @impl GenServer
  def handle_call({:status, count}, _from, %__MODULE__{} = state) do
    logs =
      case count do
        :infinity -> state.logs
        count when is_integer(count) -> Enum.take(state.logs, count)
        _ -> state.logs |> Enum.take(10)
      end
      |> Enum.reverse()

    {:reply, {state.status, state.progress, logs}, state}
  end

  @impl GenServer
  def handle_call(:get_result, _from, %__MODULE__{status: :completed, result: result} = state), do: {:reply, result, state}
  def handle_call(:get_result, _from, %__MODULE__{status: {:failed, reason}} = state), do: {:reply, {:failed, reason}, state}
  def handle_call(:get_result, _from, %__MODULE__{status: status} = state), do: {:reply, {:status, status}, state}

  @impl GenServer
  def handle_info({:progress, progress}, %__MODULE__{module: module} = state) do
    Logger.debug("#{inspect(module)} task progress: #{inspect(progress)}")
    {:noreply, %__MODULE__{state | progress: progress}}
  end

  @impl GenServer
  def handle_info({:log, level, ts, msg, md}, %__MODULE__{} = state) do
    {:noreply, %__MODULE__{state | logs: [{level, ts, msg, md} | state.logs], log_count: state.log_count + 1}, {:continue, :flush}}
  end

  @impl GenServer
  def handle_info({:result, result}, %__MODULE__{module: module} = state) do
    Logger.debug("#{inspect(module)} task returned result: #{inspect(result)}")
    {:noreply, %__MODULE__{state | status: :completed, result: result}, {:continue, {:teardown, :normal}}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{module: module, monitor_ref: ref} = state) do
    Logger.debug("#{inspect(module)} task finished unexpectedly", reason: inspect(reason))
    {:noreply, %__MODULE__{state | status: {:failed, reason}, monitor_ref: nil}, {:continue, {:teardown, reason}}}
  end

  @impl GenServer
  def handle_info({:EXIT, pid, reason}, %__MODULE__{module: module, task_pid: pid} = state) do
    Logger.debug("#{inspect(module)} task exited", reason: inspect(reason))
    {:noreply, %__MODULE__{state | task_pid: nil}}
  end

  @impl GenServer
  def handle_info({:EXIT, from, reason}, %__MODULE__{module: module} = state) when from == self() do
    Logger.debug("#{inspect(module)} exited", reason: inspect(reason))
    {:stop, reason, state}
  end

  @impl GenServer
  def handle_info(msg, %__MODULE__{module: module} = state) do
    Logger.warning("#{inspect(module)} unexpected info message", msg: inspect(msg))
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, %__MODULE__{} = state) do
    Logger.debug("#{inspect(__MODULE__)} terminating with state: #{inspect(state)}")

    state
    |> maybe_stop_task(reason)
    |> maybe_run_task_teardown(reason)
  end

  defp run_task_setup(module, args), do: apply(module, :setup, [args])

  defp run_task_run(setup_result, %__MODULE__{module: module}), do: Task.start_link(task_harness(module, setup_result))

  defp maybe_run_task_teardown(state = %__MODULE__{torn_down: true}, _reason), do: state

  defp maybe_run_task_teardown(state = %__MODULE__{monitor_ref: monitor_ref}, reason) do
    is_reference(monitor_ref) && Process.demonitor(monitor_ref, [:flush])
    result = apply(state.module, :teardown, [reason, state.progress, state.result])
    %__MODULE__{state | torn_down: true, teardown_result: result, monitor_ref: nil}
  end

  defp task_harness(module, setup_result) do
    fn ->
      DaedalRemote.Logger.setup(&send(module, {:log, &1, &2, &3, &4}))
      result = apply(module, :run, [setup_result])
      send(module, {:result, result})
    end
  end

  defp maybe_stop_task(
         %__MODULE__{
           task_pid: task_pid,
           module: module,
           monitor_ref: monitor_ref,
           shutdown: shutdown
         } = state,
         reason
       )
       when is_pid(task_pid) or is_reference(monitor_ref) do
    if is_pid(task_pid) do
      Process.exit(task_pid, reason)

      receive do
        {:DOWN, ^monitor_ref, :process, _pid, reason} ->
          Logger.debug("#{inspect(module)} shutdown confirmed with reason #{inspect(reason)}")
      after
        shutdown ->
          Logger.warning("#{inspect(module)} did not shut down in time")
      end
    end

    if is_reference(monitor_ref) do
      Process.demonitor(monitor_ref, [:flush])
    end

    %__MODULE__{state | task_pid: nil, monitor_ref: nil}
  end

  defp maybe_stop_task(state, _reason), do: state
end
