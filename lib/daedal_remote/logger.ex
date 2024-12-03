defmodule DaedalRemote.Logger do
  require DaedalRemote.Logger.LoggerHelper, as: LoggerHelper
  require Logger

  @type level :: Logger.level()

  @type logger_callback :: (level(), DateTime.t(), binary(), Keyword.t() -> :ok)

  @patched [{:log, 3} | LoggerHelper.patchable_levels()]

  defmacro __using__(_opts) do
    quote do
      require Logger, as: RealLogger
      alias unquote(__MODULE__), as: Logger
    end
  end

  @doc """
  Sets up the logger with the given callback function. The callback function will be called with the
  log level, message, and metadata for each log message. Optionally, you can pass metadata that will
  be included in all log messages. By default, the node name will be included in all log messages.
  """
  @spec setup(logger_callback) :: :ok
  def setup(logger_cb \\ nil, md \\ []) do
    Process.put(:logger_callback, logger_cb)
    Logger.metadata(Keyword.merge(md, node: Node.self()))
  end

  for level <- Logger.levels() do
    @doc """
    Logs a message at the `#{inspect(level)}` level.
    """
    @spec unquote(level)(binary(), Keyword.t()) :: Macro.t()
    defmacro unquote(level)(msg, md \\ []), do: log(unquote(level), msg, md)
  end

  # Private API

  # This macro is used to patch the Logger module to include the logger callback use at runtime.
  defp log(level, msg, md) do
    quote do
      import LoggerHelper, only: [inject_logger_metadata: 1]
      level = unquote(level)
      msg = unquote(msg)
      md = unquote(md)
      Logger.log(level, msg, md)

      case Process.get(:logger_callback, nil) do
        cb when is_function(cb, 4) -> cb.(level, DateTime.utc_now(), msg, inject_logger_metadata(md))
        _ -> :ok
      end
    end
  end

  for {func, arity} <- Logger.__info__(:functions) ++ Logger.__info__(:macros),
      {func, arity} not in @patched do
    args =
      for i <- 1..arity//1 do
        Macro.var(:"var_#{i}", nil)
      end

    quote do
      defdelegate unquote(func)(unquote_splicing(args)), to: Logger
    end
  end
end
