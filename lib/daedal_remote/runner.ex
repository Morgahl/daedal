defmodule DaedalRemote.Runner do
  @callback setup() :: {:ok, any} | {:error, any}
  @callback run() :: any
  @callback run(state :: any) :: any
  @callback teardown(reason :: any, result :: any, state :: any) :: {:ok, any} | {:error, any}

  @optional_callbacks setup: 0, run: 0, run: 1, teardown: 3

  defmodule State do
    defstruct task_pid: nil, monitor_ref: nil, task_state: nil, shutdown: 30_000, status: :starting, result: nil
  end

  def status(module, timeout \\ 5000) do
    if implements_behaviour?(module) do
      GenServer.call(module, :status, timeout)
    else
      {:error, "Module #{inspect(module)} does not implement the Runner behaviour"}
    end
  rescue
    reason -> {:error, reason}
  end

  def implements_behaviour?(module) do
    function_exported?(module, :run, 0) or
      (function_exported?(module, :run, 1) and function_exported?(module, :setup, 0))
  end

  @default_opts [
    shutdown: 30_000
  ]

  defmacro __using__(opts) do
    opts = Keyword.validate!(opts, @default_opts)

    quote location: :keep do
      use Daedal.GenServer
      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      alias DaedalRemote.Runner.State, as: RunnerState

      @default_opts unquote(opts)

      def start_link(opts) when is_list(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          restart: :transient,
          shutdown: 5000,
          type: :worker
        }
      end

      @impl GenServer
      def init(opts) do
        with {:ok, opts} <- Keyword.validate(opts, @default_opts),
             {:ok, state} <- maybe_setup() do
          {:ok, %RunnerState{task_state: state, shutdown: opts[:shutdown]}, {:continue, :run}}
        else
          {:error, reason} -> {:stop, reason}
        end
      end

      @impl GenServer
      def handle_continue(:run, %RunnerState{} = state) do
        Logger.debug("#{inspect(__MODULE__)} running", node: Node.self())

        case start_task(state) do
          {:ok, task_pid} ->
            ref = Process.monitor(task_pid)
            Logger.debug("#{inspect(__MODULE__)} task started", node: Node.self())
            {:noreply, %RunnerState{state | task_pid: task_pid, monitor_ref: ref, status: :running}}

          {:error, reason} ->
            Logger.error("#{inspect(__MODULE__)} failed to start task", node: Node.self(), reason: reason)
            {:stop, reason, state}
        end
      end

      @impl GenServer
      def handle_call(:status, _from, %RunnerState{} = state) do
        {:reply, state.status, state}
      end

      @impl GenServer
      def handle_info({:DOWN, ref, :process, _pid, reason}, %RunnerState{} = state) when ref == state.monitor_ref do
        Logger.debug("#{inspect(__MODULE__)} task finished unexpectedly", node: Node.self(), reason: reason)
        {:stop, reason, state}
      end

      @impl GenServer
      def handle_info({:result, result}, %RunnerState{} = state) do
        Logger.debug("#{inspect(__MODULE__)} task completed successfully", node: Node.self())
        {:stop, :normal, %RunnerState{state | status: :completed, result: result}}
      end

      @impl GenServer
      def handle_info(_msg, %RunnerState{} = state) do
        {:noreply, state}
      end

      @impl GenServer
      def terminate(reason, %RunnerState{} = state) do
        state
        |> maybe_stop_task(reason)
        |> maybe_teardown(reason, Map.get(state, :result, nil))
      end

      defp maybe_setup() do
        cond do
          function_exported?(__MODULE__, :setup, 0) -> apply(__MODULE__, :setup, [])
          true -> {:ok, nil}
        end
      end

      defp start_task(%RunnerState{} = state) do
        cond do
          function_exported?(__MODULE__, :setup, 0) and function_exported?(__MODULE__, :run, 1) ->
            Task.start_link(fn -> send(self(), {:result, apply(__MODULE__, :run, [state.task_state])}) end)

          true ->
            Task.start_link(fn -> send(self(), {:result, apply(__MODULE__, :run, [])}) end)
        end
      end

      defp maybe_stop_task(
             %RunnerState{task_pid: task_pid, monitor_ref: monitor_ref, shutdown: shutdown} = state,
             reason
           )
           when is_pid(task_pid) and is_reference(monitor_ref) do
        cond do
          Process.alive?(task_pid) ->
            Process.exit(task_pid, reason)

            receive do
              {:DOWN, ^monitor_ref, :process, _pid, reason} ->
                Logger.debug("#{inspect(__MODULE__)} task shutdown confirmed with reason #{inspect(reason)}", node: Node.self())
            after
              shutdown -> Logger.warning("#{inspect(__MODULE__)} task did not shut down in time", node: Node.self())
            end

            Process.demonitor(monitor_ref, [:flush])

            %{state | task_pid: nil, monitor_ref: nil}

          true ->
            Logger.debug("#{inspect(__MODULE__)} task already stopped", node: Node.self())
            state
        end
      end

      defp maybe_teardown(%RunnerState{task_state: task_state} = state, reason, result) do
        cond do
          function_exported?(__MODULE__, :teardown, 3) -> apply(__MODULE__, :teardown, [reason, result, task_state])
          true -> {:ok, state}
        end
      end
    end
  end

  defmacro __before_compile__(env) do
    # we want to ensure that the module implements the required callbacks and help guide the
    # developer to the correct implementation

    # First we want to ensure that the module implements either `run/0` or `run/1` but not both
    # Second we want to ensure that if `run/1` is implemented, `setup/0` is also implemented
    quote location: :keep do
      unless Module.defines?(unquote(env.module), {:run, 0}) or Module.defines?(unquote(env.module), {:run, 1}) do
        raise "#{inspect(unquote(env.module))} must implement either `run/0` or `run/1` but not both"
      end

      if Module.defines?(unquote(env.module), {:run, 0}) and Module.defines?(unquote(env.module), {:run, 1}) do
        raise "#{inspect(unquote(env.module))} implements both `run/0` and `run/1`, but only one is allowed"
      end

      if Module.defines?(unquote(env.module), {:run, 1}) and not Module.defines?(unquote(env.module), {:setup, 0}) do
        raise "#{inspect(unquote(env.module))} implements `run/1`, but `setup/0` is required when `run/1` is defined"
      end
    end
  end
end
