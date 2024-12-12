defmodule Daedal.Behaviour do
  @moduledoc """
  `#{inspect(__MODULE__)}` wraps
  """

  # @callback child_spec(opts :: Keyword.t) :: Supervisor.child_spec()
  # @callback implements_behaviour?(module :: module()) :: boolean()

  defmacro __using__(behaviour) do
    quote do
      @behaviour true
    end
  end

  def inject_behaviour(behaviour) do
  end
end
