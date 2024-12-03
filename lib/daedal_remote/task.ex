defmodule DaedalRemote.Task do
  @type setup_result :: any()
  @type run_result :: nil | any()
  @type teardown_result :: any()

  @callback setup(args :: any()) :: {:ok, setup_result()} | {:error, any()}
  @callback run(setup_result()) :: run_result()
  @callback teardown(reason :: any(), progress(), run_result()) :: {:ok, teardown_result()} | {:error, any()}

  @type progress :: non_neg_integer() | float() | {non_neg_integer(), non_neg_integer() | :infinity}

  @default_opts [shutdown: 30_000]
  defmacro __using__(opts) do
    opts =
      Keyword.validate!(opts, @default_opts)
      |> Keyword.put(:module, __CALLER__.module)

    quote location: :keep do
      @behaviour DaedalRemote.Task
      use DaedalRemote.Logger
      alias DaedalRemote.Task.Server, as: TaskServer

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts), do: TaskServer.child_spec(Keyword.merge(opts, unquote(opts)))

      @spec progress(DaedalRemote.Task.progress()) :: :ok
      def progress(progress), do: TaskServer.progress(__MODULE__, progress)

      @spec start(Keyword.t()) :: {:ok, pid()} | {:error, any()}
      def start(args, opts \\ []), do: DaedalRemote.DynamicSupervisor.start_child(DaedalRemote.Task, __MODULE__, args, opts)

      @spec stop() :: {:stopped, __MODULE__} | {:error, any()}
      def stop(), do: DaedalRemote.DynamicSupervisor.stop_child(DaedalRemote.Task, __MODULE__)

      @spec status(non_neg_integer() | :infinity, timeout()) :: {TaskServer.status(), DaedalRemote.Task.progress(), [TaskServer.log()]}
      def status(log_n \\ 10, timeout \\ :timer.seconds(5)), do: TaskServer.status(__MODULE__, log_n, timeout)

      @spec result(timeout()) :: any()
      def result(timeout \\ :timer.seconds(5)), do: TaskServer.result(__MODULE__, timeout)
    end
  end

  @spec implementing_modules() :: [module()]
  def implementing_modules() do
    :code.all_loaded()
    |> Enum.filter(&implements_behaviour?(elem(&1, 0)))
  end

  @spec implements_behaviour?(module()) :: boolean()
  def implements_behaviour?(module) do
    function_exported?(module, :setup, 1) and
      function_exported?(module, :run, 1) and
      function_exported?(module, :teardown, 3)
  end
end
