defmodule DaedalRemote.DynamicSupervisor do
  @moduledoc """
  `#{inspect(__MODULE__)}` is the supervisor responsible for managing the active remote processes.
  """

  use DynamicSupervisor

  require Logger

  # Public API
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_child(DaedalRemote.Runner, module, opts \\ []) do
    with {:module, module} <- Code.ensure_loaded(module),
         true <- DaedalRemote.Runner.implements_behaviour?(module) do
      DynamicSupervisor.start_child(__MODULE__, module.child_spec(opts))
    else
      {:error, reason} ->
        {:error, reason}

      false ->
        Logger.error("Module #{inspect(module)} does not implement the DaedalRemote.Runner behaviour")
        {:error, {:behaviour_not_implemented, DaedalRemote.Runner, module}}
    end
  end

  @impl DynamicSupervisor
  def init(opts) do
    opts
    |> Keyword.validate!(strategy: :one_for_one)
    |> DynamicSupervisor.init()
  end
end
