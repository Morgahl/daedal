defmodule DaedalRemote.Logger.LoggerHelper do
  @moduledoc false

  @compile_time_purge_level Application.compile_env(:logger, :compile_time_purge_level, :debug)
  @compiled_levels Enum.reject(Logger.levels(), &match?(:lt, Logger.compare_levels(&1, @compile_time_purge_level)))
  @patchable_levels Enum.map(@compiled_levels, fn level -> {level, 2} end)

  @doc false
  def compiled_levels, do: @compiled_levels

  @doc false
  def patchable_levels, do: dbg(@patchable_levels)

  @doc false
  def argv(arity), do: Enum.map(1..arity, &Macro.var(:"var_#{&1}", nil))

  defmacro inject_logger_metadata(md) do
    quote do
      Logger.metadata()
      |> Keyword.merge(module: __MODULE__, file: __ENV__.file, line: __ENV__.line, pid: self())
      |> Keyword.merge(unquote(md))
    end
  end
end
