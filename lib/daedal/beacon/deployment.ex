defmodule Daedal.Beacon.Deployment do
  use Ash.Resource, domain: Daedal.Beacon

  import Daedal.Attribute

  defmodule Application do
    use Ash.Resource, data_layer: :embedded

    import Daedal.Attribute

    attributes do
      req_pub_static :name, :atom, "The application name"
      req_pub_static :description, :string, "A brief description of the application"
      req_pub_static :version, :string, "The application version"
      req_pub_static :spec, :map, "The application specification"
    end
  end

  defmodule CPU do
    use Ash.Resource, data_layer: :embedded

    import Daedal.Attribute

    attributes do
      req_pub_static :cpu_topology, :keyword, "The CPU topology of the node as a hierarchical structure keyword list",
        constraints: [
          fields: [
            processor: [
              type: :keyword,
              constraints: [
                fields: [
                  core: [
                    type: :keyword,
                    constraints: [
                      fields: [
                        thread: [
                          type: :keyword,
                          constraints: [
                            fields: [
                              logical: [
                                type: :integer
                              ]
                            ]
                          ]
                        ]
                      ]
                    ]
                  ]
                ]
              ]
            ]
          ]
        ]

      req_pub_static :smp_support, :boolean, "Whether the node supports SMP"
      req_pub_static :dirty_cpu_schedulers, :integer, "The number of dirty CPU schedulers"
      req_pub_static :dirty_io_schedulers, :integer, "The number of dirty IO schedulers"
      req_pub_static :emu_flavor, :atom, "The emulator flavor"
    end
  end

  defmodule OS do
    use Ash.Resource, data_layer: :embedded

    import Daedal.Attribute

    attributes do
      req_pub_static :time_warp_mode, :atom, "The time warp mode"
      req_pub_static :kernel_poll, :boolean, "Whether the kernel poll is enabled"
      req_pub_static :threads, :boolean, "Whether threads are enabled"
      req_pub_static :system_architecture, :string, "The system architecture string of the node"
      req_pub_static :wordsize, :integer, "The wordsize of the node"
    end
  end

  defmodule Runtime do
    use Ash.Resource, data_layer: :embedded

    import Daedal.Attribute

    attributes do
      req_pub_static :otp_release, :string, "The OTP release version"
      req_pub_static :erts_version, :string, "The Erlang Runtime System version"
      req_pub_static :emu_type, :atom, "The emulator type"
    end
  end

  attributes do
    primary_pub_static :node, :atom, "The node name"
    req_pub_static :name, :atom, "The deployed application name"
    req_pub_static :version, :string, "The deployed application version"
    req_pub_static :applications, {:array, Application}, "The deployed application's dependencies"
    req_pub_static :os_info, OS, "The operating system information of the node"
    req_pub_static :cpu_info, CPU, "The CPU information of the node"
    req_pub_static :runtime_info, Runtime, "The runtime information of the node"
    req_pub_static :metadata, :keyword, "The deployment metadata", constraints: [fields: []]
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      primary? true

      argument :deployment, :struct, constraints: [instance_of: DaedalBeacon.Deployment]

      change fn changeset, context ->
        nil
      end
    end
  end
end
