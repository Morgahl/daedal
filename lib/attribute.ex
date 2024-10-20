defmodule Daedal.Attribute do
  @doc """
  Defines an attribute with the given name, type, and options. This is forced to be public,
  non-writable, and non-nullable. Otherwise all options are passed through to the attribute macro.
  """
  @req_pub_static [
    public?: true,
    allow_nil?: false
  ]

  defmacro primary_pub_static(name, type, description, opts \\ []) when is_atom(name) and is_binary(description) do
    attribute(name, type, enforce_opts(opts, [{:primary_key?, true}, {:description, description} | @req_pub_static]))
  end

  defmacro req_pub_static(name, type, description, opts \\ []) when is_atom(name) and is_binary(description) do
    attribute(name, type, enforce_opts(opts, [{:description, description} | @req_pub_static]))
  end

  defp attribute(name, type, opts) do
    quote do
      attribute unquote(name), unquote(type), unquote(opts)
    end
  end

  defp enforce_opts(opts, kw) do
    opts
    |> Enum.dedup_by(&elem(&1, 0))
    |> Keyword.drop(Keyword.keys(kw))
    |> Keyword.merge(kw)
  end
end
