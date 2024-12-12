defmodule DaedalRemote.Task do
  alias DaedalRemote.Task.Server, as: TaskServer

  @type status :: :starting | :running | :completed | {:failed, any()}
  @type progress :: non_neg_integer() | float() | {non_neg_integer(), non_neg_integer() | :infinity}

  @type setup_result :: any()
  @type run_result :: nil | any()
  @type teardown_result :: any()

  @callback setup(args :: any()) :: {:ok, setup_result()} | {:error, any()}
  @callback run(setup_result()) :: run_result()
  @callback teardown(reason :: any(), progress(), run_result()) :: {:ok, teardown_result()} | {:error, any()}

  @default_opts [shutdown: 30_000]
  defmacro __using__(opts) do
    opts =
      Keyword.validate!(opts, @default_opts)
      |> Keyword.put(:module, __CALLER__.module)

    quote location: :keep do
      @behaviour DaedalRemote.Task
      use DaedalRemote.Logger

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts), do: DaedalRemote.Task.Server.child_spec(Keyword.merge(opts, unquote(opts)))

      @spec progress(DaedalRemote.Task.progress()) :: :ok
      def progress(progress), do: DaedalRemote.Task.Server.progress(__MODULE__, progress)

      @spec start(Keyword.t()) :: {:running, pid()} | {:error, any()}
      def start(args, opts \\ []), do: DaedalRemote.Task.start(__MODULE__, args, Keyword.merge(opts, unquote(opts)))

      @spec stop() :: :stopped | {:error, any()}
      def stop(), do: DaedalRemote.Task.stop(__MODULE__)

      @spec status(log_n :: non_neg_integer() | :infinity, timeout()) ::
              {DaedalRemote.Task.status(), DaedalRemote.Task.progress(), [DaedalRemote.Task.Server.log()]} | {:error, any()}
      def status(log_n \\ 10, timeout \\ :timer.seconds(5)), do: DaedalRemote.Task.status(__MODULE__, log_n, timeout)

      @spec result(timeout()) :: DaedalRemote.Task.run_result() | {:status, DaedalRemote.Task.status()} | {:failed, any()}
      def result(timeout \\ :timer.seconds(5)), do: DaedalRemote.Task.result(__MODULE__, timeout)
    end
  end

  @spec start(module(), any(), keyword()) :: {:running, pid()} | {:error, any()}
  def start(module, args, opts \\ []) do
    opts = Keyword.merge(opts, extra_args: args)

    with {:module, module} <- Code.ensure_loaded(module),
         true <- implements_behaviour?(module),
         {:ok, pid} <- DynamicSupervisor.start_child(DaedalRemote.DynamicSupervisor, module.child_spec(opts)) do
      {:running, pid}
    else
      {:error, reason} -> {:error, {reason, module}}
      false -> {:error, {:behaviour_not_implemented, module}}
    end
  end

  @spec stop(module()) :: :stopped | {:error, any()}
  def stop(module) do
    with {:module, module} <- Code.ensure_loaded(module),
         true <- implements_behaviour?(module),
         pid when is_pid(pid) <- Process.whereis(module),
         :ok <- DynamicSupervisor.terminate_child(DaedalRemote.DynamicSupervisor, pid) do
      :stopped
    else
      nil -> {:error, {:not_found, module}}
      {:error, reason} -> {:error, {reason, module}}
      false -> {:error, {:behaviour_not_implemented, module}}
    end
  end

  @spec status(module(), non_neg_integer(), timeout()) :: {status(), progress(), [TaskServer.log()]}
  def status(module, log_n \\ 10, timeout \\ :timer.seconds(5)), do: TaskServer.status(module, log_n, timeout)

  @spec result(module(), timeout()) :: run_result() | {:status, status()} | {:failed, any()}
  def result(module, timeout \\ :timer.seconds(5)), do: TaskServer.result(module, timeout)

  @spec implementing_modules() :: [module()]
  def implementing_modules() do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&implements_behaviour?/1)
  end

  @spec implements_behaviour?(module()) :: boolean()
  def implements_behaviour?(module) do
    function_exported?(module, :setup, 1) and
      function_exported?(module, :run, 1) and
      function_exported?(module, :teardown, 3)
  end
end
