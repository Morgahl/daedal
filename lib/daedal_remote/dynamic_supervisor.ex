defmodule DaedalRemote.DynamicSupervisor do
  @moduledoc """
  `#{inspect(__MODULE__)}` is the supervisor responsible for managing the active remote processes.
  """

  use DynamicSupervisor

  require Logger

  @runners [
    DaedalRemote.Task
  ]

  # Public API
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def start_child(runner, module, args, opts \\ []) when runner in @runners do
    with {:module, module} <- Code.ensure_loaded(module),
         true <- runner.implements_behaviour?(module),
         {:ok, _pid} <- DynamicSupervisor.start_child(__MODULE__, module.child_spec(Keyword.merge(opts, extra_args: args))) do
      {:running, module}
    else
      {:error, reason} -> {:error, {reason, module}}
      false -> {:error, {:behaviour_not_implemented, module}}
    end
  end

  def stop_child(runner, module) when runner in @runners do
    with {:module, module} <- Code.ensure_loaded(module),
         true <- runner.implements_behaviour?(module),
         pid when is_pid(pid) <- Process.whereis(module),
         :ok <- DynamicSupervisor.terminate_child(__MODULE__, pid) do
      {:stopped, module}
    else
      nil -> {:error, {:not_found, module}}
      {:error, reason} -> {:error, {reason, module}}
      false -> {:error, {:behaviour_not_implemented, module}}
    end
  end

  @impl DynamicSupervisor
  def init(opts) do
    opts
    |> Keyword.validate!(strategy: :one_for_one)
    |> DynamicSupervisor.init()
  end
end
