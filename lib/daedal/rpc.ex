defmodule Daedal.RPC do
  @moduledoc """
  `Daedal.Rpc` is a context that defines the RPC process that `Daedal` uses to interact with the
  nodes in distributed clusters.
  """

  @default_timeout 5000

  @type cookie :: atom()
  @type args :: [term()]

  @type nodes :: [node() | {node(), cookie()}]

  @type exit_reasons :: term()
  @type error_reasons :: term()

  @type cast_result :: :ok | {:throw, term()} | {:exit, exit_reasons()} | {:error, error_reasons()}
  @type call_result(type) :: {:ok, type} | {:throw, term()} | {:exit, exit_reasons()} | {:error, error_reasons()}
  @type multicall_result(type) :: [call_result(type)]
  @type multicast_result :: [cast_result()]

  @spec connect_hidden(node(), cookie()) :: boolean() | :ignored
  def connect_hidden(node, cookie) do
    node
    |> prep_cookie(cookie)
    |> :net_kernel.hidden_connect_node()
  end

  @spec call(node(), cookie(), function()) :: call_result(term())
  @spec call(node(), cookie(), function(), timeout()) :: call_result(term())
  def call(node, cookie, function, timeout \\ @default_timeout) do
    node
    |> prep_cookie(cookie)
    |> :erpc.call(function, timeout)
    |> then(&{:ok, &1})
  catch
    :exit, reason -> {:exit, reason}
    :error, reason -> {:error, reason}
  end

  @spec call(node(), cookie(), module(), function :: atom(), args()) :: call_result(term())
  @spec call(node(), cookie(), module(), function :: atom(), args(), timeout()) :: call_result(term())
  def call(node, cookie, module, function, args, timeout \\ @default_timeout) do
    node
    |> prep_cookie(cookie)
    |> :erpc.call(module, function, args, timeout)
    |> then(&{:ok, &1})
  catch
    :exit, reason -> {:exit, reason}
    :error, reason -> {:error, reason}
  end

  @spec call!(node(), cookie(), function()) :: term()
  @spec call!(node(), cookie(), function(), timeout()) :: term()
  def call!(node, cookie, function, timeout \\ @default_timeout) do
    case call(node, cookie, function, timeout) do
      {:ok, result} -> result
      {:exit, reason} -> raise reason
      {:error, reason} -> raise reason
    end
  end

  @spec call!(node(), cookie(), module(), function :: atom(), args()) :: term()
  @spec call!(node(), cookie(), module(), function :: atom(), args(), timeout()) :: term()
  def call!(node, cookie, module, function, args, timeout \\ @default_timeout) do
    case call(node, cookie, module, function, args, timeout) do
      {:ok, result} -> result
      {:exit, reason} -> raise reason
      {:error, reason} -> raise reason
    end
  end

  @spec cast(node(), cookie(), function()) :: cast_result()
  def cast(node, cookie, function) do
    node
    |> prep_cookie(cookie)
    |> :erpc.cast(function)
  catch
    :exit, reason -> {:exit, reason}
    :error, reason -> {:error, reason}
  end

  @spec cast(node(), cookie(), module(), function :: atom(), args()) :: cast_result()
  def cast(node, cookie, module, function, args) do
    node
    |> prep_cookie(cookie)
    |> :erpc.cast(module, function, args)
  catch
    :exit, reason -> {:exit, reason}
    :error, reason -> {:error, reason}
  end

  @spec cast!(node(), cookie(), function()) :: :ok
  def cast!(node, cookie, function) do
    case cast(node, cookie, function) do
      :ok -> :ok
      {:exit, reason} -> raise reason
      {:error, reason} -> raise reason
    end
  end

  @spec cast!(node(), cookie(), module(), function :: atom(), args()) :: :ok
  def cast!(node, cookie, module, function, args) do
    case cast(node, cookie, module, function, args) do
      :ok -> :ok
      {:exit, reason} -> raise reason
      {:error, reason} -> raise reason
    end
  end

  @spec multicall(nodes(), function()) :: [{node(), call_result(term())}]
  @spec multicall(nodes(), function(), timeout()) :: [{node(), call_result(term())}]
  def multicall(node_and_cookies, function, timeout \\ @default_timeout) do
    node_and_cookies
    |> prep_cookies()
    |> :erpc.multicall(function, timeout)
    |> handle_multicall_result(node_and_cookies)
  end

  @spec multicall(nodes(), module(), function :: atom(), args()) :: [{node(), call_result(term())}]
  @spec multicall(nodes(), module(), function :: atom(), args(), timeout()) :: [{node(), call_result(term())}]
  def multicall(node_and_cookies, module, function, args, timeout \\ @default_timeout) do
    node_and_cookies
    |> prep_cookies()
    |> :erpc.multicall(module, function, args, timeout)
    |> handle_multicall_result(node_and_cookies)
  end

  @spec multicast(nodes(), function()) :: :ok
  def multicast(node_and_cookies, function) do
    node_and_cookies
    |> prep_cookies()
    |> :erpc.multicast(function)
  end

  @spec multicast(nodes(), module(), function :: atom(), args()) :: :ok
  def multicast(node_and_cookies, module, function, args) do
    node_and_cookies
    |> prep_cookies()
    |> :erpc.multicast(module, function, args)
  end

  @spec prep_cookies(nodes()) :: [node()]
  defp prep_cookies(node_and_cookies) do
    Enum.map(node_and_cookies, &prep_cookie/1)
  end

  # Prepares the cookie for the node if it is not already set to the provided cookie.
  @spec prep_cookie({node(), cookie()} | node()) :: node()
  defp prep_cookie({node, cookie}), do: prep_cookie(node, cookie)
  defp prep_cookie(node), do: node

  @spec prep_cookie(node(), cookie()) :: cookie()
  defp prep_cookie(node, cookie) do
    match?(^cookie, :erlang.get_cookie(node)) or Node.set_cookie(node, cookie)
    node
  end

  @spec handle_multicall_result(multicall_result(term()), nodes()) :: [{node(), call_result(term())}]
  defp handle_multicall_result(results, node_and_cookies) do
    Enum.zip_with([node_and_cookies, results], fn
      [{node, _cookie}, result] -> {node, result}
      [node, reason] -> {node, reason}
    end)
  end
end
