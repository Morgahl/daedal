defmodule Daedal.GenServer do
  defmacro __using__(opts) do
    inject_behaviour_hook = Keyword.get(opts, :behaviour_hook, true)

    quote do
      use GenServer
      use Daedal.BehaviourHook
      import Daedal.GenServer
      require Logger

      if unquote(inject_behaviour_hook) do
        defmacrop before_init(args) do
          quote location: :keep do
            Logger.info(
              "Starting #{inspect(__MODULE__)} with args #{inspect(unquote(args))}",
              node: Node.self(),
              ansi_color: :green
            )

            Process.flag(:trap_exit, true)

            System.monotonic_time()
          end
        end

        @impl GenServer
        def handle_info({:EXIT, _pid, reason}, state) do
          Logger.error(
            "Exiting #{inspect(__MODULE__)} with reason: #{inspect(reason)}",
            node: Node.self(),
            ansi_color: :magenta
          )

          {:stop, reason, state}
        end

        defoverridable handle_info: 2

        defmacrop after_init(result, before, _args) do
          quote location: :keep do
            Logger.info(
              "Started #{inspect(__MODULE__)} with result #{inspect(unquote(result))}",
              node: Node.self(),
              took: since(unquote(before), :microsecond),
              ansi_color: :green
            )
          end
        end

        defmacrop before_terminate(reason, _state) do
          quote location: :keep do
            Logger.info(
              "Terminating #{inspect(__MODULE__)} with reason #{inspect(unquote(reason))}",
              node: Node.self(),
              ansi_color: :magenta
            )

            System.monotonic_time()
          end
        end

        defmacrop after_terminate(result, before, _reason, _state) do
          quote location: :keep do
            Logger.info(
              "Terminated #{inspect(__MODULE__)} with result #{inspect(unquote(result))}",
              node: Node.self(),
              took: since(unquote(before), :microsecond),
              ansi_color: :magenta
            )
          end
        end
      end
    end
  end

  defmacro since(instant, time_unit) when time_unit in [:second, :millisecond, :microsecond, :nanosecond] do
    unit =
      case time_unit do
        :second -> "s"
        :millisecond -> "ms"
        :microsecond -> "μs"
        :nanosecond -> "ns"
      end

    quote do
      took = (System.monotonic_time(:native) - unquote(instant)) / System.convert_time_unit(1, unquote(time_unit), :native)
      "#{took}#{unquote(unit)}"
    end
  end
end
