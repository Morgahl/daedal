defmodule DaedalBeacon.Deployment do
  @moduledoc """
   `DaedalBeacon.Deployment` is a struct that represents a deployment in the Beacon server. This is
   used to keep track of the deployments that have registered with the Beacon server.
  """

  defmodule Applications do
    defstruct [
      :name,
      :version,
      :description,
      :spec
    ]

    @type t :: %{
            name: atom(),
            version: String.t(),
            description: String.t(),
            spec: Keyword.t()
          }

    @spec new() :: [t()]
    def new do
      for {app, description, version} <- :application.which_applications() do
        spec = Application.spec(app)

        {app,
         %__MODULE__{
           name: app,
           version: List.to_string(version),
           description: List.to_string(description),
           spec: Keyword.drop(spec, [:description, :vsn])
         }}
      end
      |> Enum.sort_by(&elem(&1, 0))
    end
  end

  defmodule CPUInfo do
    @derive {Inspect, except: [:cpu_topology]}

    defstruct [
      :cpu_topology,
      :smp_support,
      :dirty_cpu_schedulers,
      :dirty_io_schedulers,
      :emu_flavor
    ]

    @type t :: %__MODULE__{
            cpu_topology: list(),
            smp_support: boolean(),
            dirty_cpu_schedulers: integer(),
            dirty_io_schedulers: integer(),
            emu_flavor: atom()
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        cpu_topology: :erlang.system_info(:cpu_topology),
        smp_support: :erlang.system_info(:smp_support),
        dirty_cpu_schedulers: :erlang.system_info(:dirty_cpu_schedulers),
        dirty_io_schedulers: :erlang.system_info(:dirty_io_schedulers),
        emu_flavor: :erlang.system_info(:emu_flavor)
      }
    end
  end

  defmodule OSInfo do
    defstruct [
      :time_warp_mode,
      :kernel_poll,
      :threads,
      :system_architecture,
      :wordsize
    ]

    @type t :: %__MODULE__{
            time_warp_mode: atom(),
            kernel_poll: boolean(),
            threads: boolean(),
            system_architecture: String.t(),
            wordsize: 4 | 8
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        time_warp_mode: :erlang.system_info(:time_warp_mode),
        kernel_poll: :erlang.system_info(:kernel_poll),
        threads: :erlang.system_info(:threads),
        system_architecture: List.to_string(:erlang.system_info(:system_architecture)),
        wordsize: :erlang.system_info(:wordsize)
      }
    end
  end

  defmodule VersionInfo do
    defstruct [
      :otp_release,
      :erts_version,
      :emu_type
    ]

    @type t :: %__MODULE__{
            otp_release: String.t(),
            erts_version: String.t(),
            emu_type: atom()
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        otp_release: List.to_string(:erlang.system_info(:otp_release)),
        erts_version: List.to_string(:erlang.system_info(:version)),
        emu_type: :erlang.system_info(:emu_type)
      }
    end
  end

  defmodule SystemInfo do
    defstruct [
      :os_info,
      :cpu_info,
      :version_info
    ]

    @type t :: %__MODULE__{
            os_info: OSInfo.t(),
            cpu_info: CPUInfo.t(),
            version_info: VersionInfo.t()
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        os_info: OSInfo.new(),
        cpu_info: CPUInfo.new(),
        version_info: VersionInfo.new()
      }
    end
  end

  @derive {Inspect, except: [:applications]}

  defstruct [
    :node,
    :name,
    :version,
    :applications,
    :system_info,
    :neighbors,
    :daedal_remote_tasks,
    :metadata
  ]

  @type t :: %__MODULE__{
          node: atom(),
          name: atom(),
          version: any(),
          applications: [Applications.t()],
          system_info: SystemInfo.t(),
          neighbors: [{:visible, [atom()]} | {:hidden, [atom()]}],
          daedal_remote_tasks: [module()],
          metadata: Keyword.t()
        }

  @spec new() :: t()
  @spec new(Keyword.t()) :: t()
  def new(metadata \\ []) do
    app = get_application()

    version =
      case get_application_key(app, :vsn) do
        version when is_list(version) -> List.to_string(version)
        version -> version
      end

    %__MODULE__{
      node: Node.self(),
      name: app,
      version: version,
      applications: Applications.new(),
      system_info: SystemInfo.new(),
      neighbors: get_neighbors(),
      daedal_remote_tasks: DaedalRemote.Task.implementing_modules(),
      metadata: metadata
    }
  end

  defp get_application() do
    case :application.get_application() do
      {:ok, app} -> app
      :undefined -> :undefined
    end
  end

  defp get_application_key(:undefined, _), do: :undefined

  defp get_application_key(app, key) do
    case :application.get_key(app, key) do
      {:ok, value} -> value
      :undefined -> :undefined
    end
  end

  defp get_neighbors() do
    [
      {:visible, Node.list() |> Enum.sort()},
      {:hidden, Node.list(:hidden) |> Enum.sort()}
    ]
  end
end
