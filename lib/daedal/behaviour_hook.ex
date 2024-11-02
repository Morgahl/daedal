defmodule Daedal.BehaviourHook do
  defmacro __using__(_opts) do
    quote location: :keep do
      unless Module.has_attribute?(__MODULE__, :daedal_hook_targets) do
        Module.register_attribute(__MODULE__, :daedal_hooked, accumulate: true)
        @on_definition Daedal.BehaviourHook
        @before_compile Daedal.BehaviourHook
      else
        Module.delete_attribute(__MODULE__, :daedal_hook_targets)
      end

      Module.get_attribute(__MODULE__, :behaviour)
      |> Enum.flat_map(fn module -> module.behaviour_info(:callbacks) end)
      |> Enum.dedup()
      |> Enum.sort()
      |> then(&Module.put_attribute(__MODULE__, :daedal_hook_targets, &1))
    end
  end

  def __on_definition__(env, kind, name, args, _guards, _body) do
    for arity <- arity_variants(args) do
      with true <- {name, arity} in Module.get_attribute(env.module, :daedal_hook_targets),
           false <- Enum.any?(Module.get_attribute(env.module, :daedal_hooked), &match?({_, ^kind, ^name, ^arity}, &1)) do
        Module.put_attribute(env.module, :daedal_hooked, {env, kind, name, arity})
      end
    end
  end

  defmacro __before_compile__(env) do
    hooked = Module.get_attribute(env.module, :daedal_hooked) |> Enum.reverse()
    Module.delete_attribute(env.module, :daedal_hooked)

    for {def_env, kind, name, arity} <- hooked do
      args = generate_args(arity, nil)
      before_hook = :"before_#{name}"
      after_hook = :"after_#{name}"

      case {
        Module.defines?(env.module, {before_hook, arity}),
        Module.defines?(env.module, {after_hook, arity + 2})
      } do
        {false, false} ->
          nil

        {true, false} ->
          quote line: def_env.line do
            unquote(before_hook)(unquote_splicing(args))
            super(unquote_splicing(args))
          end

        {false, true} ->
          quote line: def_env.line do
            result = super(unquote_splicing(args))
            unquote(after_hook)(result, unquote_splicing(args))
            result
          end

        {true, true} ->
          quote line: def_env.line do
            before = unquote(before_hook)(unquote_splicing(args))
            result = super(unquote_splicing(args))
            unquote(after_hook)(result, before, unquote_splicing(args))
            result
          end
      end
      |> override(kind, name, args)
    end
  end

  # We need to account for variants defined as `var \\ default` and how that affects the definition
  # of the targeted function
  defp arity_variants(args) do
    max = length(args)
    min = length(for arg <- args, !match?({:\\, _, _}, arg), do: arg)
    min..max//1
  end

  # We want to silently skip the generation of overrides if no actual hook is being defined.
  defp override(nil, _, _, _), do: nil

  defp override(body, kind, name, args) do
    quote do
      defoverridable [{unquote(name), unquote(length(args))}]
      Kernel.unquote(kind)(unquote(name)(unquote_splicing(args)), do: unquote(body))
    end
  end

  defp generate_args(0, _caller), do: []
  defp generate_args(n, caller), do: for(i <- 1..n, do: Macro.var(:"var_#{i}", caller))
end
