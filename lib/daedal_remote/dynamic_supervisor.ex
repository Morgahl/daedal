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

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl DynamicSupervisor
  def init(opts) do
    opts
    |> Keyword.validate!(strategy: :one_for_one)
    |> DynamicSupervisor.init()
  end
end
