defmodule DaedalRemote do
  use Daedal.Supervisor

  @impl Daedal.Supervisor
  def child_specs(opts) do
    [
      DaedalBeacon.Pinger.child_spec(Keyword.get(opts, :pinger_opts, [])),
      DaedalRemote.DynamicSupervisor.child_spec(Keyword.get(opts, :dynamic_supervisor_opts, []))
    ]
  end

  defdelegate start_task(module, args, opts \\ []), to: DaedalRemote.Task, as: :start
  defdelegate stop_task(module), to: DaedalRemote.Task, as: :stop
  defdelegate task_status(module, log_n \\ 10, timeout \\ :timer.seconds(5)), to: DaedalRemote.Task, as: :status
  defdelegate task_result(module, timeout \\ :timer.seconds(5)), to: DaedalRemote.Task, as: :result
  defdelegate task_modules(), to: DaedalRemote.Task, as: :implementing_modules
end
