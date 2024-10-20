defmodule Daedal.Beacon do
  use Ash.Domain

  resources do
    resource Daedal.Beacon.Deployment
  end
end
