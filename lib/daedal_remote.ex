defmodule DaedalRemote do
  use Daedal.Supervisor

  @impl Daedal.Supervisor
  def child_specs(opts) do
    [
      DaedalBeacon.Pinger.child_spec(Keyword.get(opts, :pinger_opts, [])),
      DaedalRemote.DynamicSupervisor.child_spec(Keyword.get(opts, :dynamic_supervisor_opts, []))
    ]
  end
end
