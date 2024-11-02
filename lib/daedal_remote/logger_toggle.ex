defmodule DaedalRemote.LoggerToggle do
  @logger_levels [:all, :none | Logger.levels()] |> Enum.uniq()
  @moduledoc """
  Provides functionality to toggle the logging level dynamically in an Elixir application,
  while safely storing and restoring the original logging level.

  ## Usage

  To use this module, you should start by initializing the ETS table with `init/0`, then use `set/1` to change the logging level,
  and `reset/0` to revert to the original level stored. The module ensures that the original level is preserved safely until explicitly reset.

      #{inspect(__MODULE__)}.init()
      #{inspect(__MODULE__)}.set(:debug)
      #{inspect(__MODULE__)}.reset()

  The convenience functions can be used to easily switch to specific logging levels:
      #{inspect(__MODULE__)}.debug()
      #{inspect(__MODULE__)}.info()

  This module is particularly useful in environments where dynamic logging level changes are necessary,
  such as during development, testing, or production debugging.

  The available convenience functions are:
  #{for(level <- @logger_levels, do: "  - #{level}/0") |> Enum.sort() |> Enum.join("\n")}
  """

  @type logger_level :: :all | :none | Logger.level()

  @doc """
  Initializes the ETS table. This should be called when the application starts.
  """
  @spec init() :: :ets.tid()
  def init, do: :ets.new(__MODULE__, [:set, :protected, :named_table, read_concurrency: true])

  @doc """
  Deinitializes the ETS table. This should be called when the application stops.
  """
  @spec deinit() :: :ok
  def deinit do
    with :ok <- reset(),
         true <- :ets.delete(__MODULE__) do
      :ok
    end
  end

  @doc """
  Sets the logging level and stores the previous level in an ETS table if it hasn't been set yet. Returns :ok.
  """
  @spec set(logger_level()) :: :ok
  def set(new_level) when new_level in @logger_levels do
    case :ets.lookup(__MODULE__, :old_level) do
      [] ->
        # Only insert the old level if it hasn't been stored yet.
        :ets.insert(__MODULE__, {:old_level, Logger.level()})

      _ ->
        # If already stored, do not overwrite.
        :ok
    end

    Logger.configure(level: new_level)
    :ok
  end

  def set(level), do: {:error, "Invalid logger level: #{inspect(level)}. Supported levels are: #{inspect(@logger_levels)}"}

  @doc """
  Resets the logging level to the previously stored value in the ETS table.
  If no previous level was stored, maintains the current level and returns :ok.
  """
  @spec reset() :: :ok
  def reset do
    case :ets.lookup(__MODULE__, :old_level) do
      [] ->
        :ok

      [{:old_level, old_level}] ->
        Logger.configure(level: old_level)
        :ets.delete(__MODULE__, :old_level)
        :ok
    end
  end

  @doc """
  Returns the list of supported logger levels.
  """
  @spec logger_levels() :: [logger_level()]
  def logger_levels, do: @logger_levels

  # Convenience functions for setting the logging level enumerated from the list of supported levels
  # derived from Logger.levels() and the additional :all and :none levels.
  for level <- @logger_levels do
    @doc """
    Sets the logging level to `#{inspect(level)}`. Returns :ok.
    """
    @spec unquote(level)() :: :ok
    def unquote(level)(), do: set(unquote(level))
  end
end
