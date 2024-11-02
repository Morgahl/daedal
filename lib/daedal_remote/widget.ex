defmodule DaedalRemote.Widget do
  @moduledoc """
  `#{inspect(__MODULE__)}` is the GenServer responsible for managing the remote interface for
  Daedal. It is responsible for the common administrative and utility interface for the Remote context.
  """

  use Daedal.GenServer

  require Logger

  alias DaedalRemote.LoggerToggle

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    LoggerToggle.init()
    {:ok, opts}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    LoggerToggle.deinit()
    :ok
  end

  @impl GenServer
  def handle_call({:logger_toggle, level}, _from, state) do
    case level do
      :reset ->
        {:reply, LoggerToggle.reset(), state}

      _ ->
        {:reply, LoggerToggle.set(level), state}
    end
  end
end
