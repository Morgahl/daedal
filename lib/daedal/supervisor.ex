defmodule Daedal.Supervisor do
  @moduledoc """
  `Daedal.Supervisor` is a behaviour module that provides a common interface for defining a
  supervisor. This reserves the following key in the opts passed to the `start_link/1` function:
  - `:supervisor_opts` - the options to pass to the supervisor
  - All other keys are passed to the `child_specs/1` callback with the `:supervisor_opts` removed.

  The `Daedal.Supervisor` behaviour requires the following callbacks:
  - `child_specs/1` - returns a list of child specs for the supervisor which is passed the `:child_opts`
  """

  defmacro __using__(_opts) do
    quote do
      use Supervisor
      @behaviour unquote(__MODULE__)

      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(opts) do
        with {:ok, supervisor_opts, child_opts} <- Daedal.Supervisor.validate_opts(opts),
             child_specs <- child_specs(child_opts) do
          Supervisor.init(child_specs, supervisor_opts)
        end
      end
    end
  end

  @callback child_specs(opts :: Keyword.t()) :: [Supervisor.child_spec()]

  @default_opts [
    auto_shutdown: :never,
    strategy: :one_for_one
  ]

  def validate_opts(opts) do
    opts
    |> Keyword.get(:supervisor_opts, @default_opts)
    |> Keyword.validate(@default_opts)
    |> case do
      {:ok, validated_opts} -> {:ok, validated_opts, Keyword.delete(opts, :supervisor_opts)}
      {:error, reason} -> {:error, reason}
    end
  end
end
